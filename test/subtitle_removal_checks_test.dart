// A subtitle removal is only done once the file is gone: a server that
// answers "removed" and keeps the file is caught, Bazarr's misses fall back
// to Jellyfin for an admin, and network trouble is tried again.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chopper/chopper.dart' as chopper;
import 'package:http/http.dart' as http;

import 'package:chudder/fake/fake_jellyfin_open_api.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/subtitles/bazarr_client.dart';
import 'package:chudder/providers/subtitles/subtitle_file_actions.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/user_provider.dart';

const _path = '/media/movies/Film (2008)/Film (2008).en.srt';

/// A Jellyfin that lists the file until a delete it chooses to honour.
class _Jellyfin extends FakeJellyfinOpenApi {
  _Jellyfin({this.deleteStatuses = const [204], this.honoursDelete = true});

  final List<int> deleteStatuses;
  final bool honoursDelete;
  bool listed = true;
  int deletes = 0;
  int refreshes = 0;

  @override
  Future<chopper.Response<BaseItemDto>> itemsItemIdGet({String? userId, required String? itemId}) async {
    final streams = [
      if (listed) const MediaStream(type: MediaStreamType.subtitle, index: 2, path: _path, isExternal: true),
    ];
    return chopper.Response(
      http.Response('', 200),
      BaseItemDto(
        id: itemId,
        mediaSources: [MediaSourceInfo(mediaStreams: streams)],
      ),
    );
  }

  @override
  Future<chopper.Response> videosItemIdSubtitlesIndexDelete({required String? itemId, required int? index}) async {
    final status = deleteStatuses[deletes.clamp(0, deleteStatuses.length - 1)];
    deletes++;
    if (status < 300 && honoursDelete) listed = false;
    return chopper.Response(http.Response('', status), null);
  }

  @override
  Future<chopper.Response> itemsItemIdRefreshPost({
    required String? itemId,
    ItemsItemIdRefreshPostMetadataRefreshMode? metadataRefreshMode,
    ItemsItemIdRefreshPostImageRefreshMode? imageRefreshMode,
    bool? replaceAllMetadata,
    bool? replaceAllImages,
    bool? regenerateTrickplay,
  }) async {
    refreshes++;
    return chopper.Response(http.Response('', 204), null);
  }
}

class _Service extends JellyService {
  _Service(Ref ref, this.fake) : super(ref, fake);
  final JellyfinOpenApi fake;
  @override
  JellyfinOpenApi get api => fake;
}

class _Api extends JellyApi {
  _Api(this.fake);
  final JellyfinOpenApi fake;
  @override
  JellyService build() => _Service(ref, fake);
}

/// A Bazarr that answers every delete with success, and deletes or not.
class _Bazarr implements BazarrClient {
  _Bazarr({required this.honoursDelete});
  final bool honoursDelete;
  bool listed = true;
  int deletes = 0;
  int blocks = 0;
  int scans = 0;

  @override
  Future<void> deleteSubtitle(BazarrTarget target, BazarrSubtitleFile file) async {
    deletes++;
    if (honoursDelete) listed = false;
  }

  @override
  Future<void> blacklist(BazarrTarget target, BazarrSubtitleFile file, BazarrHistoryEntry entry) async {
    blocks++;
    if (honoursDelete) listed = false;
  }

  @override
  Future<void> scanDisk(BazarrTarget target) async => scans++;

