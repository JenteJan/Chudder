import 'dart:convert';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/models/external_ratings_model.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// The rating sites' verdict on one film or show, fetched once and kept for
/// the session. Every source is optional and every failure is silent: a page
/// simply shows the ratings it could get.
final externalRatingsProvider = FutureProvider.family<ExternalRatings, ExternalRatingsRequest>((ref, request) async {
  final seerrConfigured = ref.read(userProvider)?.seerrCredentials?.isConfigured ?? false;
  final omdbKey = ref.read(clientSettingsProvider).omdbApiKey?.trim();

  final results = await Future.wait<ExternalRatings?>([
    if (seerrConfigured && request.tmdbId != null) _fromSeerr(ref, request),
    if (omdbKey != null && omdbKey.isNotEmpty) _fromOmdb(request, omdbKey),
  ]);

  var merged = ExternalRatings.empty;
  for (final result in results) {
    merged = merged.merge(result);
  }
  return merged;
});

Future<ExternalRatings?> _fromSeerr(Ref ref, ExternalRatingsRequest request) async {
  try {
    final seerr = ref.read(seerrApiProvider);
    final tmdbId = request.tmdbId!;
    if (request.isSeries) {
      final details = seerr.tvDetails(tvId: tmdbId);
      final rt = await seerr.tvRatings(tmdbId);
      final tv = (await details).body;
      return ExternalRatings(
        tmdb: _nonZero(tv?.voteAverage),
        tmdbVotes: tv?.voteCount,
        rtCritics: rt?.criticsScore,
        rtAudience: rt?.audienceScore,
        rtUrl: rt?.url,
      );
    } else {
      final details = seerr.movieDetails(tmdbId: tmdbId);
      final ratings = await seerr.movieRatings(tmdbId);
      final movie = (await details).body;
      return ExternalRatings(
        tmdb: _nonZero(movie?.voteAverage),
        tmdbVotes: movie?.voteCount,
        rtCritics: ratings?.rt?.criticsScore,
        rtAudience: ratings?.rt?.audienceScore,
        rtUrl: ratings?.rt?.url,
        imdb: _nonZero(ratings?.imdb?.criticsScore),
        imdbUrl: ratings?.imdb?.url,
      );
    }
  } catch (e) {
    log('Seerr ratings lookup failed: $e');
    return null;
  }
}

double? _nonZero(double? value) => (value == null || value == 0) ? null : value;

/// OMDb: one small JSON document per title, looked up by IMDb id when there is
/// one and by name otherwise.
Future<ExternalRatings?> _fromOmdb(ExternalRatingsRequest request, String apiKey) async {
  try {
    if (request.imdbId == null && request.title.trim().isEmpty) return null;
    final query = <String, String>{
      'apikey': apiKey,
      if (request.imdbId != null) 'i': request.imdbId! else 't': request.title,
      if (request.imdbId == null) 'type': request.isSeries ? 'series' : 'movie',
      if (request.imdbId == null && request.year != null) 'y': request.year.toString(),
    };
    final response = await http.get(Uri.https('www.omdbapi.com', '/', query)).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic> || json['Response'] != 'True') return null;

    int? percent(String? value) {
      if (value == null) return null;
      return int.tryParse(value.replaceAll('%', '').split('/').first.trim());
    }

    int? rt;
    int? metacritic;
    for (final entry in (json['Ratings'] as List<dynamic>? ?? const [])) {
      if (entry is! Map) continue;
      final source = entry['Source']?.toString() ?? '';
      final value = entry['Value']?.toString();
      if (source.contains('Rotten')) rt = percent(value);
      if (source.contains('Metacritic')) metacritic = percent(value);
    }
    final imdbId = json['imdbID']?.toString();
    final title = json['Title']?.toString();
    return ExternalRatings(
      imdb: double.tryParse(json['imdbRating']?.toString() ?? ''),
      imdbVotes: int.tryParse((json['imdbVotes']?.toString() ?? '').replaceAll(',', '')),
      rtCritics: rt,
      metacritic: metacritic ?? int.tryParse(json['Metascore']?.toString() ?? ''),
      imdbUrl: imdbId == null || imdbId.isEmpty ? null : 'https://www.imdb.com/title/$imdbId/',
      metacriticUrl: title == null ? null : 'https://www.metacritic.com/search/${Uri.encodeComponent(title)}/',
    );
  } catch (e) {
    log('OMDb ratings lookup failed: $e');
    return null;
  }
}
