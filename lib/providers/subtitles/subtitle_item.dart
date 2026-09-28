import 'package:collection/collection.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/models/subtitles/release_info.dart';
import 'package:chudder/models/subtitles/subtitle_match.dart';

/// Everything the subtitle finder knows about the film or episode it is
/// finding subtitles for: what to tell Bazarr to find it, and the file a
/// subtitle has to fit.
class SubtitleItem {
  final String itemId;
  final String title;
  final bool isEpisode;
  final int? year;
  final int? season;
  final int? episode;
  final String? imdbId;
  final String? seriesTitle;
  final String? seriesImdbId;
  final String? seriesTvdbId;
  final int? seriesYear;

  /// The version whose file the subtitle is for.
  final String? mediaSourceId;
  final String? filePath;
  final dto.MediaSourceInfo? mediaSource;

  /// The file's release name from before Sonarr or Radarr renamed it, when
  /// Bazarr knows it. It says more than the file name ever does.
  final String? sceneName;

  const SubtitleItem({
    required this.itemId,
    required this.title,
    required this.isEpisode,
    this.year,
    this.season,
    this.episode,
    this.imdbId,
    this.seriesTitle,
    this.seriesImdbId,
    this.seriesTvdbId,
    this.seriesYear,
    this.mediaSourceId,
    this.filePath,
    this.mediaSource,
    this.sceneName,
  });

  factory SubtitleItem.fromDto(
    dto.BaseItemDto item, {
    dto.BaseItemDto? series,
    String? mediaSourceId,
  }) {
    final sources = item.mediaSources ?? const [];
    final source = sources.firstWhereOrNull((s) => s.id == mediaSourceId) ?? sources.firstOrNull;
    final isEpisode = item.type == dto.BaseItemKind.episode;
    String? id(Map<String, dynamic>? ids, String key) {
      final value = ids?.entries.firstWhereOrNull((e) => e.key.toLowerCase() == key)?.value?.toString();
      return value == null || value.isEmpty ? null : value;
    }

    return SubtitleItem(
      itemId: item.id ?? '',
      title: item.name ?? '',
      isEpisode: isEpisode,
      year: item.productionYear ?? item.premiereDate?.year,
      season: isEpisode ? item.parentIndexNumber : null,
      episode: isEpisode ? item.indexNumber : null,
      imdbId: id(item.providerIds, 'imdb'),
      seriesTitle: series?.name ?? item.seriesName,
      seriesImdbId: id(series?.providerIds, 'imdb'),
      seriesTvdbId: id(series?.providerIds, 'tvdb'),
      seriesYear: series?.productionYear,
      mediaSourceId: source?.id,
      filePath: source?.path ?? item.path,
      mediaSource: source,
    );
  }

  SubtitleItem withSceneName(String? value) => SubtitleItem(
        itemId: itemId,
        title: title,
        isEpisode: isEpisode,
        year: year,
        season: season,
        episode: episode,
        imdbId: imdbId,
        seriesTitle: seriesTitle,
        seriesImdbId: seriesImdbId,
        seriesTvdbId: seriesTvdbId,
        seriesYear: seriesYear,
        mediaSourceId: mediaSourceId,
        filePath: filePath,
        mediaSource: mediaSource,
        sceneName: value == null || value.trim().isEmpty ? null : value.trim(),
      );

  List<dto.MediaStream> get streams => mediaSource?.mediaStreams ?? const [];

  List<dto.MediaStream> get subtitleStreams =>
      streams.where((s) => s.type == dto.MediaStreamType.subtitle).toList();

  /// Paths of the subtitle files next to the video.
  Set<String> get externalSubtitlePaths => {
        for (final stream in subtitleStreams)
          if (stream.isExternal == true && stream.path != null) stream.path!,
      };

  /// Languages spoken in the file, three letters, the default track first.
  List<String> get audioLanguages {
    final audio = streams.where((s) => s.type == dto.MediaStreamType.audio).toList()
      ..sort((a, b) => (b.isDefault == true ? 1 : 0).compareTo(a.isDefault == true ? 1 : 0));
    return audio.map((s) => s.language?.toLowerCase()).nonNulls.where((l) => l.isNotEmpty && l != 'und').toList();
  }

  String? get fileName {
    final path = filePath;
    if (path == null || path.isEmpty) return null;
    final separator = path.lastIndexOf(RegExp(r'[\\/]'));
    return separator == -1 ? path : path.substring(separator + 1);
  }

  /// The release as the scorer sees it: Bazarr's scene name first, then the
  /// file name, then its folder (a download that kept its release name as a
  /// folder), then the streams for whatever no name says.
  ({ReleaseInfo release, String? from, bool named}) get release {
    final path = filePath ?? '';
    final parts = path.split(RegExp(r'[\\/]'));
    final folder = parts.length > 1 ? parts[parts.length - 2] : null;

    var info = ReleaseInfo.empty;
    String? from;
    for (final name in [sceneName, fileName, folder]) {
      if (name == null || name.isEmpty) continue;
      final parsed = ReleaseInfo.parse(name);
      if (parsed.describesRelease && from == null) from = name;
      info = info.mergedWith(parsed);
    }
    final named = info.describesRelease;
    return (release: info.mergedWith(_fromStreams()), from: from, named: named);
  }

  ReleaseInfo _fromStreams() {
    final video = streams.firstWhereOrNull((s) => s.type == dto.MediaStreamType.video);
    final audio = streams.firstWhereOrNull((s) => s.type == dto.MediaStreamType.audio && s.isDefault == true) ??
        streams.firstWhereOrNull((s) => s.type == dto.MediaStreamType.audio);
    return ReleaseInfo(
      resolution: _resolution(video?.width, video?.height),
      videoCodec: switch (video?.codec?.toLowerCase()) {
        'h264' || 'avc' => 'H.264',
        'hevc' || 'h265' => 'H.265',
        'av1' => 'AV1',
        'mpeg4' || 'xvid' || 'divx' => 'Xvid',
        'vc1' => 'VC-1',
        'mpeg2video' => 'MPEG-2',
        _ => null,
      },
      audioCodec: switch (audio?.codec?.toLowerCase()) {
        'ac3' => 'Dolby Digital',
        'eac3' => 'Dolby Digital Plus',
        'truehd' => 'Dolby TrueHD',
        'dts' => 'DTS',
        'aac' => 'AAC',
        'flac' => 'FLAC',
        'mp3' => 'MP3',
        'opus' => 'Opus',
        _ => null,
      },
    );
  }

  static String? _resolution(int? width, int? height) {
    final w = width ?? 0;
    final h = height ?? 0;
    if (w == 0 && h == 0) return null;
    // Width first: a 2.39:1 film at 1920x800 is a 1080p release.
    if (w >= 3200 || h >= 1800) return '2160p';
    if (w >= 1800 || h >= 1000) return '1080p';
    if (w >= 1200 || h >= 700) return '720p';
    if (h >= 560) return '576p';
    return '480p';
  }

  double? get frameRate {
    final video = streams.firstWhereOrNull((s) => s.type == dto.MediaStreamType.video);
    final rate = video?.realFrameRate ?? video?.averageFrameRate;
    return rate == null || rate <= 1 ? null : rate.toDouble();
  }

  SubtitleTarget get target {
    final r = release;
    return SubtitleTarget(
      isEpisode: isEpisode,
      year: isEpisode ? (seriesYear ?? year) : year,
      season: season,
      episode: episode,
      release: r.release,
      nameDescribesRelease: r.named,
      frameRate: frameRate,
    );
  }
}
