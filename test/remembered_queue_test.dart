import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/remembered_queue_provider.dart';
import 'package:chudder/providers/shared_provider.dart';

const _films = LanguageScope(id: 'films', name: 'Films', kind: LanguageScopeKind.collection);
const _other = LanguageScope(id: 'other', name: 'Other', kind: LanguageScopeKind.collection);

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a film played from its collection page is found in that queue again', () async {
    final queues = (await _container()).read(rememberedQueuesProvider);
    queues.remember(_films, ['a', 'b', 'c']);

    final found = queues.containing('b');
    expect(found?.scope.id, 'films');
    expect(found?.itemIds, ['a', 'b', 'c']);
    expect(queues.containing('x'), isNull);
  });

  test('the collection played last wins, and a collection keeps one queue', () async {
    final queues = (await _container()).read(rememberedQueuesProvider);
    queues.remember(_films, ['a', 'b']);
    queues.remember(_other, ['b', 'z']);
    expect(queues.containing('b')?.scope.id, 'other');

    queues.remember(_films, ['b', 'a']);
    expect(queues.containing('b')?.itemIds, ['b', 'a']);
    expect(queues.containing('z')?.scope.id, 'other');
  });

  test('only collections, and only real queues, are kept', () async {
    final queues = (await _container()).read(rememberedQueuesProvider);
    queues.remember(const LanguageScope(id: 'p', name: 'P', kind: LanguageScopeKind.playlist), ['a', 'b']);
    queues.remember(_films, ['a']);
    expect(queues.containing('a'), isNull);
  });

  test('kept across a restart', () async {
    (await _container()).read(rememberedQueuesProvider).remember(_films, ['a', 'b']);
    expect((await _container()).read(rememberedQueuesProvider).containing('a')?.scope.name, 'Films');
  });
}
