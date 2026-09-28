import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import 'package:chudder/models/bazarr_credentials_model.dart';
import 'package:chudder/models/subtitles/subtitle_match.dart';

/// A small client for the parts of Bazarr's API a player needs: find the
/// film or episode, search its providers, download a pick, and remove a file
/// it put there. Everything answers in Bazarr's own shapes, read loosely -
/// the API has changed shape a few times over the last two years.
class BazarrClient {
  BazarrClient(this.credentials, {http.Client? client}) : _client = client ?? http.Client();

  final BazarrCredentialsModel credentials;
  final http.Client _client;

  /// Manual searches ask every provider Bazarr has and last as long as the
  /// slowest of them.
  static const searchTimeout = Duration(seconds: 90);
  static const requestTimeout = Duration(seconds: 20);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    var base = credentials.serverUrl.trim();
    if (!base.contains('://')) base = 'http://$base';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.parse('$base/api/$path');
    if (query == null || query.isEmpty) return uri;
    // Arrays go as `radarrid[]=1&radarrid[]=2`, which Uri writes for a list.
    return uri.replace(queryParameters: query.map((k, v) => MapEntry(k, v is List ? v.map((e) => '$e').toList() : '$v')));
  }

  Map<String, String> get _headers => {'X-API-KEY': credentials.apiKey.trim(), 'Accept': 'application/json'};

  Future<dynamic> _get(String path, [Map<String, dynamic>? query, Duration? timeout]) async {
    final response = await _client.get(_uri(path, query), headers: _headers).timeout(timeout ?? requestTimeout);
    return _decode(response);
  }

  Future<dynamic> _send(String method, String path, Map<String, String> fields, {Map<String, dynamic>? query}) async {
    final request = http.MultipartRequest(method, _uri(path, query))
      ..headers.addAll(_headers)
      ..fields.addAll(fields);
    final streamed = await _client.send(request).timeout(requestTimeout);
    return _decode(await http.Response.fromStream(streamed));
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const BazarrException(BazarrError.unauthorized);
    }
    if (response.statusCode == 404) throw BazarrException(BazarrError.notFound, _message(response.body));
    if (response.statusCode >= 400) throw BazarrException(BazarrError.server, _message(response.body));
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      // A web server answering where Bazarr should be: the wrong address.
      throw const BazarrException(BazarrError.notBazarr);
    }
  }

  static String? _message(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is String) return decoded;
      if (decoded is Map && decoded['message'] is String) return decoded['message'] as String;
    } catch (_) {}
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.startsWith('<')) return null;
    return trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
  }

  /// Bazarr's version, which also proves the key: the status call needs it.
  Future<String> version() async {
    final body = await _get('system/status');
    final data = body is Map ? body['data'] : null;
    if (data is! Map) throw const BazarrException(BazarrError.notBazarr);
    return '${data['bazarr_version'] ?? '?'}';
  }

  /// Finds the Bazarr movie for a film by its IMDb id. Bazarr has no lookup
  /// by id, so this searches by title and checks each hit.
  Future<BazarrMovie?> findMovie({required String title, String? imdbId, int? year, String? fileName}) async {
    final hits = await _titleSearch(title);
    final ids = [for (final hit in hits) if (hit['radarrId'] != null) hit['radarrId']];
    if (ids.isEmpty) return null;
    final body = await _get('movies', {'radarrid[]': ids});
    final movies = [for (final row in _data(body)) BazarrMovie.fromJson(row)];
    return _pick(movies, imdbId: imdbId, year: year, fileName: fileName, idOf: (m) => m.imdbId, yearOf: (m) => m.year,
        pathOf: (m) => m.path);
  }

  /// Finds the Bazarr episode for a series episode.
  Future<BazarrEpisode?> findEpisode({
    required String seriesTitle,
    String? seriesImdbId,
    String? seriesTvdbId,
    int? seriesYear,
    required int season,
    required int episode,
    String? fileName,
  }) async {
    final hits = await _titleSearch(seriesTitle);
    final ids = [for (final hit in hits) if (hit['sonarrSeriesId'] != null) hit['sonarrSeriesId']];
    if (ids.isEmpty) return null;
    final body = await _get('series', {'seriesid[]': ids});
    final series = _data(body).whereType<Map>().toList();
    Map? match;
    for (final row in series) {
      final imdb = row['imdbId']?.toString();
      final tvdb = row['tvdbId']?.toString();
      if ((seriesImdbId != null && imdb == seriesImdbId) || (seriesTvdbId != null && tvdb == seriesTvdbId)) {
        match = row;
        break;
      }
    }
    match ??= series.length == 1 ? series.first : null;
    final seriesId = match?['sonarrSeriesId'];
    if (seriesId == null) return null;
    final episodes = [
      for (final row in _data(await _get('episodes', {'seriesid[]': [seriesId]}))) BazarrEpisode.fromJson(row),
    ];
    return episodes.where((e) => e.season == season && e.episode == episode).firstOrNull;
  }

  Future<List<Map>> _titleSearch(String title) async {
    final body = await _get('system/searches', {'query': title});
    final list = body is List ? body : _data(body);
    return list.whereType<Map>().toList();
  }

  static T? _pick<T>(
    List<T> items, {
    String? imdbId,
    int? year,
    String? fileName,
    required String? Function(T) idOf,
    required int? Function(T) yearOf,
    required String? Function(T) pathOf,
  }) {
    if (imdbId != null && imdbId.isNotEmpty) {
      for (final item in items) {
        if (idOf(item) == imdbId) return item;
      }
    }
    if (fileName != null && fileName.isNotEmpty) {
      for (final item in items) {
        if (_baseName(pathOf(item)) == fileName) return item;
      }
    }
    final sameYear = items.where((item) => year != null && yearOf(item) == year).toList();
    return sameYear.length == 1 ? sameYear.first : null;
  }

  /// Every result of a manual search, for all of the item's profile
  /// languages; [BazarrResult.language] says which.
  Future<List<BazarrResult>> searchMovie(int radarrId) async {
    final body = await _get('providers/movies', {'radarrid': radarrId}, searchTimeout);
    return [for (final row in _data(body)) BazarrResult.fromJson(row)];
  }

  Future<List<BazarrResult>> searchEpisode(int episodeId) async {
    final body = await _get('providers/episodes', {'episodeid': episodeId}, searchTimeout);
    return [for (final row in _data(body)) BazarrResult.fromJson(row)];
  }

  /// Queues the download; Bazarr answers before the file is written.
  Future<void> download(BazarrTarget target, BazarrResult result) async {
    final fields = {
      'hi': _flag(result.hearingImpaired),
      'forced': _flag(result.forced),
      'original_format': _flag(result.originalFormat),
      'provider': result.provider,
      'subtitle': result.token,
      'language': result.language,
    };
    switch (target) {
      case BazarrMovie(:final radarrId):
        await _send('POST', 'providers/movies', {...fields, 'radarrid': '$radarrId'},
            query: {'radarrid': radarrId});
      case BazarrEpisode(:final seriesId, :final episodeId):
        await _send('POST', 'providers/episodes', {...fields, 'seriesid': '$seriesId', 'episodeid': '$episodeId'},
            query: {'seriesid': seriesId, 'episodeid': episodeId});
    }
  }

  /// The item again, with the subtitle files Bazarr sees next to it now.
  Future<BazarrTarget?> reload(BazarrTarget target) async {
    switch (target) {
      case BazarrMovie(:final radarrId):
        final rows = _data(await _get('movies', {'radarrid[]': [radarrId]}));
        return rows.isEmpty ? null : BazarrMovie.fromJson(rows.first);
      case BazarrEpisode(:final episodeId):
        final rows = _data(await _get('episodes', {'episodeid[]': [episodeId]}));
        return rows.isEmpty ? null : BazarrEpisode.fromJson(rows.first);
    }
  }

  /// What Bazarr did to this item: which files it downloaded, from where,
  /// and under which id - the id a blacklist entry needs.
  Future<List<BazarrHistoryEntry>> history(BazarrTarget target) async {
    final body = switch (target) {
      BazarrMovie(:final radarrId) => await _get('movies/history', {'radarrid': radarrId}),
      BazarrEpisode(:final episodeId) => await _get('episodes/history', {'episodeid': episodeId}),
    };
    return [for (final row in _data(body)) BazarrHistoryEntry.fromJson(row)];
  }

  /// Deletes one of the item's subtitle files through Bazarr, so its history
  /// and database know.
  Future<void> deleteSubtitle(BazarrTarget target, BazarrSubtitleFile file) async {
    final fields = {
      'language': file.code2,
      'forced': file.forced ? 'true' : 'false',
      'hi': file.hearingImpaired ? 'true' : 'false',
      'path': file.path ?? '',
    };
    switch (target) {
      case BazarrMovie(:final radarrId):
        await _send('DELETE', 'movies/subtitles', {...fields, 'radarrid': '$radarrId'}, query: {'radarrid': radarrId});
      case BazarrEpisode(:final seriesId, :final episodeId):
        await _send('DELETE', 'episodes/subtitles', {...fields, 'seriesid': '$seriesId', 'episodeid': '$episodeId'},
            query: {'seriesid': seriesId, 'episodeid': episodeId});
    }
  }

  /// Blacklists a subtitle Bazarr downloaded: it deletes the file, will not
  /// pick that one again, and looks for another for any language now
  /// missing.
  Future<void> blacklist(BazarrTarget target, BazarrSubtitleFile file, BazarrHistoryEntry entry) async {
    final fields = {
      'provider': entry.provider,
      'subs_id': entry.subsId,
      'language': file.code2,
      'subtitles_path': file.path ?? '',
    };
    switch (target) {
      case BazarrMovie(:final radarrId):
        await _send('POST', 'movies/blacklist', {...fields, 'radarrid': '$radarrId'}, query: {'radarrid': radarrId});
      case BazarrEpisode(:final seriesId, :final episodeId):
        await _send('POST', 'episodes/blacklist', {...fields, 'seriesid': '$seriesId', 'episodeid': '$episodeId'},
            query: {'seriesid': seriesId, 'episodeid': episodeId});
    }
  }

  /// Runs one of Bazarr's subtitle tools on a file it lists: `sync` (to the
  /// video's audio, as a queued job), or a mod such as
  /// `shift_offset(h=0,m=0,s=-1,ms=-250)`, `change_FPS(from=25,to=23.976)` or
  /// `remove_HI`. Mods work on .srt files only and rewrite them in place
  /// (remove_HI writes to the name without the hearing-impaired tag).
  Future<void> subtitleTool(BazarrTarget target, BazarrSubtitleFile file, String action) async {
    final (type, id) = switch (target) {
      BazarrMovie(:final radarrId) => ('movie', radarrId),
      BazarrEpisode(:final episodeId) => ('episode', episodeId),
    };
    await _send(
      'PATCH',
      'subtitles',
      {
        'language': file.code2,
        'type': type,
        'id': '$id',
        'path': file.path ?? '',
        'forced': _flag(file.forced),
        'hi': _flag(file.hearingImpaired),
      },
      query: {'action': action},
    );
  }

  /// Has Bazarr translate [file] into [toLanguage] (two letters) with the
  /// translator set up in Bazarr. The translation is a new file next to the
  /// video.
  Future<void> translate(BazarrTarget target, BazarrSubtitleFile file, String toLanguage) async {
    final (type, id) = switch (target) {
      BazarrMovie(:final radarrId) => ('movie', radarrId),
      BazarrEpisode(:final episodeId) => ('episode', episodeId),
    };
    await _send(
      'PATCH',
      'subtitles',
      {
        'language': toLanguage,
        'type': type,
        'id': '$id',
        'path': file.path ?? '',
        'forced': _flag(file.forced),
        'hi': _flag(file.hearingImpaired),
      },
      query: {'action': 'translate'},
    );
  }

  /// Has Bazarr search and download the best subtitle for [language] (two
  /// letters) by its own scoring - what it does on its schedule, now.
  Future<void> searchAutomatically(BazarrTarget target, String language, {bool hi = false, bool forced = false}) async {
    final fields = {'language': language, 'hi': _flag(hi), 'forced': _flag(forced)};
    switch (target) {
      case BazarrMovie(:final radarrId):
        await _send('PATCH', 'movies/subtitles', {...fields, 'radarrid': '$radarrId'}, query: {'radarrid': radarrId});
      case BazarrEpisode(:final seriesId, :final episodeId):
        await _send('PATCH', 'episodes/subtitles', {...fields, 'seriesid': '$seriesId', 'episodeid': '$episodeId'},
            query: {'seriesid': seriesId, 'episodeid': episodeId});
    }
  }

  /// Bazarr's mod string for moving every line by [offset].
  static String shiftAction(Duration offset) {
    final sign = offset.isNegative ? -1 : 1;
    final total = offset.abs();
    return 'shift_offset(h=${sign * total.inHours},m=${sign * (total.inMinutes % 60)},'
        's=${sign * (total.inSeconds % 60)},ms=${sign * (total.inMilliseconds % 1000)})';
  }

  static String frameRateAction(double from, double to) => 'change_FPS(from=${_num(from)},to=${_num(to)})';

  static String _num(double value) {
    final rounded = (value * 1000).round() / 1000;
    return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : '$rounded';
  }

  void close() => _client.close();

  static List<Map> _data(dynamic body) {
    final data = body is Map ? body['data'] : body;
    return data is List ? data.whereType<Map>().toList() : const [];
  }

  static String _flag(bool value) => value ? 'True' : 'False';
}

