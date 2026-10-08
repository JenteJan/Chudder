import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/models/subtitles/subtitle_text_tools.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/subtitles/bazarr_client.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/user_provider.dart';

final _log = Logger('SubtitleFix');

/// Something to put right in a subtitle file, for everyone who plays it.
sealed class SubtitleFix {
  const SubtitleFix();
}

/// Every line earlier or later; positive is later.
class ShiftFix extends SubtitleFix {
  const ShiftFix(this.offset);
  final Duration offset;
}

/// Timed for [from] frames per second, played at [to].
class FrameRateFix extends SubtitleFix {
  const FrameRateFix(this.from, this.to);
  final double from;
  final double to;
}

/// Without the lines written for the hard of hearing.
class RemoveHearingImpairedFix extends SubtitleFix {
  const RemoveHearingImpairedFix();
}

/// Lined up against the video's own audio. Bazarr does this (ffsubsync);
/// the app cannot.
class SyncToAudioFix extends SubtitleFix {
  const SyncToAudioFix();
}

/// Put into another language by Bazarr's translator: a new file next to the
/// old one.
class TranslateFix extends SubtitleFix {
  const TranslateFix(this.toLanguage);

  /// Two letters, as Bazarr takes it.
  final String toLanguage;
}

/// Bazarr's clean-ups for common mistakes: OCR slips (l for I, 0 for O),
/// stray spaces and punctuation.
class CommonErrorsFix extends SubtitleFix {
  const CommonErrorsFix();
}

/// Out of ALL CAPITALS into ordinary sentence case.
class UppercaseFix extends SubtitleFix {
  const UppercaseFix();
}

/// Fixes only Bazarr can make.
bool _bazarrOnly(SubtitleFix fix) =>
    fix is SyncToAudioFix || fix is TranslateFix || fix is CommonErrorsFix || fix is UppercaseFix;

/// The subtitle a fix is for, as the server lists it.
class SubtitleFileRef {
  const SubtitleFileRef({
    required this.itemId,
    required this.index,
    this.mediaSourceId,
    this.path,
    this.codec,
    this.language,
    this.forced = false,
    this.hearingImpaired = false,
    this.isExternal = true,
  });

  final String itemId;
  final String? mediaSourceId;
  final int index;
  final String? path;
  final String? codec;

  /// Three letters, as the server lists it.
  final String? language;
  final bool forced;
  final bool hearingImpaired;
  final bool isExternal;

  String get fileName {
    final value = path ?? '';
    final separator = value.lastIndexOf(RegExp(r'[\\/]'));
    return separator == -1 ? value : value.substring(separator + 1);
  }

  SubtitleTextFormat? get format =>
      subtitleTextFormatOf(codec) ?? subtitleTextFormatOf(path?.split('.').lastOrNull);
}

/// Which fixes can be made to a file, and by whom.
class SubtitleFixPlan {
  const SubtitleFixPlan({
    required this.file,
    this.bazarr,
    this.bazarrFile,
    this.canUpload = false,
    this.isAdmin = false,
  });

  final SubtitleFileRef file;
  final BazarrTarget? bazarr;

  /// The file on Bazarr's side, when Bazarr lists it.
  final BazarrSubtitleFile? bazarrFile;

  /// The app can read the file, change it and give the server the new copy.
  final bool canUpload;
  final bool isAdmin;

  bool get _bazarrMods => bazarrFile != null && (bazarrFile!.path ?? '').endsWith('.srt');

  /// Whether [fix] is Bazarr's to make rather than the app's.
  ///
  /// A move in time is the app's own whenever this account may hand the
  /// server a file: the app shifts the lines itself and the new copy is on
  /// the server when the upload returns. Asked of Bazarr, the answer came
  /// back before the file had been written and the old lines were read
  /// again as the fixed ones.
  bool throughBazarr(SubtitleFix fix) =>
      _bazarrOnly(fix) || (_bazarrMods && !(canUpload && (fix is ShiftFix || fix is FrameRateFix)));

  bool supports(SubtitleFix fix) => switch (fix) {
        SyncToAudioFix() => bazarrFile != null && !file.forced,
        TranslateFix() => bazarrFile != null,
        CommonErrorsFix() || UppercaseFix() => _bazarrMods,
        _ => _bazarrMods || canUpload,
      };

  bool get anything => supports(const ShiftFix(Duration.zero)) || supports(const SyncToAudioFix());

