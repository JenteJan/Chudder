import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/list_extensions.dart';

final dashboardProvider = StateNotifierProvider<DashboardNotifier, HomeModel>((ref) {
  return DashboardNotifier(ref);
});

class DashboardNotifier extends StateNotifier<HomeModel> {
  DashboardNotifier(this.ref) : super(HomeModel()) {
    // Every row here comes from a server query, so the whole screen has to be
    // rebuilt when the server comes or goes. Without this, going offline left
    // a dashboard full of posters that cannot be opened - the state was
    // fetched while online and nothing re-ran once the screen was no longer
    // the one being looked at.
    ref.listen(connectivityStatusProvider, (previous, next) {
      if (previous == next) return;
      state = state.copyWith(loading: false);
      fetchNextUpAndResume();
    });
  }

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<void> fetchNextUpAndResume() async {
    if (state.loading) return;
    state = state.copyWith(loading: true);

    // Every request below needs the server, and each one fails on its own
    // timeout offline, leaving a dashboard of empty rows and a spinner. Build
    // the same rows out of what is downloaded instead.
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) {
      await _fetchOfflineDashboard();
      return;
    }

    final viewTypes =
        ref.read(viewsProvider.select((value) => value.dashboardViews)).map((e) => e.collectionType).toSet().toList();
    final limit = 16;

    final imagesToFetch = {
      ImageType.logo,
      ImageType.primary,
      ImageType.backdrop,
      ImageType.banner,
    }.toList();

    final fieldsToFetch = {
      ItemFields.parentid,
      ItemFields.mediastreams,
      ItemFields.mediasources,
      ItemFields.candelete,
      ItemFields.candownload,
      ItemFields.primaryimageaspectratio,
      ItemFields.overview,
      ItemFields.airtime,
      // So a show or film opened from one of these cards already knows its own
      // genres. They belong to the item, and without asking for them here the
      // genre row is the one part of the header still waiting on a request
      // after everything around it has arrived. Episode cards carry none —
      // genres live on the show — which costs nothing.
      ItemFields.genres,
    };

    if (viewTypes.containsAny([CollectionType.livetv])) {
      List<ChannelModel> channels = (await api.liveTvChannelsGet(limit: limit))
              .body
              ?.items
              ?.map((e) => ChannelModel.fromBaseDto(e, ref))
              .toList() ??
          [];

      channels = await Future.wait(
        channels.map(
          (e) async {
            final programs = await ref.read(liveTvProvider.notifier).fetchProgramsForChannel(e);
            return e.copyChannelWith(
              programs: programs,
            );
          },
        ),
      );

      state = state.copyWith(activePrograms: channels);
    } else {
      state = state.copyWith(activePrograms: []);
    }

    // One request per kind of thing that can be resumed, plus next up. They
    // are independent, so they go out together and the dashboard is ready
    // when the slowest returns rather than when the sum of them has.
    Future<List<ItemBaseModel>?> resume(MediaType mediaType) async {
      final response = await api.usersUserIdItemsResumeGet(
        enableImageTypes: imagesToFetch,
        fields: fieldsToFetch.toList(),
        mediaTypes: [mediaType],
        enableTotalRecordCount: false,
        limit: limit,
      );
      return response.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
    }

    final wantsVideo = viewTypes.containsAny([CollectionType.movies, CollectionType.tvshows]);
    final wantsAudio = viewTypes.contains(CollectionType.music);
    final wantsBooks = viewTypes.contains(CollectionType.books);

    final nextUpCutoff = DateTime.now().subtract(
        ref.read(clientSettingsProvider.select((value) => value.nextUpDateCutoff ?? const Duration(days: 28))));

    final results = await Future.wait<Object?>([
      wantsVideo ? resume(MediaType.video) : Future.value(null),
      wantsAudio ? resume(MediaType.audio) : Future.value(null),
      wantsBooks ? resume(MediaType.book) : Future.value(null),
      api.showsNextUpGet(nextUpDateCutoff: nextUpCutoff, fields: fieldsToFetch.toList()),
    ]);

    final nextResponse = results[3] as Response<BaseItemDtoQueryResult>;
    final next = nextResponse.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? [];

    // One state change for the lot, so the screen lays itself out once.
    state = state.copyWith(
      resumeVideo: wantsVideo ? results[0] as List<ItemBaseModel>? : null,
      resumeAudio: wantsAudio ? results[1] as List<ItemBaseModel>? : null,
      resumeBooks: wantsBooks ? results[2] as List<ItemBaseModel>? : null,
      nextUp: next,
      loading: false,
    );
  }

  /// The dashboard as the download folder sees it: partly-watched downloads
  /// under Continue watching, the rest as what to start next. Nothing here
  /// touches the network, so it is also what the screen shows on a cold start
  /// with no server.
  Future<void> _fetchOfflineDashboard() async {
    final downloaded = await ref.read(syncProvider.notifier).allDownloadedItems();

    bool started(ItemBaseModel item) => item.userData.progress > 0 && !item.userData.played;

    final video = downloaded.where((item) => item is! AudioModel && item is! BookModel).toList();
    final audio = downloaded.whereType<AudioModel>().cast<ItemBaseModel>().toList();
    final books = downloaded.whereType<BookModel>().cast<ItemBaseModel>().toList();

    state = state.copyWith(
      activePrograms: [],
      resumeVideo: video.where(started).toList(),
      resumeAudio: audio.where(started).toList(),
      resumeBooks: books.where(started).toList(),
      nextUp: video.where((item) => !started(item) && !item.userData.played).toList(),
      loading: false,
    );
  }

  void clear() {
    state = HomeModel();
  }
}