String? _baseName(String? path) {
  if (path == null || path.isEmpty) return null;
  final separator = path.lastIndexOf(RegExp(r'[\\/]'));
  return separator == -1 ? path : path.substring(separator + 1);
}

bool _truthy(dynamic value) => value == true || value?.toString().toLowerCase() == 'true';

int? _int(dynamic value) => value is int ? value : int.tryParse('${value ?? ''}');

enum BazarrError { unauthorized, notFound, notBazarr, server, unreachable }

class BazarrException implements Exception {
  const BazarrException(this.error, [this.message]);
  final BazarrError error;
  final String? message;

  @override
  String toString() => message ?? error.name;
}

/// The film or episode on Bazarr's side.
sealed class BazarrTarget {
  const BazarrTarget({this.sceneName, this.path, this.subtitles = const []});

  /// The release name the file had before Sonarr or Radarr renamed it.
  final String? sceneName;
  final String? path;
  final List<BazarrSubtitleFile> subtitles;

  /// The subtitle file Bazarr lists under [fileName], if it knows it.
  BazarrSubtitleFile? fileNamed(String fileName) =>
      subtitles.where((s) => s.path != null && _baseName(s.path) == fileName).firstOrNull;
}

class BazarrMovie extends BazarrTarget {
  const BazarrMovie({required this.radarrId, this.imdbId, this.year, super.sceneName, super.path, super.subtitles});