  /// A fix made by the app leaves the old file next to the new one unless
  /// this account may delete it.
  bool leavesCopy(SubtitleFix fix) =>
      fix is! TranslateFix && !throughBazarr(fix) && !(isAdmin && file.isExternal);
}

class SubtitleFixResult {
  const SubtitleFixResult({this.path, this.stream, this.inPlace = false});

  /// Where the fixed subtitle is now.
  final String? path;

  /// The fixed subtitle as the server lists it, once it does.
  final dto.MediaStream? stream;

  /// The file was rewritten under its own name: a player showing it has to
  /// load it again.
  final bool inPlace;
}

class SubtitleFixException implements Exception {
  const SubtitleFixException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum SubtitleFixPhase { working, syncing, translating, adding }

final subtitleFixServiceProvider = Provider.autoDispose((ref) => SubtitleFixService(ref));

class SubtitleFixService {
  SubtitleFixService(this.ref);
  final Ref ref;

  bool get _isAdmin => ref.read(userProvider)?.policy?.isAdministrator == true;

  Future<SubtitleFixPlan> plan(SubtitleFileRef file) async {
    final canUpload = canManageSubtitles(ref.read(userProvider)) && file.format != null;
    final bazarr = ref.read(bazarrClientProvider);
    if (bazarr == null || !file.isExternal || file.path == null) {
      return SubtitleFixPlan(file: file, canUpload: canUpload, isAdmin: _isAdmin);
    }
    try {
      final lookup = await loadSubtitleLookup(ref, itemId: file.itemId, mediaSourceId: file.mediaSourceId);
      var target = lookup.bazarr;
      if (target != null) target = await bazarr.reload(target) ?? target;
      return SubtitleFixPlan(
        file: file,
        bazarr: target,
        bazarrFile: target?.fileNamed(file.fileName),
        canUpload: canUpload,
        isAdmin: _isAdmin,
      );
    } catch (error) {
      _log.warning('Asking Bazarr about ${file.path} failed: $error');
      return SubtitleFixPlan(file: file, canUpload: canUpload, isAdmin: _isAdmin);
    }
  }

  /// Makes [fix] and waits until the server lists the result.
  Future<SubtitleFixResult> apply(
    SubtitleFixPlan plan,
    SubtitleFix fix, {
    void Function(SubtitleFixPhase phase)? onPhase,
  }) async {
    if (!plan.supports(fix)) throw const SubtitleFixException('This fix is not available for this subtitle.');
    _currentItemId = plan.file.itemId;
    _currentSourceId = plan.file.mediaSourceId;
    if (plan.throughBazarr(fix)) return _throughBazarr(plan, fix, onPhase);
    return _inApp(plan, fix, onPhase);
  }

