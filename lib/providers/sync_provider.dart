import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'package:background_downloader/background_downloader.dart';
import 'package:collection/collection.dart';
import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/api_result.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/album_model.dart';
import 'package:chudder/models/items/artist_model.dart';
import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/playlist_model.dart';
import 'package:chudder/models/items/season_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/models/syncing/database_item.dart';
import 'package:chudder/models/syncing/download_stream.dart';
import 'package:chudder/models/syncing/sync_item.dart';
import 'package:chudder/models/syncing/sync_settings_model.dart';
import 'package:chudder/models/syncing/transcode_download_model.dart';
import 'package:chudder/models/syncing/transcode_music_download_model.dart';
import 'package:chudder/models/video_stream_model.dart';
import 'package:chudder/profiles/default_profile.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/screens/settings/widgets/transcode_music_settings_popup.dart';
import 'package:chudder/screens/settings/widgets/transcode_settings_popup.dart';
import 'package:chudder/providers/sync/background_download_provider.dart';
import 'package:chudder/providers/sync/sync_provider_media.dart';
import 'package:chudder/providers/sync/sync_refresh.dart';
import 'package:chudder/providers/sync/sync_removal_plan.dart';
import 'package:chudder/providers/sync/sync_provider_overlay.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/services/notification_service.dart';
import 'package:chudder/util/duration_extensions.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/string_extensions.dart';
import 'package:chudder/util/synced_artwork.dart';

final syncProvider = StateNotifierProvider<SyncNotifier, SyncSettingsModel>((ref) => throw UnimplementedError());

final downloadTasksProvider = StateProvider.family<DownloadStream, String?>((ref, id) => DownloadStream.empty());

final activeDownloadTasksProvider = StateProvider<List<DownloadTask>>((ref) {
  return [];
});

/// Every download that has not finished, by item id: running, waiting,
/// paused and failed alike. Restored from the downloader's records at launch,
/// so a download that failed while the app was away still says so.
final downloadQueueProvider = StateProvider<Map<String, DownloadStream>>((ref) => const {});

const syncPathKey = "syncPathKey";

int _sizeOfDirectory(String path) {
  var size = 0;
  for (final entity in Directory(path).listSync(recursive: true, followLinks: false)) {
    if (entity is File) size += entity.lengthSync();
  }
  return size;
}

class SyncNotifier extends StateNotifier<SyncSettingsModel> {
  SyncNotifier(this.ref, this.mobileDirectory)
      : _db = AppDatabase(ref),
        super(SyncSettingsModel()) {
    _init();
  }

  final Ref ref;
  final AppDatabase _db;
  final Directory mobileDirectory;
  final String subPath = "Synced";

  bool updatingSyncStatus = false;

  /// Items being removed, and everything under them. A removal takes a while
  /// (tasks to cancel, folders to delete), and in that time a second press of
  /// Remove, or a download that is still fetching its metadata, would put the
  /// rows straight back or run the same removal twice.
  final Set<String> _deleting = {};

  /// Whether [id] is on its way out; downloads that would recreate it stand
  /// down.
  bool isBeingRemoved(String id) => _deleting.contains(id);

  StreamSubscription<List<SyncedItem>>? _subscription;
  StreamSubscription<void>? _artworkSubscription;

  @override
  set state(SyncSettingsModel value) {
    super.state = value;
    updateSyncStates();
  }

  Future<void> updateSyncStates() async {
    // Taken before the query rather than after it: at launch this is asked
    // three times in a row, and each call used to run the query before the
    // first of them had marked itself as under way.
    if (updatingSyncStatus) return;
    updatingSyncStatus = true;
    try {
      final lastState = (await _db.getUnsyncedItems.get()).where((item) => item.userData != null).toList();
      for (final item in lastState) {
        if (item.userData == null) continue;
        final updatedItem =
            await ref.read(jellyApiProvider).userItemsItemIdUserDataPost(itemId: item.id, body: item.userData);
        if (updatedItem?.isSuccessful == true) {
          final syncedItem = item.copyWith(unSyncedData: false);
          await _db.insertItem(syncedItem);
        } else {
          break;
        }
      }
    } catch (e) {
      // log('Error updating sync states: $e');
    } finally {
      updatingSyncStatus = false;
    }
  }

  void _init() {
    // Later, and off the launch: it walks the system temp directory, which on
    // a desktop holds thousands of entries, and nothing depends on it. The
    // browser has no such directory, and asking path_provider for one there
    // throws an unhandled MissingPluginException into the console.
    if (!kIsWeb) {
      Timer(const Duration(seconds: 15), () {
        cleanupTemporaryFiles();
        _saveMissingArtwork();
      });
    }
    ref.listen(
      userProvider,
      (previous, next) {
        if (previous?.id != next?.id) {
          if (next?.id != null) {
            _initializeQueryStream(id: next!.id);
          }
        }
      },
    );

    ref.listen(connectivityStatusProvider, (_, next) {
      if (next != ConnectionState.offline) {
        updateSyncStates();
        _saveMissingArtwork();
      }
    });
    _initializeQueryStream();
  }

  void _initializeQueryStream({String? id}) async {
    final userId = id ?? ref.read(userProvider)?.id;
    _subscription?.cancel();
    state = state.copyWith(items: []);

    if (userId == null) return;

    // Only the roots, and only from the one query. This used to read every
    // row - the series, each season and each episode of every sync - convert
    // each one, which is a file read and a JSON decode on this isolate, and
    // then keep the handful with no parent; and it did that twice, once to
    // seed the state and once more for the watch's first emission.
    _subscription = _db.getParentItems.watch().listen((items) {
      state = state.copyWith(items: items);
    });

    _artworkSubscription?.cancel();
    _artworkSubscription = _db.getArtwork.watch().listen(SyncedArtwork.replaceAll);
  }

  bool _artworkSaved = false;

  /// Saves the thumbs of downloads made before thumbs were saved - the wide
  /// cards offline showed nothing for them - and any picture the server did
  /// not hand over at the time. Once a launch; again after a failure.
  Future<void> _saveMissingArtwork() async {
    if (_artworkSaved || kIsWeb) return;
    _artworkSaved = true;
    try {
      for (final row in await _db.getArtworkRows.get()) {
        final images = row.images;
        final folder = row.path;
        if (images == null || folder == null || folder.isEmpty) continue;
        final directory = Directory(folder);
        if (!await directory.exists()) continue;

        Future<ImageData?> save(ImageData? image, String fileName) async =>
            image != null && image.path.startsWith("http") ? await urlDataToFileData(image, directory, fileName) : image;

        final primary = await save(images.primary, "primary.jpg");
        final thumb = await save(images.thumb, "thumb.jpg");
        final logo = await save(images.logo, "logo.jpg");
        if (primary == images.primary && thumb == images.thumb && logo == images.logo) continue;
        await _db.updateImages(
          row.id,
          images.copyWith(primary: () => primary, thumb: () => thumb, logo: () => logo),
        );
      }
    } catch (e) {
      _artworkSaved = false;
      log('Saving missing download artwork failed: $e');
    }
  }

  List<SyncedItem> _rootSyncItems(List<SyncedItem> items) {
    return items.where((item) => item.parentId == null).toList();
  }