  final int radarrId;
  final String? imdbId;
  final int? year;

  factory BazarrMovie.fromJson(Map json) => BazarrMovie(
        radarrId: _int(json['radarrId']) ?? -1,
        imdbId: json['imdbId']?.toString(),
        year: _int(json['year']),
        sceneName: json['sceneName']?.toString(),
        path: json['path']?.toString(),
        subtitles: BazarrSubtitleFile.listFrom(json['subtitles']),
      );
}

class BazarrEpisode extends BazarrTarget {
  const BazarrEpisode({
    required this.seriesId,
    required this.episodeId,
    required this.season,
    required this.episode,
    super.sceneName,
    super.path,
    super.subtitles,
  });

  final int seriesId;
  final int episodeId;
  final int season;
  final int episode;

  factory BazarrEpisode.fromJson(Map json) => BazarrEpisode(
        seriesId: _int(json['sonarrSeriesId']) ?? -1,
        episodeId: _int(json['sonarrEpisodeId']) ?? -1,
        season: _int(json['season']) ?? -1,
        episode: _int(json['episode']) ?? -1,
        sceneName: json['sceneName']?.toString(),
        path: json['path']?.toString(),
        subtitles: BazarrSubtitleFile.listFrom(json['subtitles']),
      );
}

class BazarrSubtitleFile {
  const BazarrSubtitleFile({
    required this.code2,
    this.code3,
    this.path,
    this.forced = false,
    this.hearingImpaired = false,
  });

