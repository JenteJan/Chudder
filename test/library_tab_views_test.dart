// The Library tab: the list of libraries the app fetched at start opens the
// tab, and picking another library asks for that library's rows only. A pull
// on the library already shown still asks for everything again.

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/models/views_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/library_screen_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/views_provider.dart';

class _FakeJellyService implements JellyService {
  final calls = <(String, Map<Symbol, dynamic>)>[];

  int called(String name) => calls.where((call) => call.$1 == name).length;

  Response<T> _ok<T>(T body) => Response<T>(http.Response('', 200), body);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll('Symbol("', '').replaceAll('")', '');
    calls.add((name, invocation.namedArguments));
    const empty = BaseItemDtoQueryResult(items: []);
    switch (name) {
      case 'usersUserIdViewsGet':
        return Future.value(_ok(const BaseItemDtoQueryResult(items: [
          BaseItemDto(id: 'movies', name: 'Movies', serverId: 's', collectionType: CollectionType.movies),
          BaseItemDto(id: 'shows', name: 'Shows', serverId: 's', collectionType: CollectionType.tvshows),
        ])));
      case 'usersUserIdItemsLatestGet':
        return Future.value(_ok(const <BaseItemDto>[]));
      case 'usersUserIdItemsResumeGet':
      case 'showsNextUpGet':
      case 'usersUserIdItemsGet':
      case 'genresGet':
        return Future.value(_ok(empty));
      case 'moviesRecommendationsGet':
        return Future.value(_ok(const <RecommendationDto>[]));
      case 'itemsGet':
        return Future.value(_ok(ServerQueryResult(items: const <ItemBaseModel>[])));
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

class _Online extends ConnectivityStatus {
  @override
  ConnectionState build() => ConnectionState.wifi;
}

class _KnownViews extends ViewsNotifier {
  _KnownViews(super.ref, List<ViewModel> views) {
    state = ViewsModel(views: views);
  }
}

ViewModel _view(String id, CollectionType type) => ViewModel(
      name: id,
      id: id,
      serverId: 's',
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

void main() {
  final movies = _view('movies', CollectionType.movies);
  final shows = _view('shows', CollectionType.tvshows);

  (ProviderContainer, _FakeJellyService) setUp(List<ViewModel> known) {
    final api = _FakeJellyService();
    final container = ProviderContainer(overrides: [
      jellyApiProvider.overrideWith(() => _FakeJellyApi(api)),
      connectivityStatusProvider.overrideWith(() => _Online()),
      viewsProvider.overrideWith((ref) => _KnownViews(ref, known)),
    ]);
    addTearDown(container.dispose);
    return (container, api);
  }

  test('the first open uses the libraries the app already has', () async {
    final (container, api) = setUp([movies, shows]);
    await container.read(libraryScreenProvider.notifier).fetchAllLibraries(reuseKnownViews: true);

    expect(api.called('usersUserIdViewsGet'), 0);
    expect(api.called('usersUserIdItemsLatestGet'), 0);
    expect(api.called('usersUserIdItemsResumeGet'), 1);
    final state = container.read(libraryScreenProvider);
    expect(state.views.map((view) => view.id), ['movies', 'shows']);
    expect(state.selectedViewModel?.id, 'movies');
  });

  test('with nothing fetched yet the first open asks the server', () async {
    final (container, api) = setUp(const []);
    await container.read(libraryScreenProvider.notifier).fetchAllLibraries(reuseKnownViews: true);

    expect(api.called('usersUserIdViewsGet'), 1);
    expect(container.read(libraryScreenProvider).views.map((view) => view.id), ['movies', 'shows']);
  });

  test('picking another library asks for its rows, not for the libraries again', () async {
    final (container, api) = setUp([movies, shows]);
    final notifier = container.read(libraryScreenProvider.notifier);
    await notifier.fetchAllLibraries(reuseKnownViews: true);
    api.calls.clear();

    await notifier.selectLibrary(shows);
    await notifier.fetchAllLibraries();

    expect(api.called('usersUserIdViewsGet'), 0);
    expect(api.called('usersUserIdItemsLatestGet'), 0);
    expect(api.calls.firstWhere((call) => call.$1 == 'usersUserIdItemsResumeGet').$2[#parentId], 'shows');
  });

  test('a pull on the library shown asks for everything again', () async {
    final (container, api) = setUp([movies, shows]);
    final notifier = container.read(libraryScreenProvider.notifier);
    await notifier.fetchAllLibraries(reuseKnownViews: true);
    api.calls.clear();

    await notifier.fetchAllLibraries();

    expect(api.called('usersUserIdViewsGet'), 1);
    expect(api.called('usersUserIdItemsResumeGet'), 1);
  });
}
