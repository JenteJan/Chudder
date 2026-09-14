import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/collection_types.dart';
import 'package:chudder/models/home_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/book_model.dart';
import 'package:chudder/models/items/channel_model.dart';
import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/recommended_model.dart';
import 'package:chudder/models/settings/home_settings_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/providers/live_tv_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/user_data_updates_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/util/continue_row.dart';
import 'package:chudder/util/list_extensions.dart';
import 'package:chudder/util/row_limits.dart';

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
    //
    // Only crossing into or out of offline counts. The state starts out as
    // mobile and the first probe moves it to wifi or ethernet on nearly every
    // launch, which used to start a fetch before the libraries were known: a
    // Continue row of next-up episodes only, and - since a fetch under way
    // turned every other caller away - often the one the dashboard asked for
    // itself thrown out with it. Which kind of network carries the server
    // says nothing about what is on it.
    ref.listen(connectivityStatusProvider, (previous, next) {
      if ((previous == ConnectionState.offline) == (next == ConnectionState.offline)) return;
      // What is under way was asked for on the other side of the change; its
      // answer is no longer wanted, and nobody should have to wait for it.
      _generation++;
      _inFlight = null;
      fetchNextUpAndResume();
    });

    // The rows were built for the libraries known when they were fetched, and
    // those can be none at all: coming back online after starting offline,
    // the fetch above goes out at once, before anything has asked for the
    // libraries again, and a refresh that asks for them meanwhile shares that
    // fetch. While the dashboard waited for the libraries before asking for
    // any rows this could not happen. So the rows are fetched again once the
    // libraries turn out to call for other kinds of rows than the ones they
    // were built for: a film you are part-way through does not stay away
    // behind next-up episodes until the next pull.
    ref.listen(viewsProvider.select((views) => views.dashboardViews), (previous, next) {
      final builtFor = _rowsBuiltFor;
      // Offline rows, or a fetch that has not looked at the libraries yet and
      // will see these when it does.
      if (builtFor == null || builtFor == _rowKindsOf(next.map((view) => view.collectionType))) return;
      _generation++;
      _inFlight = null;
      fetchNextUpAndResume();
    });

    ref.listen(userDataUpdatesProvider, (previous, next) => _applyUserData(next));
  }

  /// Which kinds of rows the last fetch from the server asked for, once it knew
  /// the libraries; null while offline or while a fetch has not got that far.
  _RowKinds? _rowsBuiltFor;

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

  /// The refresh under way, if there is one; see [refresh].
  Future<void>? _refreshing;

  /// Everything on the dashboard, at once. Whoever asks while a refresh is
  /// under way shares it - the home shell starts the first one a frame before
  /// the dashboard is there to ask.
  ///
  /// All at once. This used to be a queue - the account, then the libraries
  /// and every library's Latest row, then Continue and Next up, then the
  /// browse rows - and the top of the page came last, four round trips in,
  /// although none of it needs the rows before it. What does depend on
  /// something (which libraries there are, their order) waits for just that
  /// inside the providers, not for everything ahead of it here.
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) return running;
    final run = _refresh();
    _refreshing = run;
    run.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_refreshing, run)) _refreshing = null;
    });
    return run;
  }

  Future<void> _refresh() async {
    // The first two are guarded individually. Both need the server, and
    // offline the first one throws - which used to take the dashboard's own
    // fetch with it, so the screen never even tried to build itself out of
    // what is downloaded and simply stayed empty. Neither is required for the
    // rows.
    final information = _ignoreFailure(ref.read(userProvider.notifier).updateInformation());
    final views = _ignoreFailure(ref.read(viewsProvider.notifier).fetchViews());
    final rows = fetchNextUpAndResume();
    // Not awaited. The genre and suggestion rows are the slowest thing on the
    // page and sit under everything else, so the refresh is done without them
    // and they arrive when they arrive.
    fetchBrowseRows().ignore();
    await information;
    await views;
    await rows;
  }

  static Future<void> _ignoreFailure(Future<Object?> request) async {
    try {
      await request;
    } catch (_) {}
  }

  /// Moved on whenever what is under way stops being wanted - the app went
  /// offline or came back. An answer to an older one is dropped.
  int _generation = 0;

  /// The fetch under way, if there is one. Everyone who asks meanwhile gets
  /// that one. It used to be a `loading` flag that turned them away instead,
  /// and stayed set for good when a request failed.
  Future<void>? _inFlight;

  Future<void> fetchNextUpAndResume() {
    final running = _inFlight;
    if (running != null) return running;
    final run = _fetchNextUpAndResume(_generation);
    _inFlight = run;
    run.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    return run;
  }

  Future<void> _fetchNextUpAndResume(int generation) async {
    bool current() => mounted && generation == _generation;
    _rowsBuiltFor = null;

    // Every request below needs the server, and each one fails on its own
    // timeout offline, leaving a dashboard of empty rows and a spinner. Build
    // the same rows out of what is downloaded instead.
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) {
      await _fetchOfflineDashboard(current);
      return;
    }

    // Which libraries there are decides what to ask for, but nothing here
    // needs their rows, and on a first load the list itself is still on its
    // way. So the requests go out now, alongside it, and the list is only
    // waited for before the answer is written.
    final viewsNotifier = ref.read(viewsProvider.notifier);
    // The libraries of last time when none are known yet this session.
    final knownTypes = (viewsNotifier.likelyDashboardLibraries ?? const <LibraryKey>[]).map((e) => e.type).toSet();
    final libraries = viewsNotifier.dashboardViewList();
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
      // No MediaStreams: the cards build their streams from MediaSources, which
      // carry them too, and asking for both sent every stream twice - a third
      // of a Latest row's bytes.
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

    // One request per kind of thing that can be resumed, plus next up. They
    // are independent, so they go out together and the dashboard is ready
    // when the slowest returns rather than when the sum of them has.
    Future<_Settled<List<ItemBaseModel>?>> resume(MediaType mediaType) => _Settled.of(() async {
          final response = await api.usersUserIdItemsResumeGet(
            enableImageTypes: imagesToFetch,
            fields: fieldsToFetch.toList(),
            mediaTypes: [mediaType],
            enableTotalRecordCount: false,
            limit: limit,
          );
          return response.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
        }());

    bool wantsVideoOf(Set<CollectionType> types) =>
        types.contains(CollectionType.movies) || types.contains(CollectionType.tvshows);
    bool wantsAudioOf(Set<CollectionType> types) => types.contains(CollectionType.music);
    bool wantsBooksOf(Set<CollectionType> types) => types.contains(CollectionType.books);

    // With nothing known yet every kind is asked for, and a kind the libraries
    // turn out not to want is left out of what is written below - an empty
    // answer costs less than a round trip of waiting. Known libraries that
    // rule a kind out are trusted, and it is asked for later if they changed.
    final nothingKnown = knownTypes.isEmpty;
    var videoRequest = nothingKnown || wantsVideoOf(knownTypes) ? resume(MediaType.video) : null;
    var audioRequest = nothingKnown || wantsAudioOf(knownTypes) ? resume(MediaType.audio) : null;
    var booksRequest = nothingKnown || wantsBooksOf(knownTypes) ? resume(MediaType.book) : null;

    final nextUpCutoff = DateTime.now().subtract(
        ref.read(clientSettingsProvider.select((value) => value.nextUpDateCutoff ?? const Duration(days: 28))));

    final nextUpRequest = _Settled.of(api.showsNextUpGet(
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
    ));

    final viewTypes = (await libraries).map((e) => e.collectionType).toSet();
    if (!current()) return;
    _rowsBuiltFor = _rowKindsOf(viewTypes);

    final wantsVideo = wantsVideoOf(viewTypes);
    final wantsAudio = wantsAudioOf(viewTypes);
    final wantsBooks = wantsBooksOf(viewTypes);
    if (wantsVideo) videoRequest ??= resume(MediaType.video);
    if (wantsAudio) audioRequest ??= resume(MediaType.audio);
    if (wantsBooks) booksRequest ??= resume(MediaType.book);

    // Alongside the rest rather than ahead of it: a channel list and a request
    // per channel used to be waited for before Resume and Next up even went
    // out.
    final channelsRequest = viewTypes.contains(CollectionType.livetv)
        ? _Settled.of(() async {
            final channels = (await api.liveTvChannelsGet(limit: limit))
                    .body
                    ?.items
                    ?.map((e) => ChannelModel.fromBaseDto(e, ref))
                    .toList() ??
                [];
            return Future.wait(
              channels.map(
                (e) async {
                  final programs = await ref.read(liveTvProvider.notifier).fetchProgramsForChannel(e);
                  return e.copyChannelWith(
                    programs: programs,
                  );
                },
              ),
            );
          }())
        : null;

    final videoResult = await videoRequest;
    final audioResult = await audioRequest;
    final booksResult = await booksRequest;
    final nextUpResult = await nextUpRequest;
    final channelsResult = await channelsRequest;
    if (!current()) return;

    // A failure of anything that is shown fails the fetch, as it always has;
    // an answer nobody wants any more is dropped whatever it was.
    final channels = channelsResult?.value ?? <ChannelModel>[];
    // Empty rather than left out: left out, copyWith kept whatever was there,
    // such as the downloads shown while offline.
    final resumeVideo = (wantsVideo ? videoResult?.value : null) ?? const <ItemBaseModel>[];
    final resumeAudio = (wantsAudio ? audioResult?.value : null) ?? const <ItemBaseModel>[];
    final resumeBooks = (wantsBooks ? booksResult?.value : null) ?? const <ItemBaseModel>[];
    final next = nextUpResult.value.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? [];

    final resumed = [
      ...resumeVideo,
      ...resumeAudio,
      ...resumeBooks,
    ];

    // One state change for the lot, so the screen lays itself out once.
    state = state.copyWith(
      activePrograms: channels,
      resumeVideo: resumeVideo,
      resumeAudio: resumeAudio,
      resumeBooks: resumeBooks,
      nextUp: next,
      continueWatching: combineContinueRow(next, resumed),
    );
  }

  /// The dashboard as the download folder sees it: partly-watched downloads
  /// under Continue watching, the rest as what to start next. Nothing here
  /// touches the network, so it is also what the screen shows on a cold start
  /// with no server.
  Future<void> _fetchOfflineDashboard(bool Function() current) async {
    final downloaded = await ref.read(syncProvider.notifier).allDownloadedItems();
    if (!current()) return;

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
      continueWatching: combineContinueRow(next, resumed),
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

    _browseLoaded = true;
    // Only which libraries there are matters here, not their rows. The ones
    // there probably are go first - the libraries of last time - so these
    // requests, the slowest on the page, do not wait for the list either; and
    // if the list says otherwise they are asked for again for what it says.
    final viewsNotifier = ref.read(viewsProvider.notifier);
    final libraries = viewsNotifier.dashboardViewList();
    final likely = viewsNotifier.likelyDashboardLibraries;
    var asked = likely != null && _browsable(likely).isNotEmpty ? _browsable(likely) : null;
    var rows = asked != null ? _fetchBrowse(asked) : null;

    final actual = _browsable((await libraries).map((view) => view.libraryKey));
    if (!mounted) return;
    if (asked == null || !_sameLibraries(asked, actual)) {
      if (actual.isEmpty) {
        _browseLoaded = false;
        return;
      }
      asked = actual;
      rows = _fetchBrowse(actual);
    }

    final (genres, suggestions) = await rows!;
    if (!mounted) return;
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

  /// The libraries the browse rows are drawn from, in order: films and shows.
  static List<LibraryKey> _browsable(Iterable<LibraryKey> libraries) => libraries
      .where((library) => library.type == CollectionType.movies || library.type == CollectionType.tvshows)
      .toList();

  static bool _sameLibraries(List<LibraryKey> a, List<LibraryKey> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  Future<(List<RecommendedModel>, List<RecommendedModel>)> _fetchBrowse(List<LibraryKey> libraries) async {
    final results = await Future.wait([
      _fetchGenreRows(libraries),
      _fetchSuggestionRows(libraries.where((library) => library.type == CollectionType.movies).toList()),
    ]);
    return (results[0], results[1]);
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
  ///
  /// Two libraries at a time, in the libraries' order. One after another, a
  /// films-and-shows account waited four round trips for the last of these,
  /// and they are the last thing the page waits for.
  Future<List<RecommendedModel>> _fetchGenreRows(List<LibraryKey> views) async {
    if (views.isEmpty) return [];
    final perLibrary = await views.mapConcurrent(_genreLibrariesAtOnce, _fetchGenreRowsOf);
    return perLibrary.expand((rows) => rows).toList();
  }

  Future<List<RecommendedModel>> _fetchGenreRowsOf(LibraryKey view) async {
    final rows = <RecommendedModel>[];
    try {
      final response = await api.genresGet(
        sortBy: [ItemSortBy.sortname],
        sortOrder: [SortOrder.ascending],
        includeItemTypes: view.type == CollectionType.movies ? [BaseItemKind.movie] : [BaseItemKind.series],
        parentId: view.id,
      );
      // The endpoint takes no limit of its own, so the cap is applied to what
      // it answers with.
      final genres = (response.body?.items ?? []).take(_dashboardGenreRows).toList();
      if (genres.isEmpty) return rows;

      final requests = genres.map((genre) async {
        final items = await api.itemsGet(
          parentId: view.id,
          genreIds: [genre.id ?? ""],
          limit: kCategoryRowItemLimit,
          recursive: true,
          includeItemTypes: view.type.itemKinds.expand((e) => e.dtoKind).toList(),
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
    return rows;
  }

  /// What the server suggests from what has been played. Films only - that is
  /// all `moviesRecommendationsGet` answers for - and only the categories that
  /// came back with anything in them.
  Future<List<RecommendedModel>> _fetchSuggestionRows(List<LibraryKey> views) async {
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

  /// Fills in the banner's own items, for the sources the dashboard does not
  /// fetch anyway. Random is dealt once per session, like the genre rows: a
  /// banner that picks new films on every refresh is one you never finish
  /// reading.
  Future<void> fetchBannerItems(HomeCarouselSettings source, {bool force = false}) async {
    if (source != HomeCarouselSettings.random && source != HomeCarouselSettings.favourites) return;
    if (!force && state.bannerSource == source && state.bannerItems.isNotEmpty) return;
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) return;
    try {
      final response = await api.itemsGet(
        recursive: true,
        includeItemTypes: const [BaseItemKind.movie, BaseItemKind.series],
        isFavorite: source == HomeCarouselSettings.favourites ? true : null,
        sortBy: source == HomeCarouselSettings.random ? const [ItemSortBy.random] : const [ItemSortBy.datecreated],
        sortOrder: const [SortOrder.descending],
        limit: _bannerItemLimit,
        enableImageTypes: const [ImageType.primary, ImageType.backdrop, ImageType.thumb, ImageType.logo],
        fields: const [
          ItemFields.overview,
          ItemFields.genres,
          ItemFields.primaryimageaspectratio,
          ItemFields.mediasources,
        ],
        enableTotalRecordCount: false,
      );
      if (!mounted) return;
      state = state.copyWith(bannerItems: response.body?.items ?? const [], bannerSource: source);
    } catch (_) {
      // An empty banner is not shown; the rows under it are the page.
    }
  }

  void clear() {
    // Whatever is under way belongs to the account that is leaving.
    _generation++;
    _inFlight = null;
    _refreshing = null;
    _rowsBuiltFor = null;
    state = HomeModel();
    _browseLoaded = false;
  }
}

/// How many items the banner rotates through when it fetches its own.
const _bannerItemLimit = 20;

/// How many genres of one library get a row on the dashboard.
///
/// The libraries page shows every one it finds, because that is the page you
/// went to in order to browse. The dashboard carries these under everything
/// else and for more than one library at a time, so it takes the first few
/// rather than forty each.
const _dashboardGenreRows = 6;

/// How many libraries' genre rows are asked for at the same time.
const _genreLibrariesAtOnce = 2;

/// The kinds of rows a set of libraries calls for.
typedef _RowKinds = ({bool video, bool audio, bool books, bool liveTv});

_RowKinds _rowKindsOf(Iterable<CollectionType> libraries) {
  final types = libraries.toSet();
  return (
    video: types.contains(CollectionType.movies) || types.contains(CollectionType.tvshows),
    audio: types.contains(CollectionType.music),
    books: types.contains(CollectionType.books),
    liveTv: types.contains(CollectionType.livetv),
  );
}

/// A request's answer or its failure, held until it is wanted.
///
/// The dashboard's requests go out before it knows which of their answers it
/// will use. A failure nobody is awaiting yet would otherwise be reported as
/// unhandled, and one nobody ends up wanting would fail the whole fetch.
class _Settled<T> {
  _Settled._(this._value, this._error, this._stackTrace);

  static Future<_Settled<T>> of<T>(Future<T> request) => request.then(
        (value) => _Settled<T>._(value, null, null),
        onError: (Object error, StackTrace stackTrace) => _Settled<T>._(null, error, stackTrace),
      );

  final T? _value;
  final Object? _error;
  final StackTrace? _stackTrace;

  /// The answer, or the failure thrown again.
  T get value {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stackTrace ?? StackTrace.current);
    return _value as T;
  }
}
