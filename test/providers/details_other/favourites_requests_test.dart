import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/models/views_model.dart';
import 'package:chudder/providers/favourites_provider.dart';
import 'package:chudder/providers/views_provider.dart';

import 'fake_jelly_service.dart';

void main() {
  late FakeJellyService service;
  late ProviderContainer container;

  setUp(() {
    service = FakeJellyService();
    container = fakeContainer(service);
  });

  tearDown(() => container.dispose());

  group('favourites', () {
    ViewModel view(String id) => ViewModel(
          name: id,
          id: id,
          serverId: '',
          dateCreated: DateTime(2020),
          canDelete: false,
          canDownload: false,
          parentId: '',
          collectionType: CollectionType.movies,
          playAccess: PlayAccess.full,
          recentlyAdded: const [],
          imageData: null,
          childCount: 0,
          path: null,
        );

    ProviderContainer favouritesContainer(List<ViewModel> views) => fakeContainer(service, [
          viewsProvider.overrideWith((ref) => ViewsNotifier(ref)..state = ViewsModel(dashboardViews: views)),
        ]);

    test('one request per library, plus collections and people, all at once', () async {
      final scoped = favouritesContainer([view('v1'), view('v2')]);
      addTearDown(scoped.dispose);

      final done = scoped.read(favouritesProvider.notifier).fetchFavourites();
      await settle();

      expect(service.named('itemsGet'), hasLength(3));
      expect(service.named('personsGet'), hasLength(1));

      for (final call in service.named('itemsGet')) {
        if (call.arg<String>('parentId') == 'v1') {
          call.completer.complete(queryResult([
            fakeItem('s', BaseItemKind.series, name: 'A show'),
            fakeItem('m', BaseItemKind.movie, name: 'B film'),
          ]));
        } else {
          call.completer.complete(queryResult([]));
        }
      }
      service.named('personsGet').first.completer.complete(okResponse<List<ItemBaseModel>>([]));
      await done;

      final favourites = scoped.read(favouritesProvider).favourites;
      // Rows in the order the per-kind requests used to give them.
      expect(favourites.keys, [FladderItemType.movie, FladderItemType.series]);
    });

    test('a library with more favourites than one request holds is asked kind by kind', () async {
      final scoped = favouritesContainer([view('v1')]);
      addTearDown(scoped.dispose);

      final done = scoped.read(favouritesProvider.notifier).fetchFavourites();
      await settle();

      final combined = service.query(where: (call) => call.arg<String>('parentId') == 'v1');
      expect(combined.arg<int>('limit'), 135);
      service.query(kind: BaseItemKind.boxset).completer.complete(queryResult([]));
      service.named('personsGet').first.completer.complete(okResponse<List<ItemBaseModel>>([]));
      combined.completer.complete(queryResult([fakeItem('m', BaseItemKind.movie)], total: 500));
      await settle();

      final perKind = service
          .named('itemsGet')
          .where((call) => call.arg<int>('limit') == 15 && call.arg<String>('parentId') == 'v1');
      expect(perKind, hasLength(9));
      for (final call in perKind) {
        call.completer.complete(queryResult([]));
      }
      await done;
    });

    test('grouping keeps each kind in server order, fifteen at most, kinds in page order', () {
      final items = [
        for (var i = 0; i < 20; i++) fakeItem('a$i', BaseItemKind.audio),
        fakeItem('m1', BaseItemKind.movie),
        fakeItem('e1', BaseItemKind.episode),
        fakeItem('m2', BaseItemKind.movie),
      ];
      final grouped = FavouritesNotifier.groupFavouritesByKind(items);
      expect(grouped.take(3).map((e) => e.id), ['m1', 'm2', 'e1']);
      expect(grouped.skip(3).map((e) => e.id), [for (var i = 0; i < 15; i++) 'a$i']);
    });
  });
}
