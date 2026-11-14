import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/item_membership_provider.dart';

import 'details_other/fake_jelly_service.dart';

/// Which collections hold a film is looked up as its page opens. It used to be
/// a request per collection all at once, each answered in full, landing as
/// the page's poster settled.
void main() {
  late FakeJellyService service;
  late ProviderContainer container;
  late DateTime now;
  late MembershipCache cache;

  setUp(() {
    service = FakeJellyService();
    now = DateTime(2026, 11, 13, 12);
    container = fakeContainer(service, [
      membershipCacheProvider.overrideWith((ref) => MembershipCache(ref, now: () => now)),
    ]);
    cache = container.read(membershipCacheProvider);
  });

  tearDown(() => container.dispose());

  Iterable<FakeCall> children() => service.named('usersUserIdItemsGet').where((call) => call.arg<String>('parentId') != null);

  /// Answers the two listings with [boxSets] collections and no playlists.
  Future<void> answerListings(int boxSets) async {
    await settle();
    final listings = service.named('usersUserIdItemsGet').where((call) => call.arg<String>('parentId') == null).toList();
    for (final listing in listings) {
      if (listing.completer.isCompleted) continue;
      final kinds = listing.arg<List<BaseItemKind>>('includeItemTypes') ?? const [];
      listing.completer.complete(okResponse(BaseItemDtoQueryResult(items: [
        if (kinds.contains(BaseItemKind.boxset))
          for (var i = 0; i < boxSets; i++) BaseItemDto(id: 'set$i', name: 'Set $i', type: BaseItemKind.boxset),
      ])));
    }
    await settle();
  }

  Future<void> answerChildren() async {
    while (true) {
      final open = children().where((call) => !call.completer.isCompleted).toList();
      if (open.isEmpty) return;
      for (final call in open) {
        final id = call.arg<String>('parentId')!;
        call.completer.complete(okResponse(BaseItemDtoQueryResult(items: [
          if (id == 'set3') const BaseItemDto(id: 'film'),
        ])));
      }
      await settle();
      await settle();
    }
  }

  test('asks a few collections at a time, for their ids only', () async {
    final answer = cache.collectionsOf('film');
    await answerListings(20);

    expect(children(), hasLength(6));
    for (final call in children()) {
      expect(call.arg<bool>('enableImages'), isFalse);
      expect(call.arg<bool>('enableUserData'), isFalse);
      expect(call.arg<List<ItemFields>>('fields'), isEmpty);
    }
    await answerChildren();
    expect(children(), hasLength(20));
    expect((await answer).map((collection) => collection.id), ['set3']);
  });

  test('a page opened once the answer is old gets it at once, and the refresh happens behind it', () async {
    final first = cache.collectionsOf('film');
    await answerListings(4);
    await answerChildren();
    await first;
    final asked = service.calls.length;

    now = now.add(MembershipCache.maxAge + const Duration(minutes: 1));
    // Answered without anything coming back from the server.
    expect((await cache.collectionsOf('film')).map((collection) => collection.id), ['set3']);
    expect(service.calls.length, greaterThan(asked), reason: 'the refresh went out');
  });

  test('a change forgets the answer, and the next page waits for a new one', () async {
    final first = cache.collectionsOf('film');
    await answerListings(4);
    await answerChildren();
    await first;

    cache.invalidate();
    expect(cache.knownCollectionsOf('film'), isNull);
    var answered = false;
    final next = cache.collectionsOf('film').then((value) {
      answered = true;
      return value;
    });
    await settle();
    expect(answered, isFalse);
    await answerListings(4);
    await answerChildren();
    expect((await next).map((collection) => collection.id), ['set3']);
  });
}
