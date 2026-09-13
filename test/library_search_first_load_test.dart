// The library page's first load: one first page, not two, and no round trips
// ahead of it for things the page already knows or does not need yet.
//
// The notifier against a fake JellyService that records every call, with the
// screen's refresh listener stood in by the same `shouldRefresh` check.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/collection_types.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/library_search/library_search_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/models/views_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/library_search_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/user_data_updates_provider.dart';
import 'package:chudder/providers/views_provider.dart';

class _Call {
  _Call(this.name, this.args);
  final String name;
  final Map<Symbol, dynamic> args;
  bool get countsTotal => args[#enableTotalRecordCount] == true;
}

class _FakeJellyService implements JellyService {
  _FakeJellyService(this.serverViews);

  final List<BaseItemDto> serverViews;
  final calls = <_Call>[];

  /// Held open until completed, for the filter lists.
  final filterLists = Completer<void>();

  /// Held open until completed, for the server's list of libraries.
  final libraries = Completer<void>();

  int called(String name) => calls.where((call) => call.name == name).length;

  Response<T> _ok<T>(T body) => Response<T>(http.Response('', 200), body);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll('Symbol("', '').replaceAll('")', '');
    calls.add(_Call(name, invocation.namedArguments));
    switch (name) {
      case 'usersUserIdViewsGet':
        return libraries.future
            .then((_) => _ok(BaseItemDtoQueryResult(items: serverViews, totalRecordCount: serverViews.length)));
      case 'itemsGet':
        return Future<Response<ServerQueryResult>>.value(
            _ok(ServerQueryResult(items: const <ItemBaseModel>[], totalRecordCount: 0)));
      case 'itemsFilters2Get':
        return filterLists.future.then((_) => _ok(const QueryFilters()));
      case 'studiosGet':
      case 'genresGet':
      case 'yearsGet':
        return filterLists.future.then((_) => _ok(const BaseItemDtoQueryResult(items: [])));
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeJellyApi extends JellyApi {
  _FakeJellyApi(this.service);
  final JellyService service;
  @override
  JellyService build() => service;
}

class _NoUserDataUpdates extends StateNotifier<UserDataUpdate?> implements UserDataUpdatesNotifier {
  _NoUserDataUpdates() : super(null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KnownViews extends ViewsNotifier {
  _KnownViews(super.ref, List<ViewModel> views) {
    state = ViewsModel(views: views);
  }
}

BaseItemDto _dto(String id, CollectionType type) =>
    BaseItemDto(id: id, name: id, serverId: 'server', collectionType: type);

void main() {
  ({ProviderContainer container, _FakeJellyService api, LibrarySearchNotifier notifier, List<String> refreshes}) setUp(
      {List<ViewModel> known = const [], List<BaseItemDto>? server}) {
    final api =
        _FakeJellyService(server ?? [_dto('movies', CollectionType.movies), _dto('shows', CollectionType.tvshows)]);
    final container = ProviderContainer(overrides: [
      jellyApiProvider.overrideWith(() => _FakeJellyApi(api)),
      offlineStateProvider.overrideWithValue(false),
      userDataUpdatesProvider.overrideWith((ref) => _NoUserDataUpdates()),
      viewsProvider.overrideWith((ref) => _KnownViews(ref, known)),
    ]);
    addTearDown(container.dispose);
    const key = Key('movies');
    final refreshes = <String>[];
    // What the screen does with every change: refresh when this says so.
    container.listen<LibrarySearchModel>(librarySearchProvider(key), (previous, next) {
      if (previous?.shouldRefresh(next) == true) refreshes.add('refresh');
    }, fireImmediately: false);
    final notifier = container.read(librarySearchProvider(key).notifier);
    return (container: container, api: api, notifier: notifier, refreshes: refreshes);
  }

  test('the first load asks for its first page once, and nothing asks for it again', () async {
    final t = setUp();
    final run = t.notifier.initRefresh(parentIds: ['movies'], filters: CollectionType.movies.defaultFilters);
    t.api.filterLists.complete();
    if (!t.api.libraries.isCompleted) t.api.libraries.complete();
    await run;

    expect(t.api.calls.where((call) => call.name == 'itemsGet' && call.countsTotal), hasLength(1));
    expect(t.refreshes, isEmpty, reason: 'setting up its own libraries and filters is not a change to refresh for');
  });

  test('a filter changed once the page is up still refreshes it', () async {
    final t = setUp();
    final run = t.notifier.initRefresh(parentIds: ['movies'], filters: CollectionType.movies.defaultFilters);
    t.api.filterLists.complete();
    if (!t.api.libraries.isCompleted) t.api.libraries.complete();
    await run;

    t.notifier.setNameStartsWith('B');
    expect(t.refreshes, hasLength(1));
  });
}