  final String code2;
  final String? code3;

  /// Null for a track inside the video.
  final String? path;
  final bool forced;
  final bool hearingImpaired;

  static List<BazarrSubtitleFile> listFrom(dynamic value) => [
        if (value is List)
          for (final row in value.whereType<Map>())
            BazarrSubtitleFile(
              code2: row['code2']?.toString() ?? '',
              code3: row['code3']?.toString(),
              path: row['path']?.toString(),
              forced: _truthy(row['forced']),
              hearingImpaired: _truthy(row['hi']),
            ),
      ];
}

class BazarrHistoryEntry {
  const BazarrHistoryEntry({
    required this.provider,
    required this.subsId,
    this.path,
    this.action,
    this.timestamp,
    this.blacklisted = false,
  });

  final String provider;
  final String subsId;
  final String? path;
  final int? action;
  final String? timestamp;
  final bool blacklisted;

  /// Tells one entry from another; Bazarr gives entries no id of their own.
  String get identity => '$action|$provider|$subsId|$path|$timestamp';

  factory BazarrHistoryEntry.fromJson(Map json) => BazarrHistoryEntry(
        provider: json['provider']?.toString() ?? '',
        subsId: json['subs_id']?.toString() ?? '',
        path: json['subtitles_path']?.toString(),
        action: _int(json['action']),
        timestamp: (json['parsed_timestamp'] ?? json['timestamp'])?.toString(),
        blacklisted: _truthy(json['blacklisted']),
      );
}

