import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/person_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/util/search_relevance.dart';

MediaStreamsModel _streams() => MediaStreamsModel(versionStreams: const []);

MovieModel _movie(String name, {bool favourite = false}) => MovieModel(
      originalTitle: name,
      premiereDate: DateTime(2000),
      sortName: name,
      status: "",
      name: name,
      id: name,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: UserData(isFavourite: favourite),
      parentImages: null,
      mediaStreams: _streams(),
      canDownload: null,
      canDelete: null,
    );

SeriesModel _series(String name) => SeriesModel(
      status: "",
      originalTitle: name,
      sortName: name,
      name: name,
      id: name,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      canDownload: null,
      canDelete: null,
    );

EpisodeModel _episode(String name) => EpisodeModel(
      seriesName: name,
      season: 1,
      episode: 1,
      episodeEnd: null,
      name: name,
      id: name,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: _streams(),
      canDownload: null,
      canDelete: null,
    );

ItemBaseModel _studio(String name) => ItemBaseModel(
      name: name,
      id: name,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      canDownload: null,
      canDelete: null,
      jellyType: BaseItemKind.studio,
    );

PersonModel _person(String name, {int appearances = 0}) => PersonModel(
      libraryItemCount: appearances,
      birthPlace: const [],
      movies: const [],
      series: const [],
      name: name,
      id: name,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      canDownload: null,
      canDelete: null,
    );

void main() {
  List<String> names(List<ItemBaseModel> items) => items.map((e) => e.name).toList();

  test('an exact title beats everything else', () {
    final ranked = [
      _movie("Alienist Diaries"),
      _movie("The Alien Files"),
      _movie("Alien"),
    ].rankedFor("alien");

    expect(names(ranked).first, "Alien");
  });

  test('titles starting with the query come before titles merely containing it', () {
    final ranked = [
      _movie("Marathon Man"),
      _movie("Aliens"),
    ].rankedFor("a");

    expect(names(ranked), ["Aliens", "Marathon Man"]);
  });

  test('a word starting with the query beats a match buried mid-word', () {
    final ranked = [
      _movie("Casablanca"),
      _movie("The Bourne Identity"),
    ].rankedFor("bourne");

    expect(names(ranked).first, "The Bourne Identity");
  });

  test('films, shows and people outrank episodes on an equal name match', () {
    final ranked = [
      _episode("Arrival"),
      _person("Arrival"),
      _series("Arrival"),
      _movie("Arrival"),
    ].rankedFor("arrival");

    expect(names(ranked).last, "Arrival");
    expect(ranked.first.type, anyOf(FladderItemType.movie, FladderItemType.series));
    expect(ranked[2].type, FladderItemType.person);
    expect(ranked.last.type, FladderItemType.episode);
  });

  test('a studio ranks under the films but over the unknowns', () {
    final ranked = [
      _episode("A24"),
      _studio("A24"),
      _movie("A24 Presents"),
    ].rankedFor("a24");

    // What you watch first, then who made it, then the incidentals - even
    // though the studio and the episode match the name exactly and the film
    // only starts with it.
    expect(ranked.first.name, "A24 Presents");
    expect(ranked[1].isStudio, isTrue);
    expect(ranked.last.type, FladderItemType.episode);
  });

  test('a name that visibly matches beats a film the server matched some other way', () {
    final ranked = [
      // The server returns this for "a24" because the overview mentions it,
      // but nothing in the row says so.
      _movie("Something Else"),
      _studio("A24"),
    ].rankedFor("a24");

    expect(ranked.first.isStudio, isTrue);
    expect(ranked.last.name, "Something Else");
  });

  test('the Jack with four films outranks the Jack with one episode', () {
    final ranked = [
      _person("Jack Nobody", appearances: 1),
      _person("Jack Black", appearances: 4),
    ].rankedFor("jack");

    expect(names(ranked).first, "Jack Black");
  });

  test('how much of the library someone is in never reorders anything else', () {
    final ranked = [
      _movie("Jack Reacher"),
      _person("Jack Black", appearances: 40),
    ].rankedFor("jack");

    // Films still come before the people in them, however prolific.
    expect(names(ranked).first, "Jack Reacher");
  });

  test('a favourite wins an otherwise even tie', () {
    final ranked = [
      _movie("Alien A"),
      _movie("Alien B", favourite: true),
    ].rankedFor("alien");

    expect(names(ranked).first, "Alien B");
  });

  test('an empty query leaves the server order alone', () {
    final original = [_movie("Zulu"), _movie("Alien")];
    expect(names(original.rankedFor("  ")), ["Zulu", "Alien"]);
  });
}
