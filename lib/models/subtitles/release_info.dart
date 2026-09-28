/// What a release name says about the video it was made from.
///
/// A subtitle is timed against one particular encode: the same film on a
/// Blu-ray and on a streaming service can differ by a studio logo, a recap or
/// a different frame rate, and the lines drift apart from there. Subtitle
/// sites name each file after the release it was synced to
/// (`Show.S01E02.1080p.WEB-DL.DDP5.1.H.264-NTb`), and scene naming is regular
/// enough to read the parts back out - the same parts Bazarr compares.
class ReleaseInfo {
  final int? year;

  /// Season and episodes named in the release. A season pack carries a
  /// season and no episodes.
  final int? season;
  final List<int> episodes;
  final ReleaseSource? source;
  final String? resolution;
  final String? videoCodec;
  final String? audioCodec;
  final String? releaseGroup;
  final String? streamingService;
  final String? edition;
  final bool hearingImpaired;

  const ReleaseInfo({
    this.year,
    this.season,
    this.episodes = const [],
    this.source,
    this.resolution,
    this.videoCodec,
    this.audioCodec,
    this.releaseGroup,
    this.streamingService,
    this.edition,
    this.hearingImpaired = false,
  });

  static const empty = ReleaseInfo();

  /// Anything a subtitle could be compared on beyond the episode and year.
  bool get describesRelease =>
      source != null ||
      resolution != null ||
      videoCodec != null ||
      audioCodec != null ||
      releaseGroup != null ||
      streamingService != null;

  /// Reads a release or file name. Unknown words are ignored, so a plain
  /// "Sintel (2010)" gives a year and nothing else.
  factory ReleaseInfo.parse(String? input) {
    if (input == null) return empty;
    var name = input.trim();
    if (name.isEmpty) return empty;

    // A path: only the file (or folder) name says anything about the release.
    final slash = name.lastIndexOf(RegExp(r'[\\/]'));
    if (slash != -1) name = name.substring(slash + 1);
    name = name.replaceFirst(RegExp(r'\.(srt|ass|ssa|sub|idx|vtt|smi|mkv|mp4|avi|m4v|ts|m2ts|webm|mov|wmv)$',
        caseSensitive: false), '');

    final group = _releaseGroup(name);
    final tokens = _tokens(name);
    final lower = tokens.map((e) => e.toLowerCase()).toList();
    final joined = ' ${lower.join(' ')} ';

    final (season, episodes) = _seasonEpisode(name);

    return ReleaseInfo(
      year: _year(tokens),
      season: season,
      episodes: episodes,
      source: _source(lower, joined),
      resolution: _resolution(lower),
      videoCodec: _videoCodec(lower, joined),
      // "DD+" loses its plus to the split, so it is looked for whole.
      audioCodec: RegExp(r'(?<![a-z])(dd\+|ddp)', caseSensitive: false).hasMatch(name) &&
              !lower.contains('truehd')
          ? 'Dolby Digital Plus'
          : _audioCodec(lower, joined),
      releaseGroup: group,
      streamingService: _service(tokens),
      edition: _edition(joined),
      hearingImpaired: lower.any((e) => e == 'hi' || e == 'sdh' || e == 'cc'),
    );
  }

  static List<String> _tokens(String name) =>
      name.split(RegExp(r'[\s._\-\[\]\(\)\{\},+]+')).where((e) => e.isNotEmpty).toList();

  static int? _year(List<String> tokens) {
    // The last year-shaped word: "2001.A.Space.Odyssey.1968" is from 1968.
    int? found;
    for (final token in tokens) {
      final match = RegExp(r'^(19\d\d|20\d\d)$').firstMatch(token);
      if (match != null) found = int.parse(match.group(1)!);
    }
    return found;
  }

  static (int?, List<int>) _seasonEpisode(String name) {
    final sxe = RegExp(r'(?:^|[^a-z0-9])s(\d{1,2})((?:[ ._\-]?e\d{1,3})+)', caseSensitive: false).firstMatch(name);
    if (sxe != null) {
      final episodes = RegExp(r'e(\d{1,3})', caseSensitive: false)
          .allMatches(sxe.group(2)!)
          .map((e) => int.parse(e.group(1)!))
          .toList();
      // S01E01-E03 and S01E01-03 name a range.
      final range = RegExp(r'e(\d{1,3})-e?(\d{1,3})', caseSensitive: false).firstMatch(name.substring(sxe.start));
      if (range != null) {
        final from = int.parse(range.group(1)!);
        final to = int.parse(range.group(2)!);
        if (to > from && to - from < 30) {
          return (int.parse(sxe.group(1)!), [for (var i = from; i <= to; i++) i]);
        }
      }
      return (int.parse(sxe.group(1)!), episodes);
    }
    final cross = RegExp(r'(?:^|[^0-9])(\d{1,2})x(\d{2,3})(?:[^0-9p]|$)', caseSensitive: false).firstMatch(name);
    if (cross != null) return (int.parse(cross.group(1)!), [int.parse(cross.group(2)!)]);
    final pack = RegExp(r'(?:^|[^a-z0-9])(?:s|season[ ._]?)(\d{1,2})(?:[^a-z0-9e]|$)', caseSensitive: false)
        .firstMatch(name);
    if (pack != null) return (int.parse(pack.group(1)!), const <int>[]);
    return (null, const <int>[]);
  }