  Future<void> cleanupTemporaryFiles() async {
    final activeDownloads = ref.read(activeDownloadTasksProvider);
    if (activeDownloads.isNotEmpty) return;
    // The in-memory list is empty after every launch, including one where
    // downloads are still going in the background or are paused with their
    // partial files kept for resuming - those files are what this sweeps.
    if (await ref.read(backgroundDownloaderProvider.notifier).hasUnfinishedTasks()) return;

    // List of directories to check
    final directories = [
      //Desktop directory
      await getTemporaryDirectory(),
      //Mobile directory
      await getApplicationSupportDirectory(),
    ];

    for (final dir in directories) {
      // Streamed, and judged by name before anything is asked of the file:
      // listing synchronously blocked the app for the whole directory, and
      // every entry in it used to be stat'd to find the few that are ours.
      await for (final file in dir.list()) {
        if (file is File) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          if (!fileName.startsWith('com.bbflight.background_downloader')) continue;
          try {
            final fileSize = await file.length();
            if (fileSize != 0) {
              try {
                await file.delete();
                log('Deleted temporary file: $fileName from ${dir.path}');
              } catch (e) {
                log('Failed to delete file $fileName: $e');
              }
            }
          } on PathAccessException {
            // Skip files that are inaccessible
            continue;
          }
        }
      }
    }
  }

  Future<List<String>> getTempFiles() async {
    final tempFiles = <String>[];

    // List of directories to check
    final directories = [
      //Desktop directory
      await getTemporaryDirectory(),
      //Mobile directory
      await getApplicationSupportDirectory(),
    ];

    for (final dir in directories) {
      final List<FileSystemEntity> files = dir.listSync();

      for (var file in files) {
        if (file is File) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          final fileSize = await file.length();
          if (fileName.startsWith('com.bbflight.background_downloader') && fileSize != 0) {
            tempFiles.add(file.path);
          }
        }
      }
    }

    return tempFiles;
  }

  late final JellyService api = ref.read(jellyApiProvider);

  String? get _savePath => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      ? ref.read(clientSettingsProvider.select((value) => value.syncPath))
      : mobileDirectory.path;

  String? get savePath => _savePath;

  Directory get mainDirectory => Directory(path.joinAll([_savePath ?? "", subPath]));

  Directory? get saveDirectory {
    try {
      if (kIsWeb) return null;
      final directory = _savePath != null
          ? Directory(path.joinAll([_savePath ?? "", subPath, ref.read(userProvider)?.id ?? "UnknownUser"]))
          : null;
      directory?.createSync(recursive: true);
      if (directory?.existsSync() == true) {
        final noMedia = File(path.joinAll([directory?.path ?? "", ".nomedia"]));
        noMedia.writeAsString('');
        noMedia.createSync();
      }
      return directory;
    } catch (e) {
      log('Error accessing save directory: ${e.toString()}');
      return null;
    }
  }

  String? get syncPath => saveDirectory?.path;

  Future<int>? _directorySize;
  DateTime? _directorySizeAt;

  /// Off the UI isolate, and kept for a while: this walks every downloaded
  /// file, and the settings page asked for it anew on every rebuild.
  Future<int> get directorySize {
    final path = saveDirectory?.path;
    if (path == null) return Future.value(0);
    final cached = _directorySize;
    final at = _directorySizeAt;
    if (cached != null && at != null && DateTime.now().difference(at) < const Duration(seconds: 30)) {
      return cached;
    }
    _directorySizeAt = DateTime.now();
    return _directorySize = compute(_sizeOfDirectory, path);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _artworkSubscription?.cancel();
    super.dispose();
  }

  Future<void> refresh() async => state = state.copyWith(items: _rootSyncItems(await _db.getAllItems.get()));

  Future<List<SyncedItem>> getNestedChildren(SyncedItem? item) async {
    if (item == null) return [];
    if (item.itemModel?.type == FladderItemType.playlist) {
      return _getPlaylistChildrenFromOverlay(item);
    }
    return _db.getNestedChildren(item);
  }

  Future<List<SyncedItem>> getChildren(String parentId) async => await _db.getChildren(parentId).get();

  Future<List<SyncedItem>> getChildrenForItem(SyncedItem item) async {
    if (item.itemModel?.type == FladderItemType.playlist) {
      return _getPlaylistChildrenFromOverlay(item);
    }
    return getChildren(item.id);
  }

  Future<List<SyncedItem>> _getPlaylistChildrenFromOverlay(SyncedItem item) async {
    final childIds = await item.getPlaylistChildIdsAsync();
    if (childIds.isEmpty) return [];

    final children = await Future.wait(childIds.map(getSyncedItem));
    return children.whereType<SyncedItem>().where((child) => child.itemModel is AudioModel).toList();
  }

  /// Every downloaded item, as the models the library screens render.
  ///
  /// Screens that normally ask the server need something to show when there is
  /// no server, and "what is on disk" is the only honest answer. Only items
  /// whose video file is actually present are returned, so a queued or failed
  /// download never appears as something that can be played.
  Future<List<ItemBaseModel>> allDownloadedItems({Set<FladderItemType>? types}) async {
    final items = await _db.getDownloadedItems.get();
    return items
        .where((item) => item.videoFile.existsSync())
        .map((item) => item.itemModel)
        .nonNulls
        .where((model) => types == null || types.contains(model.type))
        .toList();
  }

  /// Watch progress made offline that has not reached the server yet.
  Future<int> pendingUserDataCount() async =>
      (await _db.getUnsyncedItems.get()).where((item) => item.userData != null).length;

  Future<List<SyncedItem>> getSiblings(SyncedItem syncedItem) async {
    if (syncedItem.parentId == null) return [];
    return getChildren(syncedItem.parentId!);
  }

  Future<SyncedItem?> getSyncedItem(String? id) async {
    if (id == null) return null;
    return await _db.getItem(id).getSingleOrNull();
  }

  Stream<SyncedItem?> watchItem(String id) => _db.getItem(id).watchSingleOrNull();

  Future<SyncedItem?> getParentItem(String id) async => await _db.getParent(id).getSingleOrNull();

  Future<SyncedItem> refreshSyncItem(SyncedItem item) async {
    List<SyncedItem> itemsToSync = await getNestedChildren(item);

    itemsToSync = [item, ...itemsToSync];

    SyncedItem parentItem = item;

    for (var i = 0; i < itemsToSync.length; i++) {
      final itemToSync = itemsToSync[i];
      if (isBeingRemoved(itemToSync.id)) continue;

      final itemResponse = await api.usersUserIdItemsItemIdGetBaseItem(
        itemId: itemToSync.id,
      );

      final itemModel = ItemBaseModel.fromBaseDto(itemResponse.bodyOrThrow, ref);

      final syncedParent = await _db.getItem(itemToSync.parentId ?? "").getSingleOrNull();

      SyncedItem newSyncedItem = await _syncItemData(syncedParent, itemModel, itemResponse.bodyOrThrow);

      // Read again now: the row may have changed, or gone, while the server
      // was answering. Written straight away, item by item, so one that
      // fails (the connection dropping half way) does not leave the files of
      // the others rewritten and their rows as they were.
      final current = await _db.getItem(itemToSync.id).getSingleOrNull();
      if (current == null || isBeingRemoved(current.id)) continue;

      final updatedItem = mergeRefreshed(current, newSyncedItem, itemModel: newSyncedItem.createItemModel(ref));
      await _db.insertItem(updatedItem);

      if (itemToSync.id == parentItem.id) {
        parentItem = updatedItem;
      }
    }

    return parentItem;
  }

  Future<void> addSyncItem(BuildContext? context, ItemBaseModel item) async {
    try {
      if (context == null) return;

      if (saveDirectory == null) {
        final selectedDirectory =
            await FilePicker.platform.getDirectoryPath(dialogTitle: context.localized.syncSelectDownloadsFolder);
        // Cancelling the picker returns null, and `null?.isEmpty == true` is
        // false, so a cancelled pick fell straight through into the download
        // with no folder set. Every path then came out relative to whatever
        // the process's working directory happened to be - which is how a
        // finished download could no longer be found, let alone played.
        if (selectedDirectory == null || selectedDirectory.isEmpty) {
          if (context.mounted) {
            FladderSnack.show(context.localized.syncNoFolderSetup, context: context);
          }
          return;
        }
        // Awaited: on macOS this resolves a security bookmark first, so
        // without the await the download started before the path was set.
        await ref.read(clientSettingsProvider.notifier).setSyncPath(selectedDirectory);
        if (saveDirectory == null) {
          if (context.mounted) {
            FladderSnack.show(context.localized.syncNoFolderSetup, context: context);
          }
          return;
        }
      }

      TranscodeDownloadModel? transcodeModel;
      TranscodeMusicDownloadModel? musicTranscodeModel;

      if (ref.read(clientSettingsProvider.select((value) => value.askDownloadQuality))) {
        if (!context.mounted) return;
        final choice = await _askDownloadQuality(context, item);
        // Dismissing the dialog cancels the download rather than falling back
        // to whatever the saved defaults happen to be.
        if (choice == null) return;
        transcodeModel = choice.video;
        musicTranscodeModel = choice.music;
      }

      // The download runs as a foreground service with a notification; with
      // notifications refused it still runs, but invisibly, and whatever
      // happens to it happens where nobody can see.
      if (!kIsWeb && Platform.isAndroid) await NotificationService.requestPermission();

      if (context.mounted) {
        FladderSnack.show(context.localized.syncAddItemForSyncing(item.detailedName(context.localized) ?? "Unknown"),
            context: context);
      }
      final newSync = switch (item) {
        EpisodeModel episode =>
          await syncSeries(item.parentBaseModel, episode: episode, transcodeModel: transcodeModel),
        SeasonModel season => await syncSeries(item.parentBaseModel, season: season, transcodeModel: transcodeModel),
        SeriesModel series => await syncSeries(series, transcodeModel: transcodeModel),
        MovieModel movie => await syncMovie(movie, transcodeModel: transcodeModel),
        AudioModel audio => await syncAudio(audio, musicTranscodeModel: musicTranscodeModel),
        AlbumModel album => await syncAlbum(album, musicTranscodeModel: musicTranscodeModel),
        ArtistModel artist => await syncArtist(artist, musicTranscodeModel: musicTranscodeModel),
        PlaylistModel playlist => await syncPlaylist(playlist, musicTranscodeModel: musicTranscodeModel),
        _ => null
      };
      if (context.mounted) {
        FladderSnack.show(
            newSync != null
                ? context.localized.startedSyncingItem(item.detailedName(context.localized) ?? "Unknown")
                : context.localized.unableToSyncItem(item.detailedName(context.localized) ?? "Unknown"),
            context: context);
      }

      return;
    } catch (e) {
      log('Error adding sync item: ${e.toString()}');
      if (context?.mounted == true) {
        FladderSnack.show(context!.localized.somethingWentWrong, context: context);
      }
    }
  }

  /// Asks which quality to download at, and whether to stop asking.
  ///
  /// Returns null when the dialog is dismissed, which cancels the download.
  /// Ticking "always use these settings" saves the choice as the new default
  /// and clears [ClientSettingsModel.askDownloadQuality]; the toggle in
  /// Settings puts the question back.
  Future<({TranscodeDownloadModel? video, TranscodeMusicDownloadModel? music})?> _askDownloadQuality(
    BuildContext context,
    ItemBaseModel item,
  ) async {
    final settings = ref.read(clientSettingsProvider.notifier);
    final isMusic = switch (item) {
      AudioModel _ || AlbumModel _ || ArtistModel _ || PlaylistModel _ => true,
      _ => false,
    };

    TranscodeDownloadModel? video;
    TranscodeMusicDownloadModel? music;
    bool confirmed = false;
    bool always = false;

    if (isMusic) {
      await showTranscodeMusicSettingsPopup(
        context: context,
        current: ref.read(clientSettingsProvider.select((value) => value.transcodeMusicDownloadModel)),
        showAlwaysOption: true,
        onChanged: (value) {
          music = value;
          confirmed = true;
        },
        onAlways: (value) => always = value,
      );
    } else {
      await showTranscodeSettingsPopup(
        context: context,
        current: ref.read(clientSettingsProvider.select((value) => value.transcodeDownloadModel)),
        showAlwaysOption: true,
        scope: await _downloadScope(item),
        onChanged: (value) {
          video = value;
          confirmed = true;
        },
        onAlways: (value) => always = value,
      );
    }

    if (!confirmed) return null;

    if (always) {
      settings.update((current) => current.copyWith(
            askDownloadQuality: false,
            transcodeDownloadModel: video ?? current.transcodeDownloadModel,
            transcodeMusicDownloadModel: music ?? current.transcodeMusicDownloadModel,
          ));
    }

    return (video: video, music: music);
  }

  /// What a download of [item] would take in: how long it all runs, how
  /// many files, and what the originals weigh - so the quality dialog can
  /// price each choice for this download rather than per hour. For a season
  /// or a show, the episodes not on the device yet.
  Future<DownloadScope?> _downloadScope(ItemBaseModel item) async {
    try {
      List<BaseItemDto> items;
      switch (item) {
        case SeasonModel _ || SeriesModel _:
          final response = await api
              .showsSeriesIdEpisodesGet(
                seriesId: item is SeasonModel ? item.seriesId : item.id,
                seasonId: item is SeasonModel ? item.id : null,
                isMissing: false,
                fields: [ItemFields.mediasources],
                enableImages: false,
                enableUserData: false,
              )
              .timeout(const Duration(seconds: 6));
          items = response.body?.items ?? const [];
        case MovieModel _ || EpisodeModel _:
          final response = await api.usersUserIdItemsItemIdGetBaseItem(itemId: item.id).timeout(const Duration(seconds: 6));
          items = [if (response.body != null) response.body!];
        default:
          return null;
      }
      final missing = <BaseItemDto>[];
      for (final dto in items) {
        final synced = await getSyncedItem(dto.id);
        if (synced != null && synced.videoFile.existsSync()) continue;
        missing.add(dto);
      }
      if (missing.isEmpty) return null;
      final ticks = missing.fold<int>(0, (sum, dto) => sum + (dto.runTimeTicks ?? 0));
      final bytes = missing.fold<int>(0, (sum, dto) => sum + (dto.mediaSources?.firstOrNull?.size ?? 0));
      return DownloadScope(
        runtime: Duration(microseconds: ticks ~/ 10),
        count: missing.length,
        originalBytes: bytes > 0 ? bytes : null,
      );
    } catch (e) {
      log('Could not work out the download size: $e');
      return null;
    }
  }

  void viewDatabase(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (context) => DriftDbViewer(_db)));

  void _markForDelete(Set<String> ids, bool marked) {
    state = state.copyWith(
      items: state.items.map((e) => ids.contains(e.id) ? e.copyWith(markedForDelete: marked) : e).toList(),
    );
  }

  static bool isMusicRoot(SyncedItem item) => switch (item.itemModel?.type) {
        FladderItemType.playlist || FladderItemType.musicAlbum || FladderItemType.musicArtist => true,
        _ => false,
      };

  /// Removes a download and everything under it.
  ///
  /// Order matters: the tasks stop first (so nothing writes into a folder that
  /// is going), then the folders go, and the rows go last. A removal that dies
  /// half way then leaves an entry that can be removed again, instead of files
  /// on disk that nothing knows about.
  Future<bool> removeSync(BuildContext context, SyncedItem? item) async {
    if (item == null) return false;
    // Music is shared between albums, artists and playlists; see removeMusic.
    if (isMusicRoot(item)) return removeMusic(context, item, MusicRemovalMode.everything);
    if (!_deleting.add(item.id)) return false;

    final ids = {item.id};
    try {
      final nestedChildren = await getNestedChildren(item);
      final everything = [...nestedChildren, item];
      ids.addAll(everything.map((e) => e.id));
      _deleting.addAll(ids);
      _markForDelete({item.id}, true);

      for (final element in everything) {
        await ref.read(backgroundDownloaderProvider).cancelTaskWithId(element.id);
        await ref.read(backgroundDownloaderProvider.notifier).forget(element.id);
      }

      for (final element in nestedChildren) {
        if (await element.directory.exists()) {
          await element.directory.delete(recursive: true);
        }
      }
      if (await item.directory.exists()) {
        await item.directory.delete(recursive: true);
      }

      await _db.deleteAllItems(everything);

      return true;
    } catch (e) {
      log('Error deleting synced item ${e.toString()}');
      _markForDelete({item.id}, false);
      if (context.mounted) FladderSnack.show(context.localized.syncRemoveUnableToDeleteItem, context: context);
      return false;
    } finally {
      _deleting.removeAll(ids);
    }
  }

  /// What removing [root] (a playlist, album or artist) would do to its
  /// tracks in [mode], for the dialog to describe before anything happens.
  Future<MusicRemovalPlan> planMusicRemovalFor(SyncedItem root, MusicRemovalMode mode) async {
    final tracks = (await getNestedChildren(root)).where((child) => child.itemModel is AudioModel).toList();
    final isPlaylist = root.itemModel?.type == FladderItemType.playlist;

    final playlists = <String, Set<String>>{};
    for (final row in await _db.getAllItems.get()) {
      if (row.itemModel?.type != FladderItemType.playlist) continue;
      playlists[row.id] = (await row.getPlaylistChildIdsAsync()).toSet();
    }

    final albumOf = <String, String?>{for (final track in tracks) track.id: track.parentId};
    final tracksOfAlbum = <String, Set<String>>{};
    if (isPlaylist) {
      for (final albumId in albumOf.values.nonNulls.toSet()) {
        tracksOfAlbum[albumId] =
            (await getChildren(albumId)).where((row) => row.itemModel is AudioModel).map((row) => row.id).toSet();
      }
    }

    return planMusicRemoval(
      scope: isPlaylist ? MusicRemovalScope.playlist : MusicRemovalScope.library,
      mode: mode,
      tracks: tracks.map((track) => track.id).toSet(),
      playlists: playlists,
      removedPlaylistId: isPlaylist ? root.id : null,
      albumOf: albumOf,
      tracksOfAlbum: tracksOfAlbum,
    );
  }

  /// The names of the playlists with these ids, for a dialog.
  Future<List<String>> playlistNames(Iterable<String> ids) async {
    final names = <String>[];
    for (final id in ids) {
      final name = (await getSyncedItem(id))?.itemModel?.name;
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names;
  }

  /// Removes a downloaded playlist, album or artist, with [mode] deciding what
  /// happens to the tracks something else still uses.
  ///
  /// Tracks that stay keep their album and artist rows (a track is a row under
  /// them), and an album or artist that ends up with no tracks goes with the
  /// rest.
  Future<bool> removeMusic(BuildContext context, SyncedItem root, MusicRemovalMode mode) async {
    if (!_deleting.add(root.id)) return false;

    var tracks = <SyncedItem>[];
    try {
      final plan = await planMusicRemovalFor(root, mode);
      tracks = (await getNestedChildren(root))
          .where((child) => child.itemModel is AudioModel && plan.remove.contains(child.id))
          .toList();
      _deleting.addAll(tracks.map((track) => track.id));
      _markForDelete({root.id}, true);

      for (final track in tracks) {
        await _deleteSyncedItemAndFiles(track);
      }

      if (root.itemModel?.type == FladderItemType.playlist) {
        await _deleteSyncedItemAndFiles(root);
      } else {
        await _cleanupOrphanedMusicParents(tracks);
        // An album or artist that never had tracks of its own is not reached
        // from a track.
        final remaining = await getSyncedItem(root.id);
        if (remaining != null && !await _hasSyncedAudioDescendants(remaining.id)) {
          await _deleteSyncedItemAndFiles(remaining);
        }
      }

      return true;
    } catch (e) {
      log('Error deleting synced music ${e.toString()}');
      _markForDelete({root.id}, false);
      if (context.mounted) FladderSnack.show(context.localized.syncRemoveUnableToDeleteItem, context: context);
      return false;
    } finally {
      _deleting.remove(root.id);
      _deleting.removeAll(tracks.map((track) => track.id));
    }
  }

  /// Stops what is still running for [item], deletes its folder, and only then
  /// its row - see [removeSync].
  Future<void> _deleteSyncedItemAndFiles(SyncedItem item) async {
    await ref.read(backgroundDownloaderProvider).cancelTaskWithId(item.id);
    await ref.read(backgroundDownloaderProvider.notifier).forget(item.id);
    if (await item.directory.exists()) {
      await item.directory.delete(recursive: true);
    }
    await _db.deleteAllItems([item]);
  }

  Future<bool> _hasSyncedAudioDescendants(String parentId) async {
    final queue = <SyncedItem>[...await getChildren(parentId)];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (current.itemModel is AudioModel) return true;
      queue.addAll(await getChildren(current.id));
    }

    return false;
  }

  Future<void> _cleanupOrphanedMusicParents(Iterable<SyncedItem> removedTracks) async {
    final candidateAlbumIds = <String>{};
    final candidateArtistIds = <String>{};

    for (final removedTrack in removedTracks) {
      final parentId = removedTrack.parentId;
      if (parentId == null) continue;

      final parent = await getSyncedItem(parentId);
      if (parent == null) continue;

      switch (parent.itemModel?.type) {
        case FladderItemType.musicAlbum:
          candidateAlbumIds.add(parent.id);
          if (parent.parentId != null) {
            candidateArtistIds.add(parent.parentId!);
          }
          break;
        case FladderItemType.musicArtist:
          candidateArtistIds.add(parent.id);
          break;
        default:
          break;
      }
    }

    for (final albumId in candidateAlbumIds) {
      final album = await getSyncedItem(albumId);
      if (album == null || album.itemModel?.type != FladderItemType.musicAlbum) continue;

      final hasTracks = await _hasSyncedAudioDescendants(album.id);
      if (hasTracks) continue;

      if (album.parentId != null) {
        candidateArtistIds.add(album.parentId!);
      }

      await _deleteSyncedItemAndFiles(album);
    }

    for (final artistId in candidateArtistIds) {
      final artist = await getSyncedItem(artistId);
      if (artist == null || artist.itemModel?.type != FladderItemType.musicArtist) continue;

      final hasTracks = await _hasSyncedAudioDescendants(artist.id);
      if (hasTracks) continue;

      await _deleteSyncedItemAndFiles(artist);
    }
  }

  Future<int> updateItem(SyncedItem item) async {
    SyncedItem syncedItem = item;
    try {
      await ref.read(jellyApiProvider).userItemsItemIdUserDataPost(itemId: syncedItem.id, body: syncedItem.userData);
    } catch (e) {
      log('Error updating item: ${syncedItem.id}');
      syncedItem = syncedItem.copyWith(unSyncedData: true);
    }
    return _db.insertItem(syncedItem);
  }

  Future<void> syncSyncedItem(
    BuildContext context,
    SyncedItem syncedItem, {
    TranscodeDownloadModel? transcodeModel,
    TranscodeMusicDownloadModel? musicTranscodeModel,
  }) async {
    final model = syncedItem.itemModel;

    switch (model) {
      case AudioModel audio:
        await syncAudio(audio, musicTranscodeModel: musicTranscodeModel);
        return;
      case AlbumModel album:
        await syncAlbum(album, musicTranscodeModel: musicTranscodeModel);
        return;
      case ArtistModel artist:
        await syncArtist(artist, musicTranscodeModel: musicTranscodeModel);
        return;
      default:
        await syncFile(
          syncedItem,
          false,
          transcodeModel: transcodeModel,
          musicTranscodeModel: musicTranscodeModel,
        );
        return;
    }
  }

  Future<SyncedItem> deleteFullSyncFiles(SyncedItem syncedItem, DownloadTask? task) async {
    // Only the file: the row stays, for a track as for an episode, so the
    // entry can be downloaded again and the album and playlists that list it
    // still do. Removing the item itself is removeSync / removeMusic.
    //
    // The task stops before the file goes: one finishing in between wrote it
    // straight back.
    await ref.read(backgroundDownloaderProvider).cancelTaskWithId(syncedItem.id);
    await ref.read(backgroundDownloaderProvider.notifier).forget(syncedItem.id);

    await syncedItem.deleteDatFiles(ref);

    syncedItem = syncedItem.copyWith(
      transcodeDownloadModel: null,
    );
    await updateItem(syncedItem);

    ref.read(downloadTasksProvider(syncedItem.id).notifier).update((state) => DownloadStream.empty());

    cleanupTemporaryFiles();
    refresh();
    return syncedItem;
  }

  /// Starts a failed or stuck download over, with a fresh address: the one
  /// the task was made with carries a session and, for a transcode, a job on
  /// the server that may both be long gone.
  Future<bool> retryDownload(String itemId) async {
    final syncedItem = await getSyncedItem(itemId);
    await ref.read(backgroundDownloaderProvider).cancelTaskWithId(itemId);
    await ref.read(backgroundDownloaderProvider.notifier).forget(itemId);
    if (syncedItem == null) return false;
    return await syncFile(syncedItem, false) ?? false;
  }

  Future<void> retryAllFailed() async {
    final failed = ref.read(downloadQueueProvider).values.where((stream) => stream.needsRetry).map((e) => e.id).toList();
    for (final id in failed) {
      await retryDownload(id);
    }
  }

  Future<void> pauseTask(DownloadStream stream) async {
    final task = stream.task;
    if (task != null && stream.canPause) await ref.read(backgroundDownloaderProvider).pause(task);
  }

  Future<void> resumeTask(DownloadStream stream) async {
    final task = stream.task;
    if (task != null) await ref.read(backgroundDownloaderProvider).resume(task);
  }

  Future<void> pauseAll() async {
    final downloader = ref.read(backgroundDownloaderProvider);
    for (final stream in ref.read(downloadQueueProvider).values) {
      final task = stream.task;
      if (task == null) continue;
      // Only what can be picked up again: a transcode paused is a transcode
      // thrown away.
      if (stream.canPause) await downloader.pause(task);
    }
  }

  Future<void> resumeAll() async {
    final downloader = ref.read(backgroundDownloaderProvider);
    for (final stream in ref.read(downloadQueueProvider).values) {
      final task = stream.task;
      if (task == null || stream.status != TaskStatus.paused) continue;
      await downloader.resume(task);
    }
  }

  /// Stops a download and forgets it, leaving the item as not downloaded.
  Future<void> cancelDownload(String itemId) async {
    await ref.read(backgroundDownloaderProvider).cancelTaskWithId(itemId);
    await ref.read(backgroundDownloaderProvider.notifier).forget(itemId);
    cleanupTemporaryFiles();
  }

  /// Deletes the files of every watched episode under [root], keeping the
  /// ones still to watch. The rows stay, so the show still lists them.
  Future<int> deleteWatched(SyncedItem root) async {
    int removed = 0;
    for (final child in await getNestedChildren(root)) {
      if (child.userData?.played != true || !child.videoFile.existsSync()) continue;
      await deleteFullSyncFiles(child, null);
      removed++;
    }
    return removed;
  }

  /// Downloads whatever under [root] is not on the device yet, in the
  /// default quality.
  Future<int> downloadRemaining(SyncedItem root, {TranscodeDownloadModel? transcodeModel}) async {
    int started = 0;
    for (final child in await getNestedChildren(root)) {
      if (!child.hasVideoFile || child.videoFile.existsSync()) continue;
      if (ref.read(downloadTasksProvider(child.id)).isPending) continue;
      syncFile(child, false, transcodeModel: transcodeModel);
      started++;
    }
    return started;
  }

  Future<bool?> syncFile(
    SyncedItem syncItem,
    bool skipDownload, {
    TranscodeDownloadModel? transcodeModel,
    TranscodeMusicDownloadModel? musicTranscodeModel,
  }) async {
    cleanupTemporaryFiles();

    if (isBeingRemoved(syncItem.id)) return null;

    if (!skipDownload && syncItem.videoFile.existsSync()) {
      return true;
    }

    final globalTranscodeModel = ref.read(clientSettingsProvider.select((value) => value.transcodeDownloadModel));
    final globalMusicTranscodeModel =
        ref.read(clientSettingsProvider.select((value) => value.transcodeMusicDownloadModel));

    final effectiveTranscodeModel = transcodeModel ?? globalTranscodeModel;
    final effectiveMusicTranscodeModel = musicTranscodeModel ?? globalMusicTranscodeModel;

    final userId = ref.read(userProvider)?.id;
    final item = syncItem.createItemModel(ref);
    if (item == null) return null;
    final isAudioItem = item is AudioModel;
    final streamModel = item.streamModel;
    final transcodeEnabled = isAudioItem ? effectiveMusicTranscodeModel.enabled : effectiveTranscodeModel.enabled;
    final maxBitrate =
        isAudioItem ? effectiveMusicTranscodeModel.maxBitrate.bitRate : effectiveTranscodeModel.maxBitrate.bitRate;
    final deviceProfile = isAudioItem
        ? (effectiveMusicTranscodeModel.enabled
            ? effectiveMusicTranscodeModel.deviceProfile
            : ref.read(videoProfileProvider))
        : (effectiveTranscodeModel.enabled ? effectiveTranscodeModel.deviceProfile : ref.read(videoProfileProvider));

    final playbackResponse = await FladderSnack.showResponse(
      api
          .itemsItemIdPlaybackInfoPost(
            itemId: syncItem.id,
            body: PlaybackInfoDto(
              userId: userId,
              enableDirectPlay: !transcodeEnabled,
              enableDirectStream: !transcodeEnabled,
              enableTranscoding: true,
              autoOpenLiveStream: true,
              maxStreamingBitrate: transcodeEnabled ? maxBitrate : null,
              deviceProfile: deviceProfile,
              mediaSourceId: streamModel?.currentVersionStream?.id,
              audioStreamIndex: streamModel?.defaultAudioStreamIndex,
              subtitleStreamIndex: streamModel?.defaultSubStreamIndex,
            ),
          )
          .apiResult,
    );

    final playbackData = playbackResponse.data;
    if (playbackData == null) {
      log('No playback info received for item ${syncItem.id}');
      return null;
    }

    // The playback request above is a round trip; the item may have been
    // removed while it was out, and this is where its folder and row would
    // come back.
    if (isBeingRemoved(syncItem.id)) return null;

    final directory = await Directory(syncItem.directory.path).create(recursive: true);

    final newState = VideoStream.fromPlayBackInfo(playbackData, ref)?.copyWith();
    final subtitles = isAudioItem
        ? <SubStreamModel>[]
        : await saveExternalSubtitles(newState?.mediaStreamsModel?.subStreams, syncItem);

    final trickPlayFile = isAudioItem ? null : await saveTrickPlayData(item, directory);
    final mediaSegments = isAudioItem ? null : (await api.mediaSegmentsGet(id: syncItem.id))?.body;

    syncItem = syncItem.copyWith(
      fChapters: await saveChapterImages(item.overview.chapters, directory) ?? [],
      subtitles: subtitles,
      videoFileName: transcodeEnabled
          ? syncItem.videoFileName?.replaceAll(
              path.extension(syncItem.videoFileName ?? ""),
              isAudioItem
                  ? effectiveMusicTranscodeModel.container.extension
                  : effectiveTranscodeModel.container.extension,
            )
          : syncItem.videoFileName,
      fTrickPlayModel: trickPlayFile,
      mediaSegments: mediaSegments,
      transcodeDownloadModel: isAudioItem ? null : effectiveTranscodeModel,
    );

    if (isAudioItem) {
      await writeMusicOverlayFile(syncItem, effectiveMusicTranscodeModel);
      await _saveSyncedLyrics(syncItem);
    } else {
      await writeOverlayFile(syncItem, effectiveTranscodeModel, subtitles);
    }

    if (isBeingRemoved(syncItem.id)) return null;
    await updateItem(syncItem);

    final currentTask = ref.read(downloadTasksProvider(syncItem.id));
    final user = ref.read(userProvider);

    if (user == null) return null;

    final mediaSource = playbackData.mediaSources?.firstOrNull;

    final String downloadUrl;
    if ((mediaSource?.supportsDirectStream ?? false) || (mediaSource?.supportsDirectPlay ?? false)) {
      final directOptions = {
        'Static': 'true',
        'mediaSourceId': mediaSource!.id,
        ...authQueryParameters(user.credentials.token),
      };
      downloadUrl = buildServerUrl(
        ref,
        pathSegments: [isAudioItem ? 'Audio' : 'Videos', mediaSource.id!, 'stream'],
        queryParameters: directOptions,
      );
      log('Using direct stream URL: $downloadUrl');
    } else if (mediaSource != null &&
        (mediaSource.supportsTranscoding ?? false) &&
        mediaSource.transcodingUrl != null) {
      downloadUrl = buildServerUrl(ref, relativeUrl: mediaSource.transcodingUrl);
      log('Using transcode URL: $downloadUrl');
    } else {
      log('No supported playback method found');
      return null;
    }

    try {
      if (currentTask.task != null) {
        await ref.read(backgroundDownloaderProvider).cancelTaskWithId(currentTask.id);
      }
      if (!skipDownload) {
        final curlHeaders = {
          ...user.credentials.header(ref),
          if (transcodeEnabled)
            ...(isAudioItem
                ? effectiveMusicTranscodeModel.curlHeaders(item.overview.runTime ?? Duration.zero, item: item)
                : effectiveTranscodeModel.curlHeaders(item.overview.runTime ?? Duration.zero, item: item)),
        };

        final downloadTask = DownloadTask(
          taskId: syncItem.id,
          url: downloadUrl,
          directory: syncItem.directory.path,
          filename: syncItem.videoFileName,
          updates: Updates.statusAndProgress,
          baseDirectory: BaseDirectory.root,
          headers: curlHeaders,
          requiresWiFi: ref.read(clientSettingsProvider.select((value) => value.requireWifi)),
          retries: 3,
          allowPause: true,
        );

        ref.read(activeDownloadTasksProvider.notifier).update((state) {
          final existingTasks = state.where((element) => element.taskId != downloadTask.taskId).toList();
          return [...existingTasks, downloadTask];
        });

        final defaultDownloadStream = DownloadStream(id: syncItem.id, task: downloadTask, status: TaskStatus.enqueued);
        ref.read(downloadTasksProvider(syncItem.id).notifier).update((state) => defaultDownloadStream);
        return await ref.read(backgroundDownloaderProvider).enqueue(downloadTask);
      }
    } catch (e) {
      log(e.toString());
      return null;
    }

    return null;
  }

  Future<void> removeAllSyncedData() async {
    if (await mainDirectory.exists()) {
      await mainDirectory.delete(recursive: true);
    }
    await _db.clearDatabase();
    state = state.copyWith(items: []);
  }

  Future<void> updatePlaybackPosition({String? itemId, required Duration position}) async {
    if (itemId == null) return;

    final syncedItem = await _db.getItem(itemId).getSingleOrNull();
    if (syncedItem == null) return;

    final item = syncedItem.itemModel;
    if (item == null) return;

    final progress = position.inMilliseconds / (item.overview.runTime?.inMilliseconds ?? 0) * 100;

    final updatedItem = syncedItem.copyWith(
      userData: syncedItem.userData?.copyWith(
        playbackPositionTicks: position.toRuntimeTicks,
        progress: progress,
        played: UserData.isPlayed(position, item.overview.runTime ?? Duration.zero),
      ),
    );
    await _db.insertItem(updatedItem);
  }

  Future<void> updatePlayedItem(String? itemId,
      {DateTime? datePlayed, required bool played, bool responseSuccessful = false}) async {
    if (itemId == null) return;

    final syncedItem = _db.getItem(itemId).getSingleOrNull();
    syncedItem.then((item) async {
      if (item == null) return;
      final updatedUserData = item.userData?.copyWith(
        played: played,
        playbackPositionTicks: 0,
        progress: 0.0,
        lastPlayed: datePlayed ?? DateTime.now().toUtc(),
      );
      SyncedItem updatedItem = item.copyWith(userData: updatedUserData, unSyncedData: !responseSuccessful);

      List<SyncedItem> children = [];
      final shouldUpdateChildren = {FladderItemType.series, FladderItemType.season}.contains(item.itemModel?.type);
      if (shouldUpdateChildren) {
        // Update child items with the same played status, jellyfin server does this was well
        // when marking a series or season as played
        children = (await getNestedChildren(item))
            .map((e) => e.copyWith(
                  userData: e.userData?.copyWith(
                    played: played,
                    playbackPositionTicks: 0,
                    progress: 0.0,
                  ),
                ))
            .toList();
      }
      await _db.insertMultipleEntries([updatedItem, ...children]);
    });
  }

  Future<void> updateFavoriteItem(String? itemId, {required bool isFavorite, bool responseSuccessful = false}) async {
    if (itemId == null) return;

    final syncedItem = _db.getItem(itemId).getSingleOrNull();
    syncedItem.then((item) async {
      if (item == null) return;
      final updatedUserData = item.userData?.copyWith(isFavourite: isFavorite);
      final updatedItem = item.copyWith(userData: updatedUserData, unSyncedData: !responseSuccessful);
      await _db.insertItem(updatedItem);
    });
  }

  Future<void> _saveSyncedLyrics(SyncedItem syncItem) async {
    try {
      final response = await api.audioItemIdLyricsGet(itemId: syncItem.id);
      final lyrics = response.body;
      if (lyrics == null) {
        if (syncItem.lyricsFile.existsSync()) {
          await syncItem.lyricsFile.delete();
        }
        return;
      }

      await syncItem.lyricsFile.writeAsString(jsonEncode(lyrics.toJson()));
    } catch (e) {
      log('Error saving lyrics for item ${syncItem.id}: ${e.toString()}');
    }
  }
}

