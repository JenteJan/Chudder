import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/external_ratings_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/person_model.dart';
import 'package:chudder/models/seerr/seerr_dashboard_model.dart';
import 'package:chudder/providers/items/person_details_provider.dart';
import 'package:chudder/providers/seerr/seerr_details_provider.dart';
import 'package:chudder/screens/seerr/seerr_person_link.dart';
import 'package:chudder/seerr/seerr_models.dart';
import 'package:chudder/util/external_links.dart';

SeerrDashboardPosterModel _poster(SeerrMediaType type) => SeerrDashboardPosterModel(
      id: '603',
      type: type,
      tmdbId: 603,
      title: 'The Matrix',
      overview: '',
      images: ImagesData(),
      mediaStatus: SeerrMediaStatus.unknown,
      jellyfinItemId: null,
      releaseYear: '1999',
    );

PersonModel _libraryPerson(String id, String name, {String? tmdb}) => PersonModel.fromBaseDto(
      BaseItemDto(id: id, name: name, type: BaseItemKind.person, providerIds: {if (tmdb != null) 'Tmdb': tmdb}),
      null,
    );

void main() {
  test('a film\'s details keep its studios and a show\'s its networks, runtime, creators and TVDB id', () {
    final movie = SeerrMovieDetails.fromJson({
      'id': 603,
      'runtime': 136,
      'productionCompanies': [
        {'id': 79, 'name': 'Village Roadshow Pictures', 'logoPath': '/x.png', 'originCountry': 'US'},
        {'id': 1, 'name': null},
      ],
    });
    expect(movie.runtime, 136);
    expect(movie.productionCompanies!.map((e) => e.name), ['Village Roadshow Pictures', '']);

    final show = SeerrTvDetails.fromJson({
      'id': 1396,
      'episodeRunTime': [47, 58],
      'networks': [
        {'id': 174, 'name': 'AMC'},
      ],
      'createdBy': [
        {'id': 66633, 'name': 'Vince Gilligan', 'profilePath': '/v.jpg'},
      ],
      'externalIds': {'imdbId': 'tt0903747', 'tvdbId': 81189},
    });
    expect(show.episodeRunTime, [47, 58]);
    expect(show.networks!.single.name, 'AMC');
    expect(show.createdBy!.single.name, 'Vince Gilligan');
    expect(show.externalIds!.tvdbId, 81189);
  });

  test('a Discover film links to the same sites a library film does', () {
    final model = SeerrDetailsModel(
      poster: _poster(SeerrMediaType.movie),
      mediaType: SeerrMediaType.movie,
      externalIds: SeerrExternalIds(imdbId: 'tt0133093'),
    );
    final links = model.externalLinks(
      ratings: const ExternalRatings(rtUrl: 'https://www.rottentomatoes.com/m/matrix'),
    );
    final sites = links.map((link) => link.site).toSet();
    expect(
      sites,
      containsAll([
        ExternalSite.imdb,
        ExternalSite.tmdb,
        ExternalSite.letterboxd,
        ExternalSite.trakt,
        ExternalSite.rottenTomatoes,
      ]),
    );
    expect(links.firstWhere((link) => link.site == ExternalSite.tmdb).url, 'https://www.themoviedb.org/movie/603');
    expect(links.firstWhere((link) => link.site == ExternalSite.imdb).url, 'https://www.imdb.com/title/tt0133093/');
  });

  test('a Discover show links to its TV pages and TVDB, and not to Letterboxd', () {
    final model = SeerrDetailsModel(
      poster: _poster(SeerrMediaType.tvshow),
      mediaType: SeerrMediaType.tvshow,
      externalIds: SeerrExternalIds(imdbId: 'tt0903747', tvdbId: 81189),
    );
    final links = model.externalLinks();
    expect(links.map((link) => link.site), isNot(contains(ExternalSite.letterboxd)));
    expect(links.firstWhere((link) => link.site == ExternalSite.tmdb).url, 'https://www.themoviedb.org/tv/603');
    expect(
        links.firstWhere((link) => link.site == ExternalSite.tvdb).url, 'https://thetvdb.com/dereferrer/series/81189');
  });

  test('the ratings are looked up once, after the details have said which IMDb title it is', () {
    final opening = SeerrDetailsModel(poster: _poster(SeerrMediaType.movie), mediaType: SeerrMediaType.movie);
    expect(opening.ratingsRequest, isNull);

    final loaded = opening.copyWith(externalIds: SeerrExternalIds(imdbId: 'tt0133093'), detailsLoaded: true);
    expect(loaded.ratingsRequest, (tmdbId: 603, imdbId: 'tt0133093', isSeries: false, title: 'The Matrix', year: 1999));
  });

  test('a face from Seerr is matched to the library by TMDB id, or by a name only one person has', () {
    final keanu = Person(id: '6384', name: 'Keanu Reeves');

    expect(
      matchLibraryPerson(keanu, [
        _libraryPerson('a', 'Keanu Reeves', tmdb: '1'),
        _libraryPerson('b', 'K. Reeves', tmdb: '6384'),
      ])?.id,
      'b',
    );
    expect(matchLibraryPerson(keanu, [_libraryPerson('c', 'keanu reeves')])?.id, 'c');
    // Same name, but the server knows them as someone else.
    expect(matchLibraryPerson(keanu, [_libraryPerson('d', 'Keanu Reeves', tmdb: '99')]), isNull);
    // Two of them and nothing to tell them apart.
    expect(
        matchLibraryPerson(keanu, [_libraryPerson('e', 'Keanu Reeves'), _libraryPerson('f', 'Keanu Reeves')]), isNull);
  });

  test('someone only Seerr knows is opened under a marked id the server never sees', () {
    expect(seerrPersonId('6384'), 'tmdb:6384');
    expect(seerrPersonTmdbId(seerrPersonId('6384')), 6384);
    expect(seerrPersonTmdbId('0123456789abcdef0123456789abcdef'), isNull);
  });

  test('a Seerr person comes with a portrait big enough for their page', () {
    final person = SeerrPersonDetails.fromJson({
      'id': 6384,
      'name': 'Keanu Reeves',
      'biography': 'Actor.',
      'birthday': '1964-09-02',
      'placeOfBirth': 'Beirut, Lebanon',
      'imdbId': 'nm0000206',
      'profilePath': '/k.jpg',
    });
    expect(person.portraitUrl, 'https://image.tmdb.org/t/p/h632/k.jpg');
    expect(person.imdbId, 'nm0000206');
  });
}
