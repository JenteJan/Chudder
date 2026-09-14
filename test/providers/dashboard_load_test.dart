import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/dashboard_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/user_data_updates_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/views_provider.dart';

/// Every request the home dashboard sends, in the order it went out, each held
/// until the test answers it.
class _FakeService extends JellyService {
  _FakeService(Ref ref) : super(ref, JellyfinOpenApi.create());

  final sent = <String>[];
  final _pending = <String, List<Completer<Object?>>>{};

  Future<T> _hold<T>(String name) {
    sent.add(name);
    final completer = Completer<Object?>();
    _pending.putIfAbsent(name, () => []).add(completer);
    return completer.future.then((value) => value as T);
  }

  /// Answers the oldest unanswered request called [name].
  void answer(String name, Object? value) {
    final waiting = _pending[name];
    if (waiting == null || waiting.isEmpty) throw StateError('nothing waiting for $name (sent: $sent)');
    waiting.removeAt(0).complete(value);
  }

  void answerAll(String name, Object? value) {
    while (_pending[name]?.isNotEmpty == true) {
      answer(name, value);
    }
  }

  int count(String name) => sent.where((request) => request == name).length;

  static Response<T> ok<T>(T body) => Response<T>(http.Response('', 200), body);

  @override
  Future<Response<UserDto>> usersMeGet() => _hold('me');

  @override
  Future<Response<bool>> quickConnectEnabled() async => ok(false);

  @override
  Future<Response<ServerConfiguration>> systemConfigurationGet() async => ok(const ServerConfiguration());

  @override
  Future<Response<UserSettings>> getCustomConfig() async => ok(UserSettings());

  @override
  Future<Response<BaseItemDtoQueryResult>> usersUserIdViewsGet({
    bool? includeExternalContent,
    List<CollectionType>? presetViews,
    bool? includeHidden,
  }) =>
      _hold('views');

  @override
  Future<Response<List<BaseItemDto>>> usersUserIdItemsLatestGet({
    String? parentId,
    List<ItemFields>? fields,
    List<BaseItemKind>? includeItemTypes,
    bool? isPlayed,
    bool? enableImages,
    int? imageTypeLimit,
    List<ImageType>? enableImageTypes,
    bool? enableUserData,
    int? limit,
    bool? groupItems,
  }) {
    latestFields.add(fields ?? const []);
    return _hold('latest');
  }

  final latestFields = <List<ItemFields>>[];
  final resumeFields = <List<ItemFields>>[];

  @override
  Future<Response<BaseItemDtoQueryResult>> usersUserIdItemsResumeGet({
    int? startIndex,
    int? limit,
    String? searchTerm,
    String? parentId,
    List<ItemFields>? fields,
    List<MediaType>? mediaTypes,
    bool? enableUserData,
    bool? enableTotalRecordCount,
    List<ImageType>? enableImageTypes,
    List<BaseItemKind>? excludeItemTypes,
    List<BaseItemKind>? includeItemTypes,
  }) {
    resumeFields.add(fields ?? const []);
    return _hold('resume-${mediaTypes!.single.value}');
  }

  @override
  Future<Response<BaseItemDtoQueryResult>> showsNextUpGet({
    int? startIndex,
    int? limit,
    String? parentId,
    String? seriesId,
    DateTime? nextUpDateCutoff,
    List<ItemFields>? fields,
    bool? enableUserData,
    List<ImageType>? enableImageTypes,
    int? imageTypeLimit,
    bool enableResumable = false,
  }) =>
      _hold('nextup');

  @override
  Future<Response<BaseItemDtoQueryResult>> genresGet({
    String? parentId,
    List<ItemSortBy>? sortBy,
    List<SortOrder>? sortOrder,
    List<BaseItemKind>? includeItemTypes,
  }) =>
      _hold('genres');

  @override
  Future<Response<List<RecommendationDto>>> moviesRecommendationsGet({
    String? parentId,
    List<ItemFields>? fields,
    int? categoryLimit,
    int? itemLimit,
  }) =>
      _hold('recommendations');
}

class _FakeJellyApi extends JellyApi {
  _FakeJellyApi(this.onBuild);

