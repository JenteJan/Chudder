import 'dart:math' as math;

import 'package:chudder/models/subtitles/release_info.dart';

/// The video a subtitle has to fit: what its file name says, filled in with
/// what its streams say, and what the library knows about the item.
class SubtitleTarget {
  final bool isEpisode;
  final int? year;
  final int? season;
  final int? episode;

  /// Read from the file name (and the folder, for a renamed file), then
  /// completed from the streams: a renamed "Sintel (2010).mkv" still has a
  /// 1080p H.264 picture.
  final ReleaseInfo release;

  /// Which of [release]'s parts the file name itself gave. Resolution and
  /// codecs can come from the streams; a release group or a source never
  /// can, and saying "no release group to compare against" is worth more
  /// than saying nothing.
  final bool nameDescribesRelease;
  final double? frameRate;

  const SubtitleTarget({
    required this.isEpisode,
    this.year,
    this.season,
    this.episode,
    this.release = ReleaseInfo.empty,
    this.nameDescribesRelease = false,
    this.frameRate,
  });
}

/// One subtitle offered for the item, from whichever source found it.
class SubtitleCandidate {
  /// Unique across sources.
  final String key;
  final SubtitleSourceKind source;

  /// The site it comes from ("OpenSubtitles", "Podnapisi", ...).
  final String provider;
  final String language;
  final String? releaseName;

  /// Other releases the uploader says it fits.
  final List<String> otherReleases;
  final String? format;
  final String? uploader;
  final String? comment;
  final double? frameRate;
  final int? downloads;
  final double? rating;
  final DateTime? uploaded;
  final bool hashMatch;
  final bool hearingImpaired;
  final bool forced;
  final bool machineTranslated;
  final bool aiTranslated;

  /// A score the source worked out itself (Bazarr, which knows the release
  /// name from before Sonarr or Radarr renamed the file), as a percentage.
  final double? sourceScore;
  final Set<MatchField> sourceMatches;
  final Set<MatchField> sourceMismatches;

  /// What the source needs back to download it.
  final Object payload;

  const SubtitleCandidate({
    required this.key,
    required this.source,
    required this.provider,
    required this.language,
    required this.payload,
    this.releaseName,
    this.otherReleases = const [],
    this.format,
    this.uploader,
    this.comment,
    this.frameRate,
    this.downloads,
    this.rating,
    this.uploaded,
    this.hashMatch = false,
    this.hearingImpaired = false,
    this.forced = false,
    this.machineTranslated = false,
    this.aiTranslated = false,
    this.sourceScore,
    this.sourceMatches = const {},
    this.sourceMismatches = const {},
  });
}

enum SubtitleSourceKind { jellyfin, bazarr }

enum MatchField {
  hash,
  episode,
  year,
  edition,
  releaseGroup,
  source,
  streamingService,
  resolution,
  videoCodec,
  audioCodec,
  frameRate,
  hearingImpaired,
}

/// How far a subtitle can be trusted to fit, in the terms the list shows.
enum MatchVerdict {
  /// Synced against this very file (a hash match).
  exact,

  /// Made for this release: same group, or same source and service.
  release,

  /// Same kind of release; timing usually holds.
  likely,

  /// Nothing tells either way, or only small things agree.
  unknown,

  /// Something that decides the timing is different: another episode, cut
  /// or frame rate.
  unlikely,
}

class SubtitleMatch {
  final SubtitleCandidate candidate;

  /// How much of what the file states about its release this subtitle
  /// agrees with (see [SubtitleFitWeights]); null when the file states
  /// nothing to compare against.
  final double? percent;
  final MatchVerdict verdict;
  final Set<MatchField> matched;

  /// Parts both sides state, and state differently.
  final Map<MatchField, (String subtitle, String video)> mismatched;

  /// The release name the score was taken from (the best of the ones given).
  final String? scoredRelease;
  final ReleaseInfo release;