  Future<SubtitleFixResult> _throughBazarr(
    SubtitleFixPlan plan,
    SubtitleFix fix,
    void Function(SubtitleFixPhase phase)? onPhase,
  ) async {
    final bazarr = ref.read(bazarrClientProvider);
    final target = plan.bazarr;
    final file = plan.bazarrFile;
    if (bazarr == null || target == null || file == null) throw const SubtitleFixException('Bazarr is not connected');

    final actions = switch (fix) {
      ShiftFix(:final offset) => [BazarrClient.shiftAction(offset)],
      FrameRateFix(:final from, :final to) => [BazarrClient.frameRateAction(from, to)],
      RemoveHearingImpairedFix() => ['remove_HI'],
      SyncToAudioFix() => ['sync'],
      CommonErrorsFix() => ['OCR_fixes', 'common'],
      UppercaseFix() => ['fix_uppercase'],
      TranslateFix() => const <String>[],
    };

    // What the file says before Bazarr is asked, to know when it says
    // something else. Bazarr answers a tool request before the file has
    // necessarily been written, and nothing below used to check: the file
    // was read again at once, the old lines came back, and the timing the
    // viewer had just set was taken off the player as "in the file now".
    final rewrites = !(fix is RemoveHearingImpairedFix || fix is TranslateFix);
    String? before;
    final format = plan.file.format;
    if (rewrites && format != null) {
      try {
        before = await _download(plan.file, format);
      } catch (error) {
        _log.warning('Reading the subtitle before the fix failed: $error');
      }
    }

    if (fix is SyncToAudioFix) {
      // A sync is a queued job that reports "completed" even when it gave
      // up; the only sure sign it worked is the history entry it writes.
      onPhase?.call(SubtitleFixPhase.syncing);
      final seen = (await bazarr.history(target)).map((e) => e.identity).toSet();
      await _bazarr(() => bazarr.subtitleTool(target, file, actions.single));
      BazarrHistoryEntry? done;
      for (var attempt = 0; attempt < 100 && done == null; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        try {
          done = (await bazarr.history(target)).firstWhereOrNull((e) => !seen.contains(e.identity) && e.action == 5);
        } catch (error) {
          _log.fine('Waiting on the Bazarr sync failed: $error');
        }
      }
      if (done == null) {
        throw const SubtitleFixException("Bazarr couldn't sync this subtitle to the audio. Its log says why.");
      }
    } else if (fix is TranslateFix) {
      onPhase?.call(SubtitleFixPhase.translating);
      await _bazarr(() => bazarr.translate(target, file, fix.toLanguage));
    } else {
      onPhase?.call(SubtitleFixPhase.working);
      for (final action in actions) {
        await _bazarr(() => bazarr.subtitleTool(target, file, action));
      }
    }

    if (before != null && format != null) {
      // A move in time always changes the file; the tidying fixes may find
      // nothing to tidy.
      await _awaitRewrite(
        plan.file,
        format,
        before,
        mustChange: fix is ShiftFix || fix is FrameRateFix || fix is SyncToAudioFix,
      );
    }

    onPhase?.call(SubtitleFixPhase.adding);
    // Removing the hearing-impaired lines and translating write to a new
    // name; everything else rewrites the file under its own. A translation
    // can take a while to appear.
    String? path = plan.file.path;
    final newFile = fix is RemoveHearingImpairedFix || fix is TranslateFix;
    if (newFile) {
      final known = target.subtitles.map((s) => s.path).toSet();
      String? created;
      for (var attempt = 0; attempt < (fix is TranslateFix ? 60 : 5) && created == null; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
        try {
          final fresh = await bazarr.reload(target);
          created = fresh?.subtitles.map((s) => s.path).nonNulls.firstWhereOrNull((p) => !known.contains(p));
        } catch (error) {
          _log.fine('Waiting on Bazarr failed: $error');
        }
      }
      if (created != null) {
        path = created;
      } else if (fix is TranslateFix) {
        throw const SubtitleFixException("Bazarr couldn't translate this subtitle. Check that a translator is set up "
            'in Bazarr (Settings > Subtitles > Translating).');
      }
    }
    await _refreshServer(plan.file.itemId);
    final stream = await _awaitStream(plan.file, (s) => _sameFile(s.path, path), attempts: 8);
    return SubtitleFixResult(path: stream?.path ?? path, stream: stream, inPlace: !newFile);
  }

  Future<void> _bazarr(Future<void> Function() call) async {
    try {
      await call();
    } on BazarrException catch (error) {
      throw SubtitleFixException(error.message ?? error.error.name);
    }
  }

  Future<SubtitleFixResult> _inApp(
    SubtitleFixPlan plan,
    SubtitleFix fix,
    void Function(SubtitleFixPhase phase)? onPhase,
  ) async {
    final file = plan.file;
    final format = file.format;
    if (format == null) throw const SubtitleFixException('Only text subtitles (SRT, VTT, ASS) can be changed.');
    onPhase?.call(SubtitleFixPhase.working);

    final text = await _download(file, format);
    final fixed = switch (fix) {
      ShiftFix(:final offset) => shiftSubtitle(text, format, offset),
      FrameRateFix(:final from, :final to) => changeSubtitleFrameRate(text, format, from, to),
      RemoveHearingImpairedFix() => removeHearingImpaired(text, format),
      _ => throw const SubtitleFixException('This needs Bazarr.'),
    };

    final before = (await _streams() ?? const <dto.MediaStream>[]).map((s) => s.path).nonNulls.toSet();
    onPhase?.call(SubtitleFixPhase.adding);
    final response = await ref.read(jellyApiProvider).api.videosItemIdSubtitlesPost(
          itemId: file.itemId,
          body: dto.UploadSubtitleDto(
            language: file.language ?? 'und',
            format: switch (format) {
              SubtitleTextFormat.srt => 'srt',
              SubtitleTextFormat.vtt => 'vtt',
              SubtitleTextFormat.ass => 'ass',
            },
            isForced: file.forced,
            isHearingImpaired: fix is RemoveHearingImpairedFix ? false : file.hearingImpaired,
            data: base64Encode(utf8.encode(fixed)),
          ),
        );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SubtitleFixException('The server does not allow this account to change subtitles.');
    }
    if (!response.isSuccessful) throw SubtitleFixException('The server refused the new file (${response.statusCode}).');