  static ReleaseSource? _source(List<String> lower, String joined) {
    bool has(String word) => lower.contains(word);
    if (has('bluray') ||
        has('bdrip') ||
        has('brrip') ||
        has('bdremux') ||
        has('bdmv') ||
        has('bd') ||
        has('uhdbd') ||
        joined.contains(' blu ray ') ||
        (has('remux') && !joined.contains(' web '))) {
      return ReleaseSource.bluRay;
    }
    if (has('webdl') ||
        has('webrip') ||
        has('web') ||
        has('webhd') ||
        has('amzn') ||
        has('nf') ||
        has('dsnp') ||
        joined.contains(' web dl ')) {
      return ReleaseSource.web;
    }
    if (has('hdtv') || has('pdtv') || has('hdtvrip') || has('dsr') || has('tvrip') || has('satrip')) {
      return ReleaseSource.hdtv;
    }
    if (has('dvdrip') || has('dvd') || has('dvd5') || has('dvd9') || has('dvdr') || has('ntsc') || has('pal')) {
      return ReleaseSource.dvd;
    }
    if (has('vhsrip') || has('vhs')) return ReleaseSource.vhs;
    if (has('cam') || has('hdcam') || has('telesync') || has('hdts') || has('telecine')) return ReleaseSource.cam;
    return null;
  }

  static String? _resolution(List<String> lower) {
    for (final token in lower) {
      switch (token) {
        case '2160p' || '4k' || 'uhd':
          return '2160p';
        case '1080p' || '1080i':
          return '1080p';
        case '720p':
          return '720p';
        case '576p' || '576i':
          return '576p';
        case '480p' || '480i':
          return '480p';
      }
    }
    return null;
  }

  static String? _videoCodec(List<String> lower, String joined) {
    for (final token in lower) {
      switch (token) {
        case 'x264' || 'h264' || 'avc':
          return 'H.264';
        case 'x265' || 'h265' || 'hevc':
          return 'H.265';
        case 'av1':
          return 'AV1';
        case 'xvid' || 'divx':
          return 'Xvid';
        case 'vc1':
          return 'VC-1';
        case 'mpeg2':
          return 'MPEG-2';
      }
    }
    // "H.264" and "H 265" arrive split in two.
    if (joined.contains(' h 264 ')) return 'H.264';
    if (joined.contains(' h 265 ')) return 'H.265';
    if (joined.contains(' vc 1 ')) return 'VC-1';
    return null;
  }

  static String? _audioCodec(List<String> lower, String joined) {
    for (final token in lower) {
      if (token == 'truehd' || token == 'atmos' && joined.contains(' truehd ')) return 'Dolby TrueHD';
    }
    for (final token in lower) {
      if (RegExp(r'^(ddp|eac3|dd\+|ddplus)(\d(\d)?)?$').hasMatch(token)) return 'Dolby Digital Plus';
    }
    for (final token in lower) {
      if (RegExp(r'^dts(hd|x|ma|es)?$').hasMatch(token)) return 'DTS';
      if (RegExp(r'^(dd|ac3)(\d(\d)?)?$').hasMatch(token)) return 'Dolby Digital';
      if (RegExp(r'^aac(\d(\d)?)?$').hasMatch(token)) return 'AAC';
      if (RegExp(r'^flac(\d(\d)?)?$').hasMatch(token)) return 'FLAC';
      if (token == 'mp3') return 'MP3';
      if (token == 'opus') return 'Opus';
    }
    return null;
  }

  /// The group that made the release: the word after the last dash, before
  /// any bracketed tags a site added ("-NTb[rarbg]").
  static String? _releaseGroup(String name) {
    var trimmed = name.replaceAll(RegExp(r'(\s*\[[^\]]*\])+$'), '').trim();
    trimmed = trimmed.replaceAll(RegExp(r'(\s*\([^)]*\))+$'), '').trim();
    final match = RegExp(r'-([A-Za-z0-9][A-Za-z0-9@&]{1,24})$').firstMatch(trimmed);
    if (match == null) return null;
    final group = match.group(1)!;
    final lower = group.toLowerCase();
    // Words that end a name without being a group: "WEB-DL", "Blu-ray", "DD5.1".
    const notGroups = {
      'dl',
      'ray',
      'rip',
      'hd',
      'sdh',
      'hi',
      'eng',
      'en',
      'forced',
      '1',
      '0',
      'x264',
      'x265',
      'h264',
      'h265',
      'hevc',
      'avc',
      '1080p',
      '720p',
      '2160p',
      '480p',
      'web',
      'webrip',
      'bluray',
      'hdtv',
    };
    if (notGroups.contains(lower)) return null;
    if (RegExp(r'^\d+$').hasMatch(group)) return null;
    if (RegExp(r'^s\d+e\d+$', caseSensitive: false).hasMatch(group)) return null;
    return group;
  }