  const SubtitleMatch({
    required this.candidate,
    required this.percent,
    required this.verdict,
    required this.matched,
    required this.mismatched,
    required this.release,
    this.scoredRelease,
  });

  /// Deal-breakers: things that mean the timing will not fit at all.
  bool get isUnlikely => verdict == MatchVerdict.unlikely;

  bool get isTranslatedByMachine => candidate.machineTranslated || candidate.aiTranslated;
}

/// How much each part of a release says about timing - Bazarr's weights
/// (subliminal_patch `DEFAULT_SCORES`, 2026-03) for the parts a release
/// name can state, plus the frame rate, which Bazarr does not compare and
/// which decides more than any of them.
///
/// Bazarr's own percentage also counts the title, year and episode, which
/// every result here matches by being found for this item at all - so a
/// bare "Futurama" read 86%. The fit counts only what could tell two
/// subtitles apart.
class SubtitleFitWeights {
  static const source = 25;
  static const releaseGroup = 20;
  static const edition = 30;
  static const frameRate = 25;
  static const streamingService = 2;
  static const resolution = 2;
  static const videoCodec = 2;
  static const audioCodec = 1;

  /// A deal-breaker's fit is never shown above this.
  static const unlikelyCeiling = 25.0;
}

/// Compares [candidate] with [target] part by part the way Bazarr does, then
/// looks for the things Bazarr leaves to its minimum score: a subtitle for a
/// different episode, cut or frame rate is not a slightly worse match but
/// no match.
///
/// The source searched for this item by its ids, so the title (and for an
/// episode the season and episode) hold unless the release name says
/// otherwise. [preferHearingImpaired] is the viewer's own choice; null
/// means either will do.
SubtitleMatch scoreSubtitle(
  SubtitleCandidate candidate,
  SubtitleTarget target, {
  bool? preferHearingImpaired,
}) {
  final names = [
    if (candidate.releaseName?.trim().isNotEmpty == true) candidate.releaseName!,
    ...candidate.otherReleases.where((e) => e.trim().isNotEmpty),
  ];
  final options = names.isEmpty ? <String?>[null] : names;

  SubtitleMatch? best;
  for (final name in options) {
    final match = _scoreAgainst(candidate, target, name, preferHearingImpaired);
    if (best == null || _better(match, best)) best = match;
  }
  return best!;
}

bool _better(SubtitleMatch a, SubtitleMatch b) {
  if (a.isUnlikely != b.isUnlikely) return !a.isUnlikely;
  return (a.percent ?? -1) > (b.percent ?? -1);
}

