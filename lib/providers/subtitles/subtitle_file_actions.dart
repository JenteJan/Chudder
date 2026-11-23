import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/subtitles/bazarr_client.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/user_provider.dart';

final _log = Logger('SubtitleFiles');

/// Who can take a subtitle file away, and how.
///
/// Jellyfin deletes a file only for an admin. Bazarr deletes any file it
/// lists for whoever holds its key - and a file Bazarr downloaded is better
/// removed through Bazarr anyway: deleted behind its back, it counts the
/// language as missing and downloads the same file again at its next
/// search.
class SubtitleRemoval {
  const SubtitleRemoval({
    required this.itemId,
    required this.index,
    required this.path,
    this.bazarr,
    this.bazarrFile,
    this.bazarrHistory,
    this.jellyfinCanDelete = false,
  });

  final String itemId;

  /// The stream as the server numbers it right now.
  final int index;
  final String? path;
  final BazarrTarget? bazarr;
  final BazarrSubtitleFile? bazarrFile;

  /// Bazarr's record of downloading it: what a block needs.
  final BazarrHistoryEntry? bazarrHistory;
  final bool jellyfinCanDelete;

  bool get possible => jellyfinCanDelete || bazarrFile != null;

  /// Bazarr can keep this one from coming back.
  bool get canBlock => bazarrFile != null && bazarrHistory != null;

  String get fileName {
    final value = path ?? '';
    final separator = value.lastIndexOf(RegExp(r'[\\/]'));
    return separator == -1 ? value : value.substring(separator + 1);
  }
}

// Kept alive: it is read, not watched, and its work outlives the read - an
// auto-disposed one was gone by the time Bazarr answered, and Riverpod 3
// throws on a disposed ref, which turned every removal into "only an admin".
final subtitleFileActionsProvider = Provider((ref) => SubtitleFileActions(ref));

class SubtitleFileActions {
  SubtitleFileActions(this.ref);
  final Ref ref;

  bool get _isAdmin => ref.read(userProvider)?.policy?.isAdministrator == true;

  /// Works out whether and how the file at [path] can be removed. Asks
  /// Bazarr, when one is connected, whether it knows the file.
  Future<SubtitleRemoval> plan({
    required String itemId,
    String? mediaSourceId,
    required int index,
    required String? path,
  }) async {
    // Read before any wait, so an answer never depends on the ref outliving it.
    final isAdmin = _isAdmin;
    final bazarr = ref.read(bazarrClientProvider);
    if (bazarr == null || path == null || path.isEmpty) {
      return SubtitleRemoval(itemId: itemId, index: index, path: path, jellyfinCanDelete: isAdmin);
    }
    try {
      final lookup = await loadSubtitleLookup(ref, itemId: itemId, mediaSourceId: mediaSourceId);
      var target = lookup.bazarr;
      if (target != null) target = await bazarr.reload(target) ?? target;
      final name = _baseName(path);
      final file = target?.fileNamed(name);
      BazarrHistoryEntry? history;
      if (target != null && file != null) {
        final entries = await bazarr.history(target);
        history = entries.firstWhereOrNull((e) => e.subsId.isNotEmpty && e.path != null && _baseName(e.path!) == name);
      }
      return SubtitleRemoval(
        itemId: itemId,
        index: index,
        path: path,
        bazarr: target,
        bazarrFile: file,
        bazarrHistory: history,
        jellyfinCanDelete: isAdmin,
      );
    } catch (error) {
      _log.warning('Asking Bazarr about $path failed: $error');
      return SubtitleRemoval(itemId: itemId, index: index, path: path, jellyfinCanDelete: isAdmin);
    }
  }