class BazarrResult {
  const BazarrResult({
    required this.provider,
    required this.token,
    required this.language,
    required this.score,
    this.matches = const [],
    this.dontMatches = const [],
    this.releases = const [],
    this.hearingImpaired = false,
    this.forced = false,
    this.originalFormat = false,
    this.uploader,
    this.url,
  });

  final String provider;

  /// Opaque: what the download call wants back. Lives an hour in Bazarr.
  final String token;

  /// Bazarr's language code, two letters ("en", "pt-BR").
  final String language;

  /// Percentage.
  final double score;
  final List<String> matches;
  final List<String> dontMatches;
  final List<String> releases;
  final bool hearingImpaired;
  final bool forced;
  final bool originalFormat;
  final String? uploader;
  final String? url;

  factory BazarrResult.fromJson(Map json) {
    List<String> strings(dynamic value) => value is List ? value.map((e) => '$e').toList() : const [];
    return BazarrResult(
      provider: json['provider']?.toString() ?? '',
      token: json['subtitle']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      score: (json['score'] is num ? (json['score'] as num).toDouble() : double.tryParse('${json['score']}')) ?? 0,
      matches: strings(json['matches']),
      dontMatches: strings(json['dont_matches']),
      releases: strings(json['release_info']).where((e) => e.trim().isNotEmpty).toList(),
      hearingImpaired: _truthy(json['hearing_impaired']),
      forced: _truthy(json['forced']),
      originalFormat: _truthy(json['original_format']),
      uploader: json['uploader']?.toString(),
      url: json['url']?.toString(),
    );
  }

  /// Bazarr's field names in the terms the list shows.
  static Set<MatchField> fields(List<String> names) => names
      .map((name) => switch (name) {
            'hash' => MatchField.hash,
            'season' || 'episode' => MatchField.episode,
            'year' => MatchField.year,
            'edition' => MatchField.edition,
            'release_group' => MatchField.releaseGroup,
            'source' => MatchField.source,
            'streaming_service' => MatchField.streamingService,
            'resolution' => MatchField.resolution,
            'video_codec' => MatchField.videoCodec,
            'audio_codec' => MatchField.audioCodec,
            'hearing_impaired' => MatchField.hearingImpaired,
            _ => null,
          })
      .nonNulls
      .toSet();
}