  @override
  Future<BazarrTarget?> reload(BazarrTarget target) async => BazarrMovie(
    radarrId: 1,
    subtitles: [if (listed) const BazarrSubtitleFile(code2: 'en', path: _path)],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User extends User {
  _User(this.admin);
  final bool admin;
  @override
  AccountModel? build() => AccountModel(
    name: 'me',
    id: 'me',
    avatar: '',
    lastUsed: DateTime(2026),
    credentials: CredentialsModel.internal(),
    policy: UserPolicy(isAdministrator: admin, authenticationProviderId: '', passwordResetProviderId: ''),
  );
}

SubtitleRemoval _plan({required bool viaBazarr, required bool admin, bool downloaded = false}) => SubtitleRemoval(
  itemId: 'film',
  index: 2,
  path: _path,
  bazarr: viaBazarr ? const BazarrMovie(radarrId: 1) : null,
  bazarrFile: viaBazarr ? const BazarrSubtitleFile(code2: 'en', path: _path) : null,
  bazarrHistory: downloaded
      ? BazarrHistoryEntry.fromJson({'provider': 'p', 'subs_id': 's1', 'action': 1, 'subtitles_path': _path})
      : null,
  jellyfinCanDelete: admin,
);

/// Runs [future] while letting its pauses pass.
Future<T> _settle<T>(WidgetTester tester, Future<T> future) async {
  T? value;
  Object? error;
  var done = false;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  for (var i = 0; i < 60 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(done, isTrue, reason: 'the removal never finished');
  if (error != null) throw error!;
  return value as T;
}

/// What [future] failed with, once its pauses have passed; null if it did not.
Future<Object?> _failure(WidgetTester tester, Future<Object?> future) async {
  try {
    await _settle(tester, future);
    return null;
  } catch (error) {
    return error;
  }
}

Matcher _removalError(SubtitleRemovalError error) =>
    isA<SubtitleRemovalException>().having((e) => e.error, 'error', error);

void main() {
  ProviderContainer containerFor({required _Jellyfin jellyfin, _Bazarr? bazarr, required bool admin}) {
    final container = ProviderContainer(
      overrides: [
        userProvider.overrideWith(() => _User(admin)),
        jellyApiProvider.overrideWith(() => _Api(jellyfin)),
        bazarrClientProvider.overrideWithValue(bazarr),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('an admin: Jellyfin deletes, and Bazarr is told to look again', (tester) async {
    final jellyfin = _Jellyfin();
    final bazarr = _Bazarr(honoursDelete: true);
    final container = containerFor(jellyfin: jellyfin, bazarr: bazarr, admin: true);
    final relisted = await _settle(
      tester,
      container.read(subtitleFileActionsProvider).remove(_plan(viaBazarr: true, admin: true)),
    );
    expect(relisted, isTrue);
    expect(jellyfin.deletes, 1);
    expect(jellyfin.listed, isFalse);
    expect(bazarr.deletes, 0);
    expect(bazarr.scans, 1);
  });

  testWidgets('blocked: Bazarr blacklists it, and the item is re-listed', (tester) async {
    final jellyfin = _Jellyfin();
    final bazarr = _Bazarr(honoursDelete: true);
    final container = containerFor(jellyfin: jellyfin, bazarr: bazarr, admin: true);
    final relisted = await _settle(
      tester,
      container
          .read(subtitleFileActionsProvider)
          .remove(_plan(viaBazarr: true, admin: true, downloaded: true), block: true),
    );
    expect(relisted, isTrue);
    expect(bazarr.blocks, 1);
    expect(jellyfin.deletes, 0);
    expect(jellyfin.refreshes, 1);
  });

  testWidgets('Bazarr answers "removed" and keeps the file: Jellyfin deletes it for an admin', (tester) async {
    final jellyfin = _Jellyfin();
    final bazarr = _Bazarr(honoursDelete: false);
    final container = containerFor(jellyfin: jellyfin, bazarr: bazarr, admin: true);
    final relisted = await _settle(
      tester,
      container
          .read(subtitleFileActionsProvider)
          .remove(_plan(viaBazarr: true, admin: true, downloaded: true), block: true),
    );
    expect(relisted, isTrue);
    expect(bazarr.blocks, 1);
    expect(jellyfin.deletes, 1);
    expect(jellyfin.listed, isFalse);
  });

  testWidgets('not an admin: Bazarr deletes it', (tester) async {
    final jellyfin = _Jellyfin();
    final bazarr = _Bazarr(honoursDelete: true);
    final container = containerFor(jellyfin: jellyfin, bazarr: bazarr, admin: false);
    final relisted = await _settle(
      tester,
      container.read(subtitleFileActionsProvider).remove(_plan(viaBazarr: true, admin: false)),
    );
    expect(relisted, isFalse);
    expect(bazarr.deletes, 1);
    expect(jellyfin.deletes, 0);
  });

  testWidgets('Bazarr keeps the file and nobody else may delete it: said so', (tester) async {
    final jellyfin = _Jellyfin();
    final container = containerFor(jellyfin: jellyfin, bazarr: _Bazarr(honoursDelete: false), admin: false);
    expect(
      await _failure(tester, container.read(subtitleFileActionsProvider).remove(_plan(viaBazarr: true, admin: false))),
      _removalError(SubtitleRemovalError.kept),
    );
    expect(jellyfin.deletes, 0);
  });

  testWidgets('a server error is tried again', (tester) async {
    final jellyfin = _Jellyfin(deleteStatuses: [503, 204]);
    final container = containerFor(jellyfin: jellyfin, admin: true);
    final relisted = await _settle(
      tester,
      container.read(subtitleFileActionsProvider).remove(_plan(viaBazarr: false, admin: true)),
    );
    expect(relisted, isTrue);
    expect(jellyfin.deletes, 2);
  });

  testWidgets('Jellyfin answers "removed" and still lists the file: said so', (tester) async {
    final jellyfin = _Jellyfin(honoursDelete: false);
    final container = containerFor(jellyfin: jellyfin, admin: true);
    expect(
      await _failure(tester, container.read(subtitleFileActionsProvider).remove(_plan(viaBazarr: false, admin: true))),
      _removalError(SubtitleRemovalError.kept),
    );
  });

  testWidgets('refused is not tried again', (tester) async {
    final jellyfin = _Jellyfin(deleteStatuses: [403]);
    final container = containerFor(jellyfin: jellyfin, admin: true);
    expect(
      await _failure(tester, container.read(subtitleFileActionsProvider).remove(_plan(viaBazarr: false, admin: true))),
      _removalError(SubtitleRemovalError.notAllowed),
    );
    expect(jellyfin.deletes, 1);
  });
}