extension SyncNotifierHelpers on SyncNotifier {
  Future<SyncedItem> createSyncItem(BaseItemDto response, {SyncedItem? parent}) async {
    final ItemBaseModel item = ItemBaseModel.fromBaseDto(response, ref);

    final existingSyncedItem = await getSyncedItem(item.id);

    if (existingSyncedItem != null) return existingSyncedItem;

    SyncedItem syncItem = await _syncItemData(parent, item, response);

    if (parent == null) {
      await _db.insertItem(syncItem);
    }

    return syncItem.copyWith(
      fileSize: response.mediaSources?.firstOrNull?.size ?? 0,
      syncing: false,
      videoFileName: response.path?.universalBasename ?? "",
    );
  }

  Future<SyncedItem> _syncItemData(SyncedItem? parent, ItemBaseModel item, BaseItemDto response) async {
    final Directory? parentDirectory = parent?.directory;

    // Never join onto "": that yields a bare item id, which is a path relative
    // to the process's working directory. Downloads landed there, and every
    // later read of them - data.json, the video file - resolved against
    // whatever directory the app happened to be launched from.
    final String? basePath = (parentDirectory ?? saveDirectory)?.path;
    if (basePath == null || basePath.isEmpty) {
      throw StateError('No downloads folder configured; refusing to sync ${item.id} to a relative path');
    }

    final directory = Directory(path.joinAll([basePath, item.id]));

    await directory.create(recursive: true);

    File dataFile = File(path.joinAll([directory.path, 'data.json']));
    await dataFile.writeAsString(jsonEncode(response.toJson()));
    final imageData = item is AudioModel
        ? _audioImageDataFromParent(parent: parent, directory: directory)
        : await saveImageData(item.images, directory);

    SyncedItem syncItem = SyncedItem(
      syncing: true,
      id: item.id,
      parentId: parent?.id,
      sortName: response.sortName,
      fImages: imageData,
      userId: ref.read(userProvider)?.id ?? "",
      path: directory.path,
      userData: item.userData,
    );
    return syncItem;
  }