    final stream = await _awaitStream(file, (s) => s.isExternal == true && s.path != null && !before.contains(s.path),
        attempts: 12);

    // The new copy is in; the old one goes when this account may delete it.
    if (stream != null && _isAdmin && file.isExternal && file.path != null) {
      final old = (await _streams())?.firstWhereOrNull((s) => s.path == file.path);
      if (old?.index != null) {
        final deleted =
            await ref.read(jellyApiProvider).api.videosItemIdSubtitlesIndexDelete(itemId: file.itemId, index: old!.index);
        if (!deleted.isSuccessful) _log.warning('Removing the old copy failed: ${deleted.statusCode}');
      }
    }
    return SubtitleFixResult(path: stream?.path, stream: stream);
  }

  /// The subtitle's text as the server has it.
  Future<String> _download(SubtitleFileRef file, SubtitleTextFormat format) async {
    final extension = switch (format) {
      SubtitleTextFormat.srt => 'srt',
      SubtitleTextFormat.vtt => 'vtt',
      SubtitleTextFormat.ass => 'ass',
    };
    final url = buildServerUrl(
      ref,
      pathSegments: [
        'Videos',
        file.itemId,
        file.mediaSourceId ?? file.itemId,
        'Subtitles',
        '${file.index}',
        '0',
        'Stream.$extension',
      ],
      queryParameters: authQueryParameters(ref.read(userProvider)?.credentials.token),
    );
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw SubtitleFixException('Could not read the subtitle from the server (${response.statusCode}).');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// Waits until the server hands out something other than [before] for
  /// [file]: the rewrite has landed and can be played.
  Future<void> _awaitRewrite(
    SubtitleFileRef file,
    SubtitleTextFormat format,
    String before, {
    required bool mustChange,
  }) async {
    final timer = Stopwatch()..start();
    final patience = mustChange ? const Duration(seconds: 30) : const Duration(seconds: 4);
    while (timer.elapsed < patience) {
      try {
        if (await _download(file, format) != before) {
          _log.info('The rewritten subtitle was there after ${timer.elapsedMilliseconds}ms');
          return;
        }
      } catch (error) {
        _log.fine('Reading the subtitle after the fix failed: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    _log.warning('The subtitle had not changed ${timer.elapsedMilliseconds}ms after the fix');
    if (mustChange) throw const SubtitleFixException("Bazarr didn't change the subtitle file.");
  }

  Future<void> _refreshServer(String itemId) async {
    if (!_isAdmin) return;
    await ref.read(jellyApiProvider).api.itemsItemIdRefreshPost(
          itemId: itemId,
          metadataRefreshMode: dto.ItemsItemIdRefreshPostMetadataRefreshMode.$default,
          imageRefreshMode: dto.ItemsItemIdRefreshPostImageRefreshMode.$default,
        );
  }

  String? _currentItemId;
  String? _currentSourceId;

  Future<List<dto.MediaStream>?> _streams() async {
    final itemId = _currentItemId;
    if (itemId == null) return null;
    try {
      final response =
          await ref.read(jellyApiProvider).api.itemsItemIdGet(itemId: itemId, userId: ref.read(userProvider)?.id);
      final sources = response.body?.mediaSources ?? const [];
      final source = sources.firstWhereOrNull((s) => s.id == _currentSourceId) ?? sources.firstOrNull;
      return (source?.mediaStreams ?? const []).where((s) => s.type == dto.MediaStreamType.subtitle).toList();
    } catch (error) {
      _log.fine('Listing subtitles failed: $error');
      return null;
    }
  }

  Future<dto.MediaStream?> _awaitStream(
    SubtitleFileRef file,
    bool Function(dto.MediaStream stream) wanted, {
    required int attempts,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 600 : 1500));
      final found = (await _streams())?.firstWhereOrNull(wanted);
      if (found != null) return found;
    }
    return null;
  }

  static bool _sameFile(String? a, String? b) {
    if (a == null || b == null) return false;
    String name(String p) => p.substring(p.lastIndexOf(RegExp(r'[\\/]')) + 1);
    return name(a) == name(b);
  }
}
