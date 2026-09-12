import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/recommended_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_data_updates_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/list_extensions.dart';
import 'package:fladder/util/row_limits.dart';

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

    ref.listen(userDataUpdatesProvider, (previous, next) => _applyUserData(next));
  }

  /// Progress the server has just reported, on the cards that are showing it.
  ///
  /// What belongs in these rows, and in what order, is still worked out by
  /// [fetchNextUpAndResume] - this only keeps what the cards say about the
  /// things already in them from waiting on the next fetch.
  void _applyUserData(UserDataUpdate? update) {
    if (update == null) return;

    // One pass per row, and the same list back when the update says nothing
    // about anything in it. A row is a hundred items now and there are as many
    // rows as libraries, so walking each of them twice - once to ask whether
    // to bother, once to rebuild - is worth not doing on every push.
    List<ItemBaseModel> applied(List<ItemBaseModel> items) {
      List<ItemBaseModel>? changed;
      for (var index = 0; index < items.length; index++) {
        final data = update[items[index].id];
        if (data == null) continue;
        // Mentioned is not the same as changed. The server names every item it
        // touched, and most of the time it is saying what the card already
        // shows - so rewriting it would replace the row for nothing, and a
        // replaced row is a rebuilt card.
        if (items[index].userData == data) continue;
        changed ??= List<ItemBaseModel>.of(items);
        changed[index] = items[index].copyWith(userData: data);
      }
      return changed ?? items;
    }

    final resumeVideo = applied(state.resumeVideo);
    final resumeAudio = applied(state.resumeAudio);
    final resumeBooks = applied(state.resumeBooks);
    final nextUp = applied(state.nextUp);
    final continueWatching = applied(state.continueWatching);

    // Untouched rows come back as the very list that went in, so this is the
    // "nothing here changed" test as well.
    if (identical(resumeVideo, state.resumeVideo) &&
        identical(resumeAudio, state.resumeAudio) &&
        identical(resumeBooks, state.resumeBooks) &&
        identical(nextUp, state.nextUp) &&
        identical(continueWatching, state.continueWatching)) {
      return;
    }

    state = state.copyWith(
      resumeVideo: resumeVideo,
      resumeAudio: resumeAudio,
      resumeBooks: resumeBooks,
      nextUp: nextUp,
      continueWatching: continueWatching,
    );
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
    final limit = kRowItemLimit;

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

  /// Rows to browse once there is nothing left to carry on with: a row per
  /// genre, and what the server makes of what has been played.
  ///
  /// Kept apart from [fetchNextUpAndResume] and not awaited by it - these are
  /// the slowest things on the page and the least urgent, so Continue and Next
  /// up are not held up waiting for them. Fetched once per session: genres are
  /// asked for `sortBy: random`, and a page whose lower half deals itself a new
  /// hand every two minutes is not one you can browse. See [_browseLoaded].
  Future<void> fetchBrowseRows({bool force = false}) async {
    if (!force && _browseLoaded) return;
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) return;

    final views = ref.read(viewsProvider.select((value) => value.dashboardViews));
    final movieViews = views.where((view) => view.collectionType == CollectionType.movies).toList();
    final genreViews = views
        .where((view) => view.collectionType == CollectionType.movies || view.collectionType == CollectionType.tvshows)
        .toList();
    if (genreViews.isEmpty && movieViews.isEmpty) return;

    _browseLoaded = true;
    final results = await Future.wait([
      _fetchGenreRows(genreViews),
      _fetchSuggestionRows(movieViews),
    ]);

    if (!mounted) return;
    final genres = results[0];
    final suggestions = results[1];
    // Only when there is something new to say.
    //
    // This runs after the page is already up, so its answer lands while
    // somebody is looking at - and possibly using - the screen. Assigning
    // regardless rebuilt every row, and a rebuilt row throws its cards away:
    // the card holding the selection went with them, which is how coming back
    // from a film lost track of what was selected. Nothing new, nothing moves.
    if (_sameRows(genres, state.genres) && _sameRows(suggestions, state.suggestions)) return;
    state = state.copyWith(
      genres: genres,
      suggestions: suggestions,
    );
  }

  /// Whether the browse rows have been filled in once already.
  bool _browseLoaded = false;

  /// Whether two sets of rows hold the same things in the same order.
  static bool _sameRows(List<RecommendedModel> a, List<RecommendedModel> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      final one = a[index];
      final other = b[index];
      if (one.posters.length != other.posters.length) return false;
      for (var poster = 0; poster < one.posters.length; poster++) {
        if (one.posters[poster].id != other.posters[poster].id) return false;
      }
    }
    return true;
  }

  /// A row per genre, over every library that has them.
  ///
  /// The genre list itself is unlimited - a library can answer with forty - so
  /// the rows are capped, and the item requests go out a few at a time: forty at
  /// once starve the rows above these of the connections they need. The same
  /// shape [LibraryScreen] uses.
  Future<List<RecommendedModel>> _fetchGenreRows(List<ViewModel> views) async {
    if (views.isEmpty) return [];
    final rows = <RecommendedModel>[];

    for (final view in views) {
      try {
        final response = await api.genresGet(
          sortBy: [ItemSortBy.sortname],
          sortOrder: [SortOrder.ascending],
          includeItemTypes:
              view.collectionType == CollectionType.movies ? [BaseItemKind.movie] : [BaseItemKind.series],
          parentId: view.id,
        );
        // The endpoint takes no limit of its own, so the cap is applied to what
        // it answers with.
        final genres = (response.body?.items ?? []).take(_dashboardGenreRows).toList();
        if (genres.isEmpty) continue;

        final requests = genres.map((genre) async {
          final items = await api.itemsGet(
            parentId: view.id,
            genreIds: [genre.id ?? ""],
            limit: kCategoryRowItemLimit,
            recursive: true,
            includeItemTypes: view.collectionType.itemKinds.expand((e) => e.dtoKind).toList(),
            enableImageTypes: [ImageType.primary],
            fields: [
              ItemFields.primaryimageaspectratio,
              ItemFields.overview,
            ],
            sortBy: [ItemSortBy.random],
            enableTotalRecordCount: false,
            imageTypeLimit: 1,
          );
          final posters = items.body?.items ?? [];
          if (posters.isEmpty) return null;
          return RecommendedModel(name: Other(genre.name ?? ""), posters: posters);
        }).toList();

        for (var index = 0; index < requests.length; index += 6) {
          final batch = await Future.wait(requests.sublist(index, (index + 6).clamp(0, requests.length)));
          rows.addAll(batch.whereType<RecommendedModel>());
        }
      } catch (_) {
        // One library failing is a row missing, not an empty dashboard.
      }
    }

    return rows;
  }

  /// What the server suggests from what has been played. Films only - that is
  /// all `moviesRecommendationsGet` answers for - and only the categories that
  /// came back with anything in them.
  Future<List<RecommendedModel>> _fetchSuggestionRows(List<ViewModel> views) async {
    if (views.isEmpty) return [];
    final rows = <RecommendedModel>[];

    for (final view in views) {
      try {
        final response = await api.moviesRecommendationsGet(
          parentId: view.id,
          categoryLimit: 4,
          itemLimit: kCategoryRowItemLimit,
          fields: [
            ItemFields.overview,
            ItemFields.primaryimageaspectratio,
          ],
        );
        rows.addAll(
          (response.body ?? [])
              .map((entry) => RecommendedModel.fromBaseDto(entry, ref))
              .where((row) => row.posters.isNotEmpty),
        );
      } catch (_) {
        // As above: a missing row beats a broken page.
      }
    }

    return rows;
  }

  void clear() {
    state = HomeModel();
    _browseLoaded = false;
  }
}

/// How many genres of one library get a row on the dashboard.
///
/// The libraries page shows every one it finds, because that is the page you
/// went to in order to browse. The dashboard carries these under everything
/// else and for more than one library at a time, so it takes the first few
/// rather than forty each.
const _dashboardGenreRows = 6;

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