  ImagesData? _audioImageDataFromParent({required SyncedItem? parent, required Directory directory}) {
    final parentImages = parent?.fImages;
    final parentDirectory = parent?.directory;

    if (parentImages == null || parentDirectory == null) return null;

    ImageData? rebasePath(ImageData? image) {
      final imagePath = image?.path;
      if (imagePath == null || imagePath.isEmpty) return null;

      final absoluteParentPath = path.join(parentDirectory.path, imagePath);
      final relativePath = path.relative(absoluteParentPath, from: directory.path);

      return image?.copyWith(path: relativePath);
    }

    return parentImages.copyWith(
      primary: () => rebasePath(parentImages.primary),
      logo: () => rebasePath(parentImages.logo),
      backDrop: () => (parentImages.backDrop ?? []).map((image) => rebasePath(image)).whereType<ImageData>().toList(),
    );
  }

  Future<SyncedItem?> syncMovie(
    ItemBaseModel item, {
    bool skipDownload = false,
    TranscodeDownloadModel? transcodeModel,
  }) async {
    final response = await api.usersUserIdItemsItemIdGetBaseItem(
      itemId: item.id,
    );

    final itemBaseModel = response.body;
    if (itemBaseModel == null) return null;

    SyncedItem syncItem = await createSyncItem(itemBaseModel);

    if (!syncItem.directory.existsSync()) return null;

    await _db.insertItem(syncItem);

    await syncFile(syncItem, skipDownload, transcodeModel: transcodeModel);

    return syncItem;
  }