  /// Removes the file, and makes sure it is gone: a server that answers
  /// "done" is asked again whether it still lists the file. With [block],
  /// Bazarr also keeps it from being downloaded again (and looks for a
  /// replacement itself). Bazarr can answer that it deleted a file it could
  /// not touch; an admin then has Jellyfin delete it. Network trouble and
  /// server errors are tried again a few times before giving up. Returns
  /// whether the server has been asked to re-list the item - without that,
  /// the old stream stays listed until the server's next scan.
  Future<bool> remove(SubtitleRemoval removal, {bool block = false}) async {
    final bazarr = ref.read(bazarrClientProvider);
    final target = removal.bazarr;
    final file = removal.bazarrFile;
    final isAdmin = _isAdmin;
    final bazarrKnows = bazarr != null && target != null && file != null;
    // Jellyfin deletes directly for an admin, and its answer is easy to
    // check. Bazarr only when it is needed: to block the file from coming
    // back, or for a user Jellyfin would refuse.
    final viaBazarr = bazarrKnows && (!removal.jellyfinCanDelete || (block && removal.bazarrHistory != null));

    if (viaBazarr) {
      await _withRetries('Bazarr removing ${removal.fileName}', () async {
        if (block && removal.bazarrHistory != null) {
          await bazarr.blacklist(target, file, removal.bazarrHistory!);
        } else {
          await bazarr.deleteSubtitle(target, file);
        }
      });
      final stillListed = await _bazarrStillLists(bazarr, target, file);
      if (!stillListed) {
        if (!isAdmin) return false;
        await _withRetries('refreshing ${removal.itemId}', () => _refreshItem(removal.itemId));
        return true;
      }
      _log.warning('Bazarr answered that it removed ${removal.fileName}, but still lists it');
      if (!removal.jellyfinCanDelete) {
        throw const SubtitleRemovalException(SubtitleRemovalError.kept);
      }
      // Bazarr could not touch the file; Jellyfin deletes it for an admin.
    }

    if (!removal.jellyfinCanDelete) {
      throw const SubtitleRemovalException(SubtitleRemovalError.notAllowed);
    }
    var deleted = false;
    await _withRetries('Jellyfin removing ${removal.fileName}', () async {
      deleted = await _jellyfinDelete(removal);
    });
    if (!deleted) return false;
    // Jellyfin re-lists the item itself once the file is gone; a file it
    // still lists after that was not deleted, whatever it answered.
    if (removal.path?.isNotEmpty == true && !await _jellyfinLetGo(removal)) {
      _log.warning('Jellyfin answered that it removed ${removal.fileName}, but still lists it');
      throw const SubtitleRemovalException(SubtitleRemovalError.kept);
    }
    // Bazarr listed the file: have it look again, so it neither keeps the
    // file in its list nor fetches the language anew. Not worth failing for.
    if (bazarrKnows && !viaBazarr) {
      try {
        await bazarr.scanDisk(target);
      } catch (error) {
        _log.info('Asking Bazarr to rescan after removing ${removal.fileName} failed: $error');
      }
    }
    return true;
  }

  /// Whether Jellyfin stops listing the file within a few seconds.
  Future<bool> _jellyfinLetGo(SubtitleRemoval removal) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      if (await _currentIndex(removal) == _gone) return true;
    }
    return false;
  }

  /// One Jellyfin delete. False when the file was already gone.
  Future<bool> _jellyfinDelete(SubtitleRemoval removal) async {
    // The list this was picked from can be a refresh behind: every download
    // and removal renumbers the files next to the video, and a stale number
    // is a 400 - or someone else's file. Ask for the number now, by path,
    // and never fall back to the old number for a file that has one: a
    // second removal of the same row finds its file gone, and the old number
    // then belongs to the next file along.
    final int index;
    if (removal.path?.isNotEmpty == true) {
      final lookup = await _currentIndex(removal);
      if (lookup == null) {
        throw const SubtitleRemovalException(SubtitleRemovalError.unreachable);
      }
      if (lookup == _gone) {
        _log.info('${removal.fileName} is no longer listed; nothing to remove');
        return false;
      }
      index = lookup;
    } else {
      index = removal.index;
    }
    final response = await ref.read(jellyApiProvider).api.videosItemIdSubtitlesIndexDelete(
          itemId: removal.itemId,
          index: index,
        );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SubtitleRemovalException(SubtitleRemovalError.notAllowed);
    }
    if (!response.isSuccessful) {
      throw SubtitleRemovalException(SubtitleRemovalError.server, '${response.statusCode}');
    }
    return true;
  }

  Future<void> _refreshItem(String itemId) async {
    final response = await ref.read(jellyApiProvider).api.itemsItemIdRefreshPost(
          itemId: itemId,
          metadataRefreshMode: dto.ItemsItemIdRefreshPostMetadataRefreshMode.$default,
          imageRefreshMode: dto.ItemsItemIdRefreshPostImageRefreshMode.$default,
        );
    if (!response.isSuccessful) {
      throw SubtitleRemovalException(SubtitleRemovalError.server, '${response.statusCode}');
    }
  }

  /// Whether Bazarr still lists [file] once it has had a moment.
  Future<bool> _bazarrStillLists(BazarrClient bazarr, BazarrTarget target, BazarrSubtitleFile file) async {
    final name = _baseName(file.path ?? '');
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
      try {
        final fresh = await bazarr.reload(target);
        if (fresh != null && fresh.fileNamed(name) == null) return false;
      } catch (error) {
        _log.info('Asking Bazarr again about $name failed: $error');
      }
    }
    return true;
  }

  /// [action], tried again after a pause when the network or the server
  /// failed it - not when it was refused or the file is not there.
  Future<void> _withRetries(String what, Future<void> Function() action) async {
    const pauses = [Duration(seconds: 1), Duration(seconds: 3)];
    for (var attempt = 0;; attempt++) {
      try {
        await action();
        return;
      } catch (error) {
        if (!_isTransient(error) || attempt >= pauses.length) {
          _log.warning('$what failed: $error');
          if (error is BazarrException && error.error == BazarrError.unauthorized) {
            throw const SubtitleRemovalException(SubtitleRemovalError.notAllowed);
          }
          if (error is SubtitleRemovalException) rethrow;
          if (_isTransient(error)) {
            throw const SubtitleRemovalException(SubtitleRemovalError.unreachable);
          }
          throw SubtitleRemovalException(SubtitleRemovalError.server, '$error');
        }
        _log.info('$what failed, trying again: $error');
        await Future<void>.delayed(pauses[attempt]);
      }
    }
  }

  static bool _isTransient(Object error) =>
      error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException ||
      (error is BazarrException && (error.error == BazarrError.server || error.error == BazarrError.unreachable)) ||
      (error is SubtitleRemovalException &&
          (error.error == SubtitleRemovalError.unreachable ||
              (error.error == SubtitleRemovalError.server && (int.tryParse(error.detail ?? '') ?? 0) >= 500)));
}

