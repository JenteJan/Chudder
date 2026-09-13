import 'package:flutter/material.dart';

import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/external_ratings_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/album_model.dart';
import 'package:chudder/models/items/artist_model.dart';
import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/person_model.dart';
import 'package:chudder/models/items/season_model.dart';
import 'package:chudder/models/items/series_model.dart';

/// The sites something in the library can be looked up on.
///
/// Each carries the colour its own mark is known by, so a row of these reads
/// at a glance the way it would on any other site.
enum ExternalSite {
  imdb,
  tmdb,
  tvdb,
  trakt,
  letterboxd,
  rottenTomatoes,
  metacritic,
  musicBrainz,
  wikipedia,
  other;

  String get label => switch (this) {
        ExternalSite.imdb => 'IMDb',
        ExternalSite.tmdb => 'TMDB',
        ExternalSite.tvdb => 'TVDB',
        ExternalSite.trakt => 'Trakt',
        ExternalSite.letterboxd => 'Letterboxd',
        ExternalSite.rottenTomatoes => 'Rotten Tomatoes',
        ExternalSite.metacritic => 'Metacritic',
        ExternalSite.musicBrainz => 'MusicBrainz',
        ExternalSite.wikipedia => 'Wikipedia',
        ExternalSite.other => '',
      };

  /// The brand's own colour, used as the chip's fill.
  Color get color => switch (this) {
        ExternalSite.imdb => const Color(0xFFF5C518),
        ExternalSite.tmdb => const Color(0xFF01B4E4),
        ExternalSite.tvdb => const Color(0xFF6CD491),
        ExternalSite.trakt => const Color(0xFFED1C24),
        ExternalSite.letterboxd => const Color(0xFF202830),
        ExternalSite.rottenTomatoes => const Color(0xFFFA320A),
        ExternalSite.metacritic => const Color(0xFF001A3B),
        ExternalSite.musicBrainz => const Color(0xFFBA478F),
        ExternalSite.wikipedia => const Color(0xFF3B3B3B),
        ExternalSite.other => const Color(0xFF5A5A5A),
      };

  /// What reads on top of [color].
  Color get foreground => switch (this) {
        ExternalSite.imdb => Colors.black,
        ExternalSite.tvdb => Colors.black,
        _ => Colors.white,
      };

  /// The order they are shown in: the ones most people know first.
  int get rank => index;

  static ExternalSite fromName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('imdb')) return ExternalSite.imdb;
    if (lower.contains('themoviedb') || lower.contains('tmdb')) return ExternalSite.tmdb;
    if (lower.contains('thetvdb') || lower.contains('tvdb')) return ExternalSite.tvdb;
    if (lower.contains('trakt')) return ExternalSite.trakt;
    if (lower.contains('letterboxd')) return ExternalSite.letterboxd;
    if (lower.contains('rotten')) return ExternalSite.rottenTomatoes;
    if (lower.contains('metacritic')) return ExternalSite.metacritic;
    if (lower.contains('musicbrainz')) return ExternalSite.musicBrainz;
    if (lower.contains('wikipedia')) return ExternalSite.wikipedia;
    return ExternalSite.other;
  }
}

/// One place an item can be opened on the web.
class ExternalLink {
  final ExternalSite site;
  final String name;
  final String url;

  const ExternalLink({required this.site, required this.name, required this.url});

  IconData get icon => switch (site) {
        ExternalSite.rottenTomatoes => IconsaxPlusBold.star_1,
        ExternalSite.musicBrainz => IconsaxPlusBold.musicnote,
        ExternalSite.wikipedia => IconsaxPlusBold.book_1,
        _ => IconsaxPlusLinear.export_3,
      };
}

extension ItemProviderIds on ItemBaseModel {
  /// The ids the metadata providers know this item by, where the model has
  /// them. Only the kinds that are looked up outside the server carry any.
  Map<String, dynamic>? get providerIdsOrNull => switch (this) {
        MovieModel movie => movie.providerIds,
        SeriesModel series => series.providerIds,
        PersonModel person => person.providerIds,
        AlbumModel album => album.providerIds,
        ArtistModel artist => artist.providerIds,
        AudioModel audio => audio.providerIds,
        _ => null,
      };

  String? _providerId(String key) {
    final ids = providerIdsOrNull;
    if (ids == null) return null;
    for (final entry in ids.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) {
        final value = entry.value?.toString().trim();
        return (value == null || value.isEmpty) ? null : value;
      }
    }
    return null;
  }

  String? get imdbId => _providerId('Imdb');
  String? get tmdbIdString => _providerId('Tmdb');
  String? get tvdbIdString => _providerId('Tvdb');

  bool get _isShowLike => this is SeriesModel || this is SeasonModel || this is EpisodeModel;

  /// Everywhere this item can be opened on the web: what the server already
  /// links to, and what can be worked out from the provider ids on top of it.
  /// One link per site, best-known site first.
  List<ExternalLink> externalLinks({ExternalRatings? ratings}) {
    final found = <ExternalSite, ExternalLink>{};
    final others = <ExternalLink>[];

    void add(ExternalSite site, String url, {String? name}) {
      if (url.isEmpty) return;
      if (site == ExternalSite.other) {
        others.add(ExternalLink(site: site, name: name ?? url, url: url));
        return;
      }
      found.putIfAbsent(site, () => ExternalLink(site: site, name: name ?? site.label, url: url));
    }

    for (final url in overview.externalUrls ?? const <ExternalUrls>[]) {
      add(ExternalSite.fromName(url.name), url.url, name: url.name);
    }

    final imdb = imdbId;
    final tmdb = tmdbIdString;
    final tvdb = tvdbIdString;
    final isPerson = this is PersonModel;

    if (imdb != null) {
      add(ExternalSite.imdb, isPerson ? 'https://www.imdb.com/name/$imdb/' : 'https://www.imdb.com/title/$imdb/');
      if (!isPerson) add(ExternalSite.trakt, 'https://trakt.tv/search/imdb/$imdb');
    }
    if (tmdb != null) {
      final path = isPerson
          ? 'person'
          : _isShowLike
              ? 'tv'
              : 'movie';
      add(ExternalSite.tmdb, 'https://www.themoviedb.org/$path/$tmdb');
      if (this is MovieModel) add(ExternalSite.letterboxd, 'https://letterboxd.com/tmdb/$tmdb/');
    }
    if (tvdb != null) {
      add(ExternalSite.tvdb, 'https://thetvdb.com/dereferrer/${_isShowLike ? 'series' : 'movie'}/$tvdb');
    }
    if (ratings?.rtUrl != null) add(ExternalSite.rottenTomatoes, ratings!.rtUrl!);
    if (ratings?.imdbUrl != null) add(ExternalSite.imdb, ratings!.imdbUrl!);
    if (ratings?.metacritic != null && ratings?.metacriticUrl != null) {
      add(ExternalSite.metacritic, ratings!.metacriticUrl!);
    }

    final sorted = found.values.toList()..sort((a, b) => a.site.rank.compareTo(b.site.rank));
    return [...sorted, ...others];
  }
}