  Future<SyncedItem?> syncAudio(
    AudioModel item, {
    bool skipDownload = false,
    SyncedItem? parent,
    TranscodeMusicDownloadModel? musicTranscodeModel,
  }) async {
    final existingSyncedItem = await getSyncedItem(item.id);
    if (existingSyncedItem != null && existingSyncedItem.videoFile.existsSync()) {
      return existingSyncedItem;
    }

    final response = await api.usersUserIdItemsItemIdGetBaseItem(
      itemId: item.id,
    );

    final itemBaseModel = response.body;
    if (itemBaseModel == null) return null;

    SyncedItem? albumParent = parent;
    if (albumParent == null && itemBaseModel.albumId != null) {
      final albumResponse = await api.usersUserIdItemsItemIdGetBaseItem(
        itemId: itemBaseModel.albumId!,
      );
      if (albumResponse.body != null) {
        SyncedItem? artistItem;
        if (albumResponse.body!.parentId != null) {
          final artistResponse = await api.usersUserIdItemsItemIdGetBaseItem(
            itemId: albumResponse.body!.parentId!,
          );
          if (artistResponse.body != null) {
            artistItem = await createSyncItem(artistResponse.bodyOrThrow);
            await _db.insertItem(artistItem);
          }
        }
        final albumItem = await createSyncItem(albumResponse.bodyOrThrow, parent: artistItem);
        await _db.insertItem(albumItem);
        albumParent = albumItem;
      }
    }

    SyncedItem syncItem = await createSyncItem(itemBaseModel, parent: albumParent);

    if (!syncItem.directory.existsSync()) return null;

    await _db.insertItem(syncItem);

    await syncFile(syncItem, skipDownload, musicTranscodeModel: musicTranscodeModel);

    return syncItem;
  }