final subtitleRemovalQueueProvider = Provider((ref) => SubtitleRemovalQueue(ref));

/// Removals that wait out an undo window before anything is deleted.
///
/// Nothing is touched on the server until the window has passed, so undo
/// is only ever "don't" - never "put it back", which the server cannot do
/// faithfully (Jellyfin renames an upload, Bazarr keeps a block). Kept
/// alive for the whole app, so closing the player or the dialog a removal
/// was asked from does not cancel it; quitting the app inside the window
/// does, and leaves the file where it was.
class SubtitleRemovalQueue {
  SubtitleRemovalQueue(this.ref);
  final Ref ref;

  /// How long the undo stays on offer.
  static const undoWindow = Duration(seconds: 6);

  /// A little past [undoWindow], so an undo pressed as the message leaves
  /// still lands before the delete starts.
  static const _grace = Duration(milliseconds: 600);

  final Map<String, PendingSubtitleRemoval> _pending = {};

  /// Removals not yet finished, for a caller that re-reads the item.
  Future<void> get settled => Future.wait([
        for (final pending in _pending.values) pending.result.then((_) {}, onError: (_) {}),
      ]);

  PendingSubtitleRemoval schedule(SubtitleRemoval removal, {required bool block}) {
    final key = removal.path?.isNotEmpty == true ? removal.path! : '${removal.itemId}#${removal.index}';
    final existing = _pending[key];
    if (existing != null) return existing;
    final pending = PendingSubtitleRemoval._();
    _pending[key] = pending;
    pending._timer = Timer(undoWindow + _grace, () async {
      pending._started = true;
      try {
        pending._completer.complete(await ref.read(subtitleFileActionsProvider).remove(removal, block: block));
      } catch (error, stackTrace) {
        pending._completer.completeError(error, stackTrace);
      } finally {
        _pending.remove(key);
      }
    });
    pending._onUndo = () => _pending.remove(key);
    return pending;
  }
}

class PendingSubtitleRemoval {
  PendingSubtitleRemoval._();

  final Completer<bool?> _completer = Completer();
  Timer? _timer;
  bool _started = false;
  VoidCallback? _onUndo;

  /// Whether the server re-lists the item, once the file is gone; null if
  /// it was undone. Fails the way [SubtitleFileActions.remove] does.
  Future<bool?> get result => _completer.future;

  /// Calls the removal off. False when it had already started.
  bool undo() {
    if (_started || _completer.isCompleted) return false;
    _timer?.cancel();
    _onUndo?.call();
    _completer.complete(null);
    return true;
  }
}

/// What [SubtitleFileActions._currentIndex] answers for a file the server no
/// longer lists.
const _gone = -2;

extension on SubtitleFileActions {
  /// The file's number as the server lists it now, [_gone] when it is not
  /// listed any more, null when the server could not be asked.
  Future<int?> _currentIndex(SubtitleRemoval removal) async {
    final path = removal.path;
    if (path == null || path.isEmpty) return null;
    try {
      final response = await ref.read(jellyApiProvider).api.itemsItemIdGet(
            itemId: removal.itemId,
            userId: ref.read(userProvider)?.id,
          );
      final sources = response.body?.mediaSources;
      if (!response.isSuccessful || sources == null) return null;
      for (final source in sources) {
        final stream = source.mediaStreams?.firstWhereOrNull((s) => s.type == dto.MediaStreamType.subtitle && s.path == path);
        if (stream?.index != null) return stream!.index;
      }
      return _gone;
    } catch (error) {
      _log.fine('Looking up ${removal.fileName} failed: $error');
    }
    return null;
  }
}

enum SubtitleRemovalError {
  notAllowed,
  server,

  /// The server answered that it removed the file, and still has it.
  kept,

  /// The server could not be reached, even after trying again.
  unreachable,
}

class SubtitleRemovalException implements Exception {
  const SubtitleRemovalException(this.error, [this.detail]);
  final SubtitleRemovalError error;
  final String? detail;
  @override
  String toString() => detail ?? error.name;
}

String _baseName(String path) {
  final separator = path.lastIndexOf(RegExp(r'[\\/]'));
  return separator == -1 ? path : path.substring(separator + 1);
}