SubtitleMatch _scoreAgainst(
  SubtitleCandidate candidate,
  SubtitleTarget target,
  String? releaseName,
  bool? preferHearingImpaired,
) {
  final release = ReleaseInfo.parse(releaseName);
  final video = target.release;
  final matched = <MatchField>{};
  final mismatched = <MatchField, (String, String)>{};
  var dealBreaker = false;

  void compare(MatchField field, String? subtitle, String? ofVideo) {
    if (subtitle == null || ofVideo == null) return;
    if (subtitle.toLowerCase() == ofVideo.toLowerCase()) {
      matched.add(field);
    } else {
      mismatched[field] = (subtitle, ofVideo);
    }
  }

  if (candidate.hashMatch) matched.add(MatchField.hash);

  // Episode: the search asked for this one, so it holds unless the name
  // says another. A season pack of the right season still fits.
  if (target.isEpisode) {
    final wrongSeason = release.season != null && target.season != null && release.season != target.season;
    final wrongEpisode =
        release.episodes.isNotEmpty && target.episode != null && !release.episodes.contains(target.episode);
    if (wrongSeason || wrongEpisode) {
      dealBreaker = true;
      mismatched[MatchField.episode] = (
        _episodeLabel(release.season, release.episodes),
        _episodeLabel(target.season, target.episode == null ? const [] : [target.episode!]),
      );
    } else {
      matched.add(MatchField.episode);
    }
  }

  // Year: a remake shares a title with the original, and one year's slack
  // covers a festival year against a release year.
  if (release.year != null && target.year != null && (release.year! - target.year!).abs() > 1) {
    if (!target.isEpisode) dealBreaker = true;
    mismatched[MatchField.year] = ('${release.year}', '${target.year}');
  } else {
    matched.add(MatchField.year);
  }

  compare(MatchField.source, release.source?.family, video.source?.family);
  // As in Bazarr, a group only counts on the same kind of source: a group
  // that does both web and Blu-ray releases times them differently.
  compare(MatchField.releaseGroup, release.releaseGroup, video.releaseGroup);
  if (!matched.contains(MatchField.source)) matched.remove(MatchField.releaseGroup);
  compare(MatchField.streamingService, release.streamingService, video.streamingService);
  compare(MatchField.resolution, release.resolution, video.resolution);
  compare(MatchField.videoCodec, release.videoCodec, video.videoCodec);
  compare(MatchField.audioCodec, release.audioCodec, video.audioCodec);

  // Another cut is another running time: an Extended subtitle drifts off a
  // theatrical file by whole scenes. Only a disagreement both sides state
  // rules it out - most files do not say which cut they are.
  if (release.edition != null && video.edition == null) {
    // The file does not say which cut it is, which mostly means the
    // theatrical one - worth showing, not worth ruling out.
    mismatched[MatchField.edition] = (release.edition!, '');
  } else if (release.edition != null && video.edition != null) {
    if (release.edition!.toLowerCase() == video.edition!.toLowerCase()) {
      matched.add(MatchField.edition);
    } else {
      mismatched[MatchField.edition] = (release.edition!, video.edition!);
      if (_changesRuntime(release.edition!) || _changesRuntime(video.edition!)) dealBreaker = true;
    }
  }

  // Frame rate: a subtitle timed at 25 fps runs 4% fast on a 23.976 film and
  // is minutes out by the end. 23.976 against 24 is the same film speed as
  // far as a subtitle file goes, so only a real gap counts.
  final subFps = candidate.frameRate;
  final videoFps = target.frameRate;
  if (subFps != null && subFps > 1 && videoFps != null && videoFps > 1) {
    if ((subFps - videoFps).abs() < 0.5) {
      matched.add(MatchField.frameRate);
    } else {
      mismatched[MatchField.frameRate] = (_fps(subFps), _fps(videoFps));
      dealBreaker = true;
    }
  }

  final hearingImpaired = candidate.hearingImpaired || release.hearingImpaired;
  if (preferHearingImpaired == null || preferHearingImpaired == hearingImpaired) {
    matched.add(MatchField.hearingImpaired);
  }

  // Bazarr's own comparison, when it made one, is taken over: it compared
  // against the release the file was before it was renamed.
  if (candidate.sourceScore != null) {
    matched.addAll(candidate.sourceMatches);
    for (final field in candidate.sourceMismatches) {
      mismatched.putIfAbsent(field, () => ('', ''));
      matched.remove(field);
    }
  }

  final hash = matched.contains(MatchField.hash);
  final percent = _fit(
    matched: matched,
    video: video,
    release: release,
    isEpisode: target.isEpisode,
    frameRateCompared: matched.contains(MatchField.frameRate) || mismatched.containsKey(MatchField.frameRate),
    dealBreaker: dealBreaker && !hash,
  );

  final MatchVerdict verdict;
  if (dealBreaker && !hash) {
    verdict = MatchVerdict.unlikely;
  } else if (hash) {
    verdict = MatchVerdict.exact;
  } else if (matched.contains(MatchField.releaseGroup) ||
      (matched.contains(MatchField.source) &&
          matched.contains(MatchField.streamingService) &&
          !mismatched.containsKey(MatchField.releaseGroup))) {
    verdict = MatchVerdict.release;
  } else if (matched.contains(MatchField.source)) {
    verdict = MatchVerdict.likely;
  } else {
    verdict = MatchVerdict.unknown;
  }

  return SubtitleMatch(
    candidate: candidate,
    percent: percent,
    verdict: verdict,
    matched: matched,
    mismatched: mismatched,
    release: release,
    scoredRelease: releaseName,
  );
}