  Future<SyncedItem?> syncAlbum(
    AlbumModel item, {
    bool skipDownload = false,
    SyncedItem? parent,
    TranscodeMusicDownloadModel? musicTranscodeModel,
  }) async {
    final response = await api.usersUserIdItemsItemIdGetBaseItem(
      itemId: item.id,
    );

    final itemBaseModel = response.body;
    if (itemBaseModel == null) return null;

    SyncedItem? artistItem = parent;
    if (artistItem == null && itemBaseModel.parentId != null) {
      final artistResponse = await api.usersUserIdItemsItemIdGetBaseItem(
        itemId: itemBaseModel.parentId!,
      );
      if (artistResponse.body != null) {
        artistItem = await createSyncItem(artistResponse.bodyOrThrow);
        await _db.insertItem(artistItem);
      }
    }

    final albumItem = await createSyncItem(itemBaseModel, parent: artistItem);
    if (!albumItem.directory.existsSync()) return null;

    final tracksResponse = await api.itemsGet(
      parentId: item.id,
      includeItemTypes: [BaseItemKind.audio],
      recursive: false,
      enableUserData: true,
      fields: [
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.overview,
        ItemFields.path,
        ItemFields.parentid,
        ItemFields.sortname,
      ],
    );

    final tracks = tracksResponse.body?.items ?? [];

    final Map<String, SyncedItem> newItems = {albumItem.id: albumItem};
    final Map<String, SyncedItem> itemsToDownload = {};

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final trackDto = await api.usersUserIdItemsItemIdGetBaseItem(itemId: track.id);
      if (trackDto.body == null) continue;
      final syncedTrack = await createSyncItem(trackDto.bodyOrThrow, parent: albumItem);
      newItems[syncedTrack.id] = syncedTrack;
      if (!await syncedTrack.videoFile.exists()) {
        itemsToDownload[syncedTrack.id] = syncedTrack;
      }
    }

