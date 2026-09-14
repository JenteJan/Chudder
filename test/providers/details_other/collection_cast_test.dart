import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/providers/items/collection_details_provider.dart';

import 'fake_jelly_service.dart';

void main() {
  late FakeJellyService service;
  late ProviderContainer container;

  setUp(() {
    service = FakeJellyService();
    container = fakeContainer(service);
  });

  tearDown(() => container.dispose());

  test('a collection\'s entries come without their cast, which fills in from its own request', () async {
    final provider = collectionDetailsProvider('boxset');
    container.listen(provider, (_, __) {});

    final done = container.read(provider.notifier).fetch(null);
    await settle();

    final queries = service.named('itemsGet').toList();
    expect(queries, hasLength(2));
    final children = queries.firstWhere((call) => !call.arg<List<ItemFields>>('fields')!.contains(ItemFields.people));
    final cast = queries.firstWhere((call) => call.arg<List<ItemFields>>('fields')!.contains(ItemFields.people));
    expect(children.arg<List<ItemFields>>('fields'), contains(ItemFields.providerids));
    // The similar row does not wait for the entries either.
    expect(service.named('itemsItemIdSimilarGet'), hasLength(1));

    ItemBaseModel withCast(String id, List<String> people) => fakeItem(id, BaseItemKind.movie).copyWith(
          overview: OverviewModel(people: [for (final person in people) Person(id: person, name: person)]),
        );

    service.itemGet().completer.complete(okResponse(fakeItem('boxset', BaseItemKind.boxset)));
    children.completer.complete(queryResult([fakeItem('a', BaseItemKind.movie), fakeItem('b', BaseItemKind.movie)]));
    await settle();
    expect(container.read(provider).children.map((e) => e.id), ['a', 'b']);
    expect(container.read(provider).loading, isFalse);
    expect(container.read(provider).recurringCast, isEmpty);

    cast.completer.complete(queryResult([
      withCast('a', ['star', 'one-off']),
      withCast('b', ['star']),
    ]));
    service
        .named('itemsItemIdSimilarGet')
        .first
        .completer
        .complete(okResponse(const BaseItemDtoQueryResult(items: [])));
    await settle();
    // Empty for the boxset, so the newest entry is asked instead.
    final fallback = service.named('itemsItemIdSimilarGet').last;
    expect(fallback.arg<String>('itemId'), 'b');
    fallback.completer.complete(okResponse(const BaseItemDtoQueryResult(items: [])));
    await done;

    final details = container.read(provider);
    expect(details.recurringCast.map((e) => e.id), ['star']);
    expect(details.children.first.overview.people.map((e) => e.id), ['star', 'one-off']);
    // Still the same kind of item, for the page they open.
    expect(details.children.first.type, FladderItemType.movie);
  });
}
