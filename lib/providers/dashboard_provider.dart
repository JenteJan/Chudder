import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/episode_model.dart';
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
      ImageType.thumb,
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
      api.showsNextUpGet(
        nextUpDateCutoff: nextUpCutoff,
        fields: fieldsToFetch.toList(),
        enableImageTypes: imagesToFetch,
        imageTypeLimit: 1,
        limit: limit,
        // One episode per show, and the right one: the episode you are
        // part-way through where there is one, the episode after the last you
        // finished where there is not. The combined row is built out of this,
        // and asking for only-unstarted episodes meant a show you were in the
        // middle of arrived from Resume and its follower from here, so the
        // same show stood in the row twice.
        enableResumable: true,
      ),
    ]);

    final nextResponse = results[3] as Response<BaseItemDtoQueryResult>;
    final next = nextResponse.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? [];

    final resumed = [
      ...?(wantsVideo ? results[0] as List<ItemBaseModel>? : null),
      ...?(wantsAudio ? results[1] as List<ItemBaseModel>? : null),
      ...?(wantsBooks ? results[2] as List<ItemBaseModel>? : null),
    ];

    // One state change for the lot, so the screen lays itself out once.
    state = state.copyWith(
      resumeVideo: wantsVideo ? results[0] as List<ItemBaseModel>? : null,
      resumeAudio: wantsAudio ? results[1] as List<ItemBaseModel>? : null,
      resumeBooks: wantsBooks ? results[2] as List<ItemBaseModel>? : null,
      nextUp: next,
      continueWatching: _continueRow(next, resumed),
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

    final resumed = [...video.where(started), ...audio.where(started), ...books.where(started)];
    final next = video.where((item) => !started(item) && !item.userData.played).toList();

    state = state.copyWith(
      activePrograms: [],
      resumeVideo: video.where(started).toList(),
      resumeAudio: audio.where(started).toList(),
      resumeBooks: books.where(started).toList(),
      nextUp: next,
      continueWatching: _continueRow(next, resumed),
      loading: false,
    );
  }

  void clear() {
    state = HomeModel();
  }
}

/// The one row of things to carry on with, newest first: what you are in the
/// middle of and what you would start next, whether or not you finished the
/// last of it.
///
/// The server does the harder half. Asked with `enableResumable`, Next Up
/// answers with one episode per show - the one you are part-way through, or
/// the one after the last you finished - so a show is answered for once and
/// only once. What is left is everything Next Up knows nothing about, films
/// above all, which Resume carries.
List<ItemBaseModel> _continueRow(List<ItemBaseModel> nextUp, List<ItemBaseModel> resume) {
  final shows = nextUp.whereType<EpisodeModel>().map((episode) => episode.parentId).nonNulls.toSet();
  final taken = nextUp.map((item) => item.id).toSet();

  final rest = resume
      .where((item) => !taken.contains(item.id) && !(item is EpisodeModel && shows.contains(item.parentId)))
      .toList();

  final played = {..._playedAt(nextUp), ..._playedAt(rest)};
  return [...nextUp, ...rest]
    ..sort((a, b) => (played[b.id] ?? DateTime(0)).compareTo(played[a.id] ?? DateTime(0)));
}

/// When each item of one server-ordered list was last played, filled in for
/// the ones the server leaves blank.
///
/// Both lists arrive newest first, but a date only comes with an item that has
/// actually been played: the episode after the one you finished has none at
/// all. Each of those takes the date of the first dated item below it and a
/// moment more, which leaves it exactly where the server put it and still lets
/// the other list slot in around it. A list with no dates anywhere keeps its
/// own order and sits under everything that has one.
Map<String, DateTime> _playedAt(List<ItemBaseModel> items) {
  final dates = <String, DateTime>{};
  var below = DateTime.fromMillisecondsSinceEpoch(0);
  for (var index = items.length - 1; index >= 0; index--) {
    final item = items[index];
    below = item.userData.lastPlayed ?? below.add(const Duration(microseconds: 1));
    dates[item.id] = below;
  }
  return dates;
}