    await _db.insertMultipleEntries(newItems.values.toList());

    if (!skipDownload) {
      for (var i = 0; i < itemsToDownload.length; i++) {
        final track = itemsToDownload.values.elementAt(i);
        syncFile(track, false, musicTranscodeModel: musicTranscodeModel);
      }
    }

    return albumItem;
  }

  Future<SyncedItem?> syncArtist(
    ArtistModel item, {
    bool skipDownload = false,
    TranscodeMusicDownloadModel? musicTranscodeModel,
  }) async {
    final response = await api.usersUserIdItemsItemIdGetBaseItem(
      itemId: item.id,
    );

    final itemBaseModel = response.body;
    if (itemBaseModel == null) return null;

    final artistItem = await createSyncItem(itemBaseModel);
    if (!artistItem.directory.existsSync()) return null;

    final albumsResponse = await api.itemsGet(
      parentId: item.id,
      includeItemTypes: [BaseItemKind.musicalbum],
      recursive: false,
      enableUserData: true,
      fields: [
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.overview,
        ItemFields.path,
        ItemFields.parentid,
        ItemFields.sortname,
      ],
    );

    final albums = albumsResponse.body?.items ?? [];

    final Map<String, SyncedItem> newItems = {artistItem.id: artistItem};
    final Map<String, SyncedItem> itemsToDownload = {};

    for (var i = 0; i < albums.length; i++) {
      final album = albums[i];
      final albumDto = await api.usersUserIdItemsItemIdGetBaseItem(itemId: album.id);
      if (albumDto.body == null) continue;
      final syncedAlbum = await createSyncItem(albumDto.bodyOrThrow, parent: artistItem);
      newItems[syncedAlbum.id] = syncedAlbum;

      final tracksResponse = await api.itemsGet(
        parentId: album.id,
        includeItemTypes: [BaseItemKind.audio],
        recursive: false,
        enableUserData: true,
        fields: [
          ItemFields.mediastreams,
          ItemFields.mediasources,
          ItemFields.overview,
          ItemFields.path,
          ItemFields.parentid,
          ItemFields.sortname,
        ],
      );

      final tracks = tracksResponse.body?.items ?? [];

      for (var j = 0; j < tracks.length; j++) {
        final track = tracks[j];
        final trackDto = await api.usersUserIdItemsItemIdGetBaseItem(itemId: track.id);
        if (trackDto.body == null) continue;
        final syncedTrack = await createSyncItem(trackDto.bodyOrThrow, parent: syncedAlbum);
        newItems[syncedTrack.id] = syncedTrack;
        if (!await syncedTrack.videoFile.exists()) {
          itemsToDownload[syncedTrack.id] = syncedTrack;
        }
      }
    }

    await _db.insertMultipleEntries(newItems.values.toList());

    if (!skipDownload) {
      for (var i = 0; i < itemsToDownload.length; i++) {
        final track = itemsToDownload.values.elementAt(i);
        syncFile(track, false, musicTranscodeModel: musicTranscodeModel);
      }
    }

    return artistItem;
  }

  Future<SyncedItem?> syncPlaylist(
    PlaylistModel item, {
    bool skipDownload = false,
    TranscodeMusicDownloadModel? musicTranscodeModel,
  }) async {
    final response = await api.usersUserIdItemsItemIdGetBaseItem(
      itemId: item.id,
    );

    final itemBaseModel = response.body;
    if (itemBaseModel == null) return null;

    final playlistItem = await createSyncItem(itemBaseModel);
    if (!playlistItem.directory.existsSync()) return null;

    await _db.insertItem(playlistItem);

    final tracksResponse = await api.playlistsPlaylistIdItemsGet(
      playlistId: item.id,
      enableUserData: true,
      fields: [
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.overview,
        ItemFields.path,
        ItemFields.parentid,
        ItemFields.sortname,
      ],
    );

    final playlistTracks = tracksResponse.body?.items.whereType<AudioModel>().toList() ?? [];

    final childIds = playlistTracks.map((e) => e.id).whereType<String>().toList();

    for (final track in playlistTracks) {
      await syncAudio(track, skipDownload: skipDownload, musicTranscodeModel: musicTranscodeModel);
    }

    await writePlaylistChildrenOverlay(playlistItem, childIds);

    return playlistItem;
  }

  Future<SyncedItem?> syncSeries(
    SeriesModel item, {
    SeasonModel? season,
    EpisodeModel? episode,
    TranscodeDownloadModel? transcodeModel,
  }) async {
    final response = await api.usersUserIdItemsItemIdGetBaseItem(
      itemId: item.id,
    );

    List<SyncedItem> newItems = [];

    List<SyncedItem>? itemsToDownload = [];

    SyncedItem seriesItem = await createSyncItem(response.bodyOrThrow);
    newItems.add(seriesItem);
    if (!seriesItem.directory.existsSync()) return null;

    final seasonsResponse = await api.showsSeriesIdSeasonsGet(
      seriesId: item.id,
      isMissing: false,
      enableUserData: true,
      fields: [
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.overview,
        ItemFields.mediasourcecount,
        ItemFields.airtime,
        ItemFields.datecreated,
        ItemFields.datelastmediaadded,
        ItemFields.datelastrefreshed,
        ItemFields.sortname,
        ItemFields.seasonuserdata,
        ItemFields.externalurls,
        ItemFields.genres,
        ItemFields.parentid,
        ItemFields.path,
        ItemFields.chapters,
        ItemFields.trickplay,
      ],
    );

    final seasons = seasonsResponse.body?.items ?? [];

    for (var i = 0; i < seasons.length; i++) {
      final newSeason = seasons[i];
      final syncedSeason = await createSyncItem(newSeason, parent: seriesItem);
      newItems.add(syncedSeason);
      final episodesResponse = await api.showsSeriesIdEpisodesGet(
        isMissing: false,
        enableUserData: true,
        fields: [
          ItemFields.mediastreams,
          ItemFields.mediasources,
          ItemFields.overview,
          ItemFields.mediasourcecount,
          ItemFields.airtime,
          ItemFields.datecreated,
          ItemFields.datelastmediaadded,
          ItemFields.datelastrefreshed,
          ItemFields.sortname,
          ItemFields.seasonuserdata,
          ItemFields.externalurls,
          ItemFields.genres,
          ItemFields.parentid,
          ItemFields.path,
          ItemFields.chapters,
          ItemFields.trickplay,
        ],
        seasonId: newSeason.id,
        seriesId: seriesItem.id,
      );

      final episodes = episodesResponse.body?.items?.where((ep) => ep.seasonId == newSeason.id).toList() ?? [];

      final episodeResults = await Future.wait(
        episodes.map((ep) async {
          final newEpisode = await createSyncItem(ep, parent: syncedSeason);
          return (ep, newEpisode);
        }),
      );

      for (final (ep, newEpisode) in episodeResults) {
        newItems.add(newEpisode);
        // A whole show asked for with neither a season nor an episode named
        // used to write every row and download nothing at all.
        final wanted = episode == null && season == null
            ? true
            : episode?.id == ep.id || newSeason.id == season?.id;
        if (wanted && !await newEpisode.videoFile.exists()) {
          itemsToDownload.add(newEpisode);
        }
      }
    }

    // Removed while the rows were being gathered: they must not come back.
    await _db.insertMultipleEntries(newItems.where((item) => !isBeingRemoved(item.id)).toList());

    for (var i = 0; i < itemsToDownload.length; i++) {
      final item = itemsToDownload[i];
      //No need to await file sync happens in the background
      syncFile(item, false, transcodeModel: transcodeModel);
    }

    return seriesItem;
  }
}
