// How many requests opening a film or a show costs: the page joins what
// opening it already asked for.

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chudder/fake/fake_jellyfin_open_api.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/items/item_prefetch_provider.dart';
import 'package:chudder/providers/items/movies_details_provider.dart';
import 'package:chudder/providers/items/series_details_provider.dart';
import 'package:chudder/providers/items/series_next_up_provider.dart';
import 'package:chudder/providers/related_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/user_data_updates_provider.dart';

const _latency = Duration(milliseconds: 30);

Response<T> _ok<T>(T body) => Response<T>(http.Response('', 200), body);

class _Server extends JellyService {
  _Server(Ref ref) : super(ref, FakeJellyfinOpenApi());

  final List<String> requests = [];

  @override
  Future<Response<ItemBaseModel>> usersUserIdItemsItemIdGet({String? itemId}) async {
    requests.add('item $itemId');
    await Future<void>.delayed(_latency);
    final dto = switch (itemId) {
      'movie' => const BaseItemDto(id: 'movie', name: 'A film', type: BaseItemKind.movie),
      'show' => const BaseItemDto(id: 'show', name: 'A show', type: BaseItemKind.series),
      _ => BaseItemDto(id: itemId, name: 'An episode', type: BaseItemKind.episode, seriesId: 'show'),
    };
    return _ok(ItemBaseModel.fromBaseDto(dto, ref));
  }

  @override
  Future<Response<List<BaseItemDto>>> itemsItemIdSpecialFeaturesGet({required String itemId}) async {
    requests.add('special $itemId');
    await Future<void>.delayed(_latency);
    return _ok(const <BaseItemDto>[]);
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
  }) async {
    requests.add('nextup $seriesId');
    await Future<void>.delayed(_latency);
    return _ok(const BaseItemDtoQueryResult(items: [
      BaseItemDto(
        id: 'e2',
        name: 'Two',
        type: BaseItemKind.episode,
        seriesId: 'show',
        parentIndexNumber: 1,
        indexNumber: 2,
      ),
    ]));
  }

  @override
  Future<Response<BaseItemDtoQueryResult>> showsSeriesIdEpisodesGet({
    required String? seriesId,
    List<ItemFields>? fields,
    int? season,
    String? seasonId,
    bool? isMissing,
    String? adjacentTo,
    String? startItemId,
    int? startIndex,
    int? limit,
    bool? enableImages,
    int? imageTypeLimit,
    List<ImageType>? enableImageTypes,
    bool? enableUserData,
    ShowsSeriesIdEpisodesGetSortBy? sortBy,
  }) async {
    requests.add('episodes $seriesId');
    await Future<void>.delayed(_latency);
    return _ok(BaseItemDtoQueryResult(items: [
      for (final index in [1, 2, 3])
        BaseItemDto(
          id: 'e$index',
          name: 'Episode $index',
          type: BaseItemKind.episode,
          seriesId: 'show',
          parentIndexNumber: 1,
          indexNumber: index,
        ),
    ]));
  }

  @override
  Future<Response<BaseItemDtoQueryResult>> showsSeriesIdSeasonsGet({
    required String? seriesId,
    bool? enableUserData,
    bool? isMissing,
    List<ItemFields>? fields,
  }) async {
    requests.add('seasons $seriesId');
    await Future<void>.delayed(_latency);
    return _ok(const BaseItemDtoQueryResult(items: [
      BaseItemDto(id: 's1', name: 'Season 1', type: BaseItemKind.season, seriesId: 'show', indexNumber: 1),
    ]));
  }
}

class _Api extends JellyApi {
  _Api(this.server);
  final _Server Function(Ref ref) server;
  @override
  JellyService build() => server(ref);
}

class _Related extends RelatedNotifier {
  _Related(Ref ref) : super(ref: ref);

  @override
  Future<Response<List<ItemBaseModel>>> relatedContent(String itemId) async {
    await Future<void>.delayed(_latency);
    return _ok(const <ItemBaseModel>[]);
  }
}

class _NoUpdates extends StateNotifier<UserDataUpdate?> implements UserDataUpdatesNotifier {
  _NoUpdates(this.ref) : super(null);
  @override
  final Ref ref;
}

MovieModel _moviePoster() => MovieModel(
      name: 'A film',
      id: 'movie',
      originalTitle: '',
      premiereDate: DateTime(2000),
      sortName: '',
      status: '',
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: false,
      canDelete: false,
    );

void main() {
  late _Server server;
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: [
      jellyApiProvider.overrideWith(() => _Api((ref) => server = _Server(ref))),
      relatedUtilityProvider.overrideWith(_Related.new),
      userDataUpdatesProvider.overrideWith(_NoUpdates.new),
    ]);
    // Held open, as the page would: the api provider is autoDispose.
    container.listen(jellyApiProvider, (_, __) {});
  });

  tearDown(() => container.dispose());

  test('a film opened from its card asks for itself once', () async {
    final poster = _moviePoster();
    final subscription = container.listen(movieDetailsProvider('movie'), (_, __) {});
    container.read(itemPrefetchProvider).prefetch(poster);

    await container.read(movieDetailsProvider('movie').notifier).fetchDetails(poster);

    expect(server.requests.where((request) => request == 'item movie'), hasLength(1));
    expect(container.read(movieDetailsProvider('movie'))?.name, 'A film');
    subscription.close();
  });

  test('a show opened from its card asks for itself once', () async {
    final subscription = container.listen(seriesDetailsProvider('show'), (_, __) {});
    container.read(seriesNextUpProvider).prefetch('show');

    await container.read(seriesDetailsProvider('show').notifier).fetchDetails('show');

    expect(server.requests.where((request) => request == 'item show'), hasLength(1));
    expect(container.read(seriesDetailsProvider('show'))?.availableEpisodes, hasLength(3));
    subscription.close();
  });
}