  static const _services = {
    'NF': 'Netflix',
    'AMZN': 'Amazon',
    'DSNP': 'Disney+',
    'DSNY': 'Disney+',
    'HMAX': 'Max',
    'MAX': 'Max',
    'ATVP': 'Apple TV+',
    'HULU': 'Hulu',
    'PCOK': 'Peacock',
    'PMTP': 'Paramount+',
    'STAN': 'Stan',
    'CR': 'Crunchyroll',
    'iT': 'iTunes',
    'ITUNES': 'iTunes',
    'DSCP': 'Discovery+',
    'CRAV': 'Crave',
    'SHO': 'Showtime',
    'HBO': 'HBO',
    'RED': 'YouTube Red',
    'VIAP': 'Viaplay',
    'SKST': 'SkyShowtime',
    'NOW': 'NOW',
    'BCORE': 'Bravia Core',
    'MA': 'Movies Anywhere',
  };

  static String? _service(List<String> tokens) {
    for (final token in tokens) {
      // Case matters: "iT" is iTunes, "it" is a word; "MA" is Movies Anywhere
      // only in capitals, and "DTS-HD.MA" is not it.
      final service = _services[token] ?? (token.length > 3 ? _services[token.toUpperCase()] : null);
      if (service == null) continue;
      if (token == 'MA' && tokens.any((t) => t.toUpperCase() == 'DTS' || t.toUpperCase() == 'HD')) continue;
      return service;
    }
    return null;
  }

  static String? _edition(String joined) {
    if (joined.contains(' extended ')) return 'Extended';
    if (joined.contains(' directors cut ') || joined.contains(' director s cut ') || joined.contains(' dc ')) {
      return "Director's Cut";
    }
    if (joined.contains(' unrated ')) return 'Unrated';
    if (joined.contains(' uncut ')) return 'Uncut';
    if (joined.contains(' theatrical ')) return 'Theatrical';
    if (joined.contains(' imax ')) return 'IMAX';
    if (joined.contains(' final cut ')) return 'Final Cut';
    if (joined.contains(' criterion ')) return 'Criterion';
    if (joined.contains(' remastered ')) return 'Remastered';
    return null;
  }

  ReleaseInfo copyWith({
    int? year,
    int? season,
    List<int>? episodes,
    ReleaseSource? source,
    String? resolution,
    String? videoCodec,
    String? audioCodec,
    String? releaseGroup,
    String? streamingService,
    String? edition,
  }) {
    return ReleaseInfo(
      year: year ?? this.year,
      season: season ?? this.season,
      episodes: episodes ?? this.episodes,
      source: source ?? this.source,
      resolution: resolution ?? this.resolution,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      releaseGroup: releaseGroup ?? this.releaseGroup,
      streamingService: streamingService ?? this.streamingService,
      edition: edition ?? this.edition,
      hearingImpaired: hearingImpaired,
    );
  }

  /// Fills what this name leaves out from [other] - the file name first,
  /// then what the streams say.
  ReleaseInfo mergedWith(ReleaseInfo other) => ReleaseInfo(
        year: year ?? other.year,
        season: season ?? other.season,
        episodes: episodes.isNotEmpty ? episodes : other.episodes,
        source: source ?? other.source,
        resolution: resolution ?? other.resolution,
        videoCodec: videoCodec ?? other.videoCodec,
        audioCodec: audioCodec ?? other.audioCodec,
        releaseGroup: releaseGroup ?? other.releaseGroup,
        streamingService: streamingService ?? other.streamingService,
        edition: edition ?? other.edition,
        hearingImpaired: hearingImpaired || other.hearingImpaired,
      );

  @override
  String toString() => 'ReleaseInfo(year: $year, S$season E$episodes, $source, $resolution, $videoCodec, '
      '$audioCodec, group: $releaseGroup, service: $streamingService, edition: $edition, hi: $hearingImpaired)';
}

enum ReleaseSource {
  bluRay('Blu-ray'),
  web('Web'),
  hdtv('HDTV'),
  dvd('DVD'),
  vhs('VHS'),
  cam('Cam');

  const ReleaseSource(this.label);
  final String label;

  /// Sources Bazarr treats as one: a DVD rip and a VHS rip are both
  /// standard-definition discs as far as timing goes.
  String get family => switch (this) {
        ReleaseSource.dvd || ReleaseSource.vhs => 'Disc',
        _ => label,
      };
}
