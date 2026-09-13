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
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/library_filter_model.dart';
import 'package:chudder/models/library_search/library_search_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/models/views_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/library_search_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/user_data_updates_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/util/map_bool_helper.dart';

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

ViewModel _view(String id, CollectionType type) => ViewModel(
      name: id,
      id: id,
      serverId: 'server',
      dateCreated: DateTime(2020),
      canDelete: false,
      canDownload: false,
      parentId: '',
      collectionType: type,
      playAccess: PlayAccess.full,
      recentlyAdded: const [],
      imageData: null,
      childCount: 0,
      path: null,
    );

BaseItemDto _dto(String id, CollectionType type) =>
    BaseItemDto(id: id, name: id, serverId: 'server', collectionType: type);

void main() {
  final movies = _view('movies', CollectionType.movies);
  final shows = _view('shows', CollectionType.tvshows);

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

  test('libraries the app already holds open the page without asking the server first', () async {
    final t = setUp(known: [movies, shows]);
    final run = t.notifier.initRefresh(parentIds: ['movies'], filters: CollectionType.movies.defaultFilters);
    // The first page is asked for while the server's list is still out.
    await pumpEventQueue();
    expect(t.api.called('itemsGet'), 1);
    t.api.filterLists.complete();
    t.api.libraries.complete();
    await run;

    final state = t.container.read(librarySearchProvider(const Key('movies')));
    expect(state.views.included.map((view) => view.id), ['movies']);
    expect(state.views.keys.map((view) => view.id), ['movies', 'shows']);
    expect(t.refreshes, isEmpty);
  });

  test('a library only the server lists is added once its list arrives', () async {
    final t = setUp(
      known: [movies],
      server: [_dto('movies', CollectionType.movies), _dto('trailers', CollectionType.trailers)],
    );
    final run = t.notifier.initRefresh(parentIds: ['movies'], filters: CollectionType.movies.defaultFilters);
    t.api.filterLists.complete();
    if (!t.api.libraries.isCompleted) t.api.libraries.complete();
    await run;

    final state = t.container.read(librarySearchProvider(const Key('movies')));
    expect(state.views.keys.map((view) => view.id), ['movies', 'trailers']);
    expect(state.views.included.map((view) => view.id), ['movies']);
  });

  test('a library the app remembers but the server no longer lists is dropped', () async {
    final t = setUp(known: [movies, shows], server: [_dto('movies', CollectionType.movies)]);
    final run = t.notifier.initRefresh(parentIds: ['movies'], filters: CollectionType.movies.defaultFilters);
    t.api.filterLists.complete();
    t.api.libraries.complete();
    await run;

    final state = t.container.read(librarySearchProvider(const Key('movies')));
    expect(state.views.keys.map((view) => view.id), ['movies']);
  });

  test('a page the app knows nothing about asks the server for its libraries first', () async {
    final t = setUp();
    final run = t.notifier.initRefresh(parentIds: ['movies'], filters: CollectionType.movies.defaultFilters);
    await pumpEventQueue();
    expect(t.api.called('itemsGet'), 0);
    t.api.filterLists.complete();
    t.api.libraries.complete();
    await run;
    expect(t.api.calls.first.name, 'usersUserIdViewsGet');
    expect(t.api.called('itemsGet'), 1);
  });

  test('a genre link does not wait for the filter lists before its posters', () async {
    final t = setUp(known: [movies, shows]);
    final run = t.notifier.initRefresh(
      parentIds: ['movies'],
      filters: const LibraryFilterModel(recursive: true, genres: {'Drama': true}),
    );
    await pumpEventQueue();
    expect(t.api.called('itemsGet'), 1, reason: 'the first page is not held back by the filter lists');
    final page = t.api.calls.firstWhere((call) => call.name == 'itemsGet');
    expect(page.args[#genres], ['Drama']);

    t.api.filterLists.complete();
    if (!t.api.libraries.isCompleted) t.api.libraries.complete();
    await run;
    expect(t.refreshes, isEmpty);
  });

  test('a studio link still waits for the studio list that holds its pick', () async {
    final t = setUp(known: [movies, shows]);
    final run = t.notifier.initRefresh(
      parentIds: ['movies'],
      filters: LibraryFilterModel(recursive: true, studios: {Studio(id: 's', name: 'Studio'): true}),
    );
    await pumpEventQueue();
    expect(t.api.called('itemsGet'), 0);
    t.api.filterLists.complete();
    if (!t.api.libraries.isCompleted) t.api.libraries.complete();
    await run;
    expect(t.api.called('itemsGet'), 1);
  });
}
