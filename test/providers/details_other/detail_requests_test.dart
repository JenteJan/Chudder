import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/book_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/album_model.dart';
import 'package:chudder/models/items/artist_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/providers/items/album_details_provider.dart';
import 'package:chudder/providers/items/artist_details_provider.dart';
import 'package:chudder/providers/items/book_details_provider.dart';
import 'package:chudder/providers/items/person_details_provider.dart';
import 'package:chudder/providers/items/studio_details_provider.dart';

import 'fake_jelly_service.dart';

void main() {
  late FakeJellyService service;
  late ProviderContainer container;

  setUp(() {
    service = FakeJellyService();
    container = fakeContainer(service);
  });

  tearDown(() => container.dispose());

  test('an album asks for its tracks and related albums with the album, and never for "related songs"', () async {
    final seed = fakeItem('album', BaseItemKind.musicalbum, parentId: 'artist', artists: ['Artist']) as AlbumModel;
    final provider = albumDetailsProvider('album');
    container.listen(provider, (_, __) {});

    final done = container.read(provider.notifier).fetchDetails(seed);
    await settle();

    // Nothing has answered yet, and all three are already out.
    expect(service.named('usersUserIdItemsItemIdGet'), hasLength(1));
    final tracks = service.query(kind: BaseItemKind.audio);
    final related = service.query(kind: BaseItemKind.musicalbum);
    expect(tracks.arg<String>('parentId'), 'album');
    expect(related.arg<String>('parentId'), 'artist');

    // Rows landing before the album survive the album's arrival.
    tracks.completer.complete(queryResult([fakeItem('t1', BaseItemKind.audio)]));
    related.completer.complete(queryResult([fakeItem('other', BaseItemKind.musicalbum), seed]));
    await settle();
    service.itemGet().completer.complete(okResponse<ItemBaseModel>(seed));
    await done;

    final album = container.read(provider)!;
    expect(album.tracks.map((e) => e.id), ['t1']);
    expect(album.relatedAlbums.map((e) => e.id), ['other']);
    expect(service.named('itemsGet'), hasLength(2));
  });

  test('an album card without a parent waits for the album before asking for related albums', () async {
    final seed = fakeItem('album', BaseItemKind.musicalbum) as AlbumModel;
    final provider = albumDetailsProvider('album');
    container.listen(provider, (_, __) {});

    final done = container.read(provider.notifier).fetchDetails(seed);
    await settle();
    expect(service.named('itemsGet'), hasLength(1));

    service.query(kind: BaseItemKind.audio).completer.complete(queryResult([]));
    service.itemGet().completer.complete(
          okResponse(fakeItem('album', BaseItemKind.musicalbum, parentId: 'artist', artists: ['Artist'])),
        );
    await settle();
    final related = service.query(kind: BaseItemKind.musicalbum);
    expect(related.arg<String>('parentId'), 'artist');
    related.completer.complete(queryResult([]));
    await done;
  });

  test('a person\'s films and series go out with the person, and show together once it has arrived', () async {
    final provider = personDetailsProvider('person');
    container.listen(provider, (_, __) {});

    final done = container.read(provider.notifier).fetchPerson(Person(id: 'person'));
    await settle();

    final movies = service.query(kind: BaseItemKind.movie);
    final series = service.query(kind: BaseItemKind.series);
    expect(movies.arg<List<String>>('personIds'), ['person']);
    expect(series.arg<List<String>>('personIds'), ['person']);

    movies.completer.complete(queryResult([fakeItem('m1', BaseItemKind.movie)]));
    await settle();
    expect(container.read(provider), isNull);

    service.itemGet().completer.complete(okResponse(fakeItem('person', BaseItemKind.person)));
    await settle();
    // Films and series land together, so the backdrop is picked once.
    expect(container.read(provider)!.movies, isEmpty);

    series.completer.complete(queryResult([fakeItem('s1', BaseItemKind.series)]));
    await done;
    expect(container.read(provider)!.series.map((e) => e.id), ['s1']);
    expect(container.read(provider)!.movies.map((e) => e.id), ['m1']);
  });

  test('a studio\'s films go out with the studio', () async {
    final provider = studioDetailsProvider('studio');
    container.listen(provider, (_, __) {});

    final done = container.read(provider.notifier).fetch(null);
    await settle();
    expect(service.named('itemsGet'), hasLength(2));

    service.query(kind: BaseItemKind.movie).completer.complete(queryResult([fakeItem('m1', BaseItemKind.movie)]));
    service.query(kind: BaseItemKind.series).completer.complete(queryResult([]));
    await settle();
    service.itemGet().completer.complete(okResponse(fakeItem('studio', BaseItemKind.studio)));
    await done;

    final details = container.read(provider);
    expect(details.studio?.id, 'studio');
    expect(details.movies.map((e) => e.id), ['m1']);
    expect(details.loading, isFalse);
  });

  test('a book asks for itself, its folder and the libraries at once', () async {
    final book = fakeItem('book', BaseItemKind.book, parentId: 'folder') as BookModel;
    final provider = bookDetailsProvider('book');
    container.listen(provider, (_, __) {});

    final done = container.read(provider.notifier).fetchDetails(book);
    await settle();

    final gets = service.named('usersUserIdItemsItemIdGet').toList();
    expect(gets.map((call) => call.arg<String>('itemId')), ['book', 'folder']);
    expect(service.named('usersUserIdViewsGet'), hasLength(1));

    gets[0].completer.complete(okResponse(book));
    gets[1].completer.complete(okResponse(fakeItem('folder', BaseItemKind.folder, name: 'H. G. Wells')));
    service.named('usersUserIdViewsGet').first.completer.complete(
          okResponse(const BaseItemDtoQueryResult(items: [BaseItemDto(id: 'books', name: 'Books')])),
        );
    await settle();
    final siblings = service.query(kind: BaseItemKind.book);
    expect(siblings.arg<String>('parentId'), 'folder');
    siblings.completer.complete(queryResult([book, fakeItem('book2', BaseItemKind.book, parentId: 'folder')]));
    await done;

    expect(container.read(provider).chapters.map((e) => e.id), ['book', 'book2']);
    expect(service.named('usersUserIdItemsItemIdGet'), hasLength(2));
  });

  test("an artist's rows follow the artist, all at once, and similar artists are not asked for", () async {
    final seed = fakeItem('artist', BaseItemKind.musicartist) as ArtistModel;
    final provider = artistDetailsProvider('artist');
    container.listen(provider, (_, __) {});

    final done = container.read(provider.notifier).fetchDetails(seed);
    await settle();
    expect(service.named('itemsGet'), isEmpty);

    service.itemGet().completer.complete(okResponse(seed));
    await settle();

    // Latest tracks, albums, the download check and favourite tracks.
    expect(service.named('itemsGet'), hasLength(4));
    for (final call in service.named('itemsGet')) {
      if (call.arg<bool>('isFavorite') == true) {
        call.completer.complete(queryResult([fakeItem('fav', BaseItemKind.audio)]));
      } else if (call.arg<List<BaseItemKind>>('includeItemTypes')!.contains(BaseItemKind.musicalbum)) {
        call.completer.complete(queryResult([fakeItem('album', BaseItemKind.musicalbum)]));
      } else {
        call.completer.complete(queryResult([fakeItem('t1', BaseItemKind.audio)]));
      }
    }
    await done;

    final artist = container.read(provider)!;
    expect(artist.favoriteTracks.map((e) => e.id), ['fav']);
    expect(artist.albums.map((e) => e.id), ['album']);
    expect(artist.tracks.map((e) => e.id), ['t1']);
    expect(service.named('itemsItemIdSimilarGet'), isEmpty);
  });
}