/// How much of what the file says about its release this subtitle agrees
/// with, from 0 to 100; null when the file says nothing to compare against.
///
/// Only what the file states counts, so every result for one file is held
/// to the same measure - and what the subtitle leaves out counts against
/// it, since a release name that says nothing proves nothing. A release
/// group only counts on the same source, as in Bazarr.
double? _fit({
  required Set<MatchField> matched,
  required ReleaseInfo video,
  required ReleaseInfo release,
  required bool isEpisode,
  required bool frameRateCompared,
  required bool dealBreaker,
}) {
  if (matched.contains(MatchField.hash)) return 100;
  var total = 0;
  var agreed = 0;
  void count(MatchField field, int weight, {required bool stated}) {
    if (!stated) return;
    total += weight;
    if (matched.contains(field)) agreed += weight;
  }

  count(MatchField.source, SubtitleFitWeights.source, stated: video.source != null);
  count(MatchField.releaseGroup, SubtitleFitWeights.releaseGroup, stated: video.releaseGroup != null);
  count(MatchField.streamingService, SubtitleFitWeights.streamingService, stated: video.streamingService != null);
  count(MatchField.resolution, SubtitleFitWeights.resolution, stated: video.resolution != null);
  count(MatchField.videoCodec, SubtitleFitWeights.videoCodec, stated: video.videoCodec != null);
  count(MatchField.audioCodec, SubtitleFitWeights.audioCodec, stated: video.audioCodec != null);
  // A cut only counts once someone names one.
  count(MatchField.edition, SubtitleFitWeights.edition,
      stated: !isEpisode && (video.edition != null || release.edition != null));
  count(MatchField.frameRate, SubtitleFitWeights.frameRate, stated: frameRateCompared);

  if (total == 0) return dealBreaker ? 0 : null;
  final fit = agreed * 100 / total;
  return dealBreaker ? math.min(fit, SubtitleFitWeights.unlikelyCeiling) : fit;
}

/// Best first: anything that will not fit goes to the bottom, then how well
/// it fits, then what people have made of it.
int compareMatches(SubtitleMatch a, SubtitleMatch b) {
  if (a.isUnlikely != b.isUnlikely) return a.isUnlikely ? 1 : -1;
  final fitA = a.percent ?? -1;
  final fitB = b.percent ?? -1;
  if ((fitA - fitB).abs() >= 0.5) return fitB.compareTo(fitA);
  final verdict = a.verdict.index.compareTo(b.verdict.index);
  if (verdict != 0) return verdict;
  if (a.isTranslatedByMachine != b.isTranslatedByMachine) return a.isTranslatedByMachine ? 1 : -1;
  if (a.candidate.forced != b.candidate.forced) return a.candidate.forced ? 1 : -1;
  final downloads = (b.candidate.downloads ?? 0).compareTo(a.candidate.downloads ?? 0);
  if (downloads != 0) return downloads;
  return (b.candidate.rating ?? 0).compareTo(a.candidate.rating ?? 0);
}

bool _changesRuntime(String edition) =>
    const {'Extended', "Director's Cut", 'Unrated', 'Uncut', 'Final Cut'}.contains(edition);

String _fps(double value) {
  final rounded = (value * 1000).round() / 1000;
  return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : '$rounded';
}

String _episodeLabel(int? season, List<int> episodes) {
  final s = season == null ? '' : 'S${season.toString().padLeft(2, '0')}';
  final e = episodes.map((e) => 'E${e.toString().padLeft(2, '0')}').join();
  return '$s$e'.isEmpty ? '?' : '$s$e';
}