  final void Function(_FakeService service) onBuild;

  @override
  JellyService build() {
    final service = _FakeService(ref);
    onBuild(service);
    return service;
  }
}

class _SignedIn extends User {
  @override
  AccountModel? build() => AccountModel(
        name: 'someone',
        id: 'user',
        avatar: '',
        lastUsed: DateTime(2026),
        credentials: CredentialsModel.internal(),
      );
}

class _Connectivity extends ConnectivityStatus {
  @override
  ConnectionState build() => ConnectionState.mobile;

  void set(ConnectionState next) => state = next;
}

class _NoUserDataUpdates extends UserDataUpdatesNotifier {
  _NoUserDataUpdates(super.ref);
}

final _emptyItems = _FakeService.ok(const BaseItemDtoQueryResult(items: []));

Response<BaseItemDtoQueryResult> _libraries(List<(String, CollectionType)> libraries) => _FakeService.ok(
      BaseItemDtoQueryResult(
        items: [
          for (final (id, type) in libraries) BaseItemDto(id: id, name: id, collectionType: type),
        ],
      ),
    );

void main() {
  late ProviderContainer container;
  late _FakeService api;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      jellyApiProvider.overrideWith(() => _FakeJellyApi((service) => api = service)),
      userProvider.overrideWith(_SignedIn.new),
      connectivityStatusProvider.overrideWith(_Connectivity.new),
      userDataUpdatesProvider.overrideWith(_NoUserDataUpdates.new),
    ]);
    container.read(jellyApiProvider);
  });

  tearDown(() => container.dispose());

  /// What the dashboard does when it loads.
  Future<void> refresh() => container.read(dashboardProvider.notifier).refresh();

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('Continue and Next up go out with the library list, not behind the account and every Latest row', () async {
    final done = refresh();
    await settle();

    expect(api.sent, containsAll(['me', 'views', 'nextup', 'resume-Video', 'resume-Audio', 'resume-Book']));
    expect(api.count('latest'), 0);
    expect(api.count('genres') + api.count('recommendations'), 0);

    api.answer('views', _libraries([('films', CollectionType.movies)]));
    await settle();
    // Latest goes out as soon as the libraries are known; the rows under it
    // wait for the account, which carries the order of the libraries.
    expect(api.count('latest'), 1);
    expect(api.count('recommendations'), 0);

    api.answer('me', _FakeService.ok(const UserDto(id: 'user', name: 'someone')));
    await settle();
    expect(api.count('genres'), 1);
    expect(api.count('recommendations'), 1);

    api.answer('latest', _FakeService.ok(<BaseItemDto>[]));
    for (final name in ['resume-Video', 'resume-Audio', 'resume-Book', 'nextup']) {
      api.answer(name, _emptyItems);
    }
    await done;

    expect(container.read(viewsProvider).dashboardViews.map((view) => view.id), ['films']);
    // One of each and no more.
    expect(api.count('views'), 1);
    expect(api.count('nextup'), 1);
    expect(api.count('resume-Video'), 1);
  });

  test('the home shell and the dashboard asking for the first load get one load between them', () async {
    final fromShell = refresh();
    await settle();
    final fromDashboard = refresh();
    await settle();
    expect(api.count('me'), 1);
    expect(api.count('views'), 1);
    expect(api.count('nextup'), 1);

    api.answer('views', _libraries([('films', CollectionType.movies)]));
    api.answer('me', _FakeService.ok(const UserDto(id: 'user')));
    await settle();
    api.answerAll('latest', _FakeService.ok(<BaseItemDto>[]));
    for (final name in ['resume-Video', 'resume-Audio', 'resume-Book', 'nextup']) {
      api.answer(name, _emptyItems);
    }
    await Future.wait([fromShell, fromDashboard]);
  });

  test('rows of MediaStreams are not asked for twice', () async {
    final done = refresh();
    await settle();
    api.answer('views', _libraries([('films', CollectionType.movies)]));
    api.answer('me', _FakeService.ok(const UserDto(id: 'user')));
    await settle();
    api.answerAll('latest', _FakeService.ok(<BaseItemDto>[]));
    for (final name in ['resume-Video', 'resume-Audio', 'resume-Book', 'nextup']) {
      api.answer(name, _emptyItems);
    }
    await done;

    for (final fields in [...api.latestFields, ...api.resumeFields]) {
      expect(fields, contains(ItemFields.mediasources));
      expect(fields, isNot(contains(ItemFields.mediastreams)));
    }
  });

  test('the first probe moving mobile to ethernet does not start a fetch of its own', () async {
    container.read(dashboardProvider.notifier);
    (container.read(connectivityStatusProvider.notifier) as _Connectivity).set(ConnectionState.ethernet);
    await settle();
    (container.read(connectivityStatusProvider.notifier) as _Connectivity).set(ConnectionState.wifi);
    await settle();
    expect(api.sent, isEmpty);
  });

  test('a caller that arrives while a fetch is under way shares it instead of being turned away', () async {
    final dashboard = container.read(dashboardProvider.notifier);
    final first = dashboard.fetchNextUpAndResume();
    final second = dashboard.fetchNextUpAndResume();
    await settle();
    expect(api.count('nextup'), 1);

    for (final name in ['resume-Video', 'resume-Audio', 'resume-Book', 'nextup']) {
      api.answer(name, _emptyItems);
    }
    await Future.wait([first, second]);

    // And once it is done, the next one really fetches.
    unawaited(dashboard.fetchNextUpAndResume());
    await settle();
    expect(api.count('nextup'), 2);
  });

  test('a kind of row the libraries do not have is dropped, not written', () async {
    final done = refresh();
    await settle();
    api.answer('views', _libraries([('shows', CollectionType.tvshows)]));
    api.answer('me', _FakeService.ok(const UserDto(id: 'user')));
    await settle();
    api.answerAll('latest', _FakeService.ok(<BaseItemDto>[]));
    api.answerAll('genres', _emptyItems);
    api.answer('resume-Video', _emptyItems);
    api.answer('nextup', _emptyItems);
    // Audio was asked for before the libraries were known; its failure is not
    // this dashboard's problem any more.
    api._pending['resume-Audio']!.removeAt(0).completeError(StateError('no music here'));
    api.answer('resume-Book', _emptyItems);
    await done;
  });

  test('coming back online before the libraries are known fetches the rows again once they are', () async {
    // One service for the whole test, as in the app: this one goes on over
    // several turns of the event loop, and nothing else holds on to it.
    container.listen(jellyApiProvider, (_, __) {});
    // A cold start offline: no libraries known, and nothing remembered.
    final connectivity = container.read(connectivityStatusProvider.notifier) as _Connectivity;
    connectivity.set(ConnectionState.offline);
    final dashboard = container.read(dashboardProvider.notifier);

    connectivity.set(ConnectionState.wifi);
    await settle();
    expect(api.count('nextup'), 1);
    expect(api.count('views'), 0);

    // The dashboard's own refresh a moment later shares the fetch under way.
    final done = dashboard.refresh();
    await settle();
    expect(api.count('nextup'), 1);

    final film = _FakeService.ok(const BaseItemDtoQueryResult(items: [
      BaseItemDto(id: 'film', name: 'film', type: BaseItemKind.movie),
    ]));
    for (final name in ['resume-Video', 'resume-Audio', 'resume-Book']) {
      api.answer(name, name == 'resume-Video' ? film : _emptyItems);
    }
    api.answer('nextup', _emptyItems);
    await settle();
    // Written for no libraries at all, so without the film.
    expect(container.read(dashboardProvider).continueWatching, isEmpty);

    api.answer('views', _libraries([('films', CollectionType.movies)]));
    api.answer('me', _FakeService.ok(const UserDto(id: 'user')));
    await settle();
    api.answerAll('latest', _FakeService.ok(<BaseItemDto>[]));
    await settle();

    // The libraries call for a Resume row, so the rows go out again.
    expect(api.count('nextup'), 2);
    expect(api.count('resume-Video'), 2);
    api.answer('resume-Video', film);
    api.answer('nextup', _emptyItems);
    await done;
    await settle();

    final home = container.read(dashboardProvider);
    expect(home.resumeVideo.map((item) => item.id), ['film']);
    expect(home.continueWatching.map((item) => item.id), ['film']);
  });

  test('rows are not fetched again when the libraries they were built for are written', () async {
    final done = refresh();
    await settle();
    api.answer('views', _libraries([('films', CollectionType.movies)]));
    api.answer('me', _FakeService.ok(const UserDto(id: 'user')));
    await settle();
    api.answerAll('latest', _FakeService.ok(<BaseItemDto>[]));
    for (final name in ['resume-Video', 'resume-Audio', 'resume-Book', 'nextup']) {
      api.answer(name, _emptyItems);
    }
    await done;
    await settle();
    expect(api.count('nextup'), 1);
  });

  test('a failure of a row that is shown still fails the fetch, and the next fetch still runs', () async {
    final dashboard = container.read(dashboardProvider.notifier);
    final fetch = dashboard.fetchNextUpAndResume();
    await settle();
    api._pending['nextup']!.removeAt(0).completeError(StateError('server gone'));
    for (final name in ['resume-Video', 'resume-Audio', 'resume-Book']) {
      api.answer(name, _emptyItems);
    }
    await expectLater(fetch, throwsStateError);

    unawaited(dashboard.fetchNextUpAndResume());
    await settle();
    expect(api.count('nextup'), 2);
  });

  group('the libraries of last time', () {
    const key = 'dashboardLibraries..user';
    final noAccount = Response<UserDto>(http.Response('', 500), null);

    test('are remembered once the list is back', () async {
      final done = refresh();
      await settle();
      api.answer('views', _libraries([('films', CollectionType.movies), ('shows', CollectionType.tvshows)]));
      api.answer('me', noAccount);
      await settle();
      api.answerAll('latest', _FakeService.ok(<BaseItemDto>[]));
      for (final name in ['resume-Video', 'resume-Audio', 'resume-Book', 'nextup']) {
        api.answer(name, _emptyItems);
      }
      await done;
      expect(preferences.getString(key), '[{"id":"films","type":"movies"},{"id":"shows","type":"tvshows"}]');
    });

    test('have their rows asked for before the list comes back, and only once', () async {
      await preferences.setString(key, '[{"id":"films","type":"movies"}]');
      final done = refresh();
      await settle();

      expect(api.count('views'), 1);
      expect(api.count('latest'), 1);
      expect(api.count('genres'), 1);
      expect(api.count('recommendations'), 1);
      // Known to have no music and no books, so those are not asked for.
      expect(api.count('resume-Video'), 1);
      expect(api.count('resume-Audio'), 0);
      expect(api.count('resume-Book'), 0);

      api.answer('views', _libraries([('films', CollectionType.movies)]));
      api.answer('me', noAccount);
      await settle();
      expect(api.count('latest'), 1);
      expect(api.count('genres'), 1);
      expect(api.count('recommendations'), 1);

      api.answer('latest', _FakeService.ok(<BaseItemDto>[]));
      api.answer('resume-Video', _emptyItems);
      api.answer('nextup', _emptyItems);
      await done;
      expect(container.read(viewsProvider).dashboardViews.map((view) => view.id), ['films']);
    });

    test('that are no longer there are asked about again for what there is now', () async {
      await preferences.setString(key, '[{"id":"films","type":"movies"}]');
      final done = refresh();
      await settle();

      api.answer('views', _libraries([('shows', CollectionType.tvshows), ('books', CollectionType.books)]));
      api.answer('me', noAccount);
      await settle();
      // The shows and the books have their Latest rows asked for now; the
      // films' is left unanswered and unused.
      expect(api.count('latest'), 3);
      expect(api.count('genres'), 2);
      expect(api.count('recommendations'), 1);
      expect(api.count('resume-Book'), 1);

      api.answerAll('latest', _FakeService.ok(<BaseItemDto>[]));
      api.answer('resume-Video', _emptyItems);
      api.answer('resume-Book', _emptyItems);
      api.answer('nextup', _emptyItems);
      await done;
      expect(container.read(viewsProvider).dashboardViews.map((view) => view.id), ['shows', 'books']);
      expect(preferences.getString(key), '[{"id":"shows","type":"tvshows"},{"id":"books","type":"books"}]');
    });
  });
}
