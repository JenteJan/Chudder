import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/boxset_model.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/items/album_model.dart';
import 'package:fladder/models/items/artist_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/folder_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/person_model.dart';
import 'package:fladder/models/items/photos_model.dart';
import 'package:fladder/models/items/playlist_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/items/watched_state.dart';
import 'package:fladder/models/library_filter_model.dart';
import 'package:fladder/models/library_search/library_search_options.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/details_screens/album_detail_screen.dart';
import 'package:fladder/screens/details_screens/artist_detail_screen.dart';
import 'package:fladder/screens/details_screens/book_detail_screen.dart';
import 'package:fladder/screens/details_screens/channel_detail_screen.dart';
import 'package:fladder/screens/details_screens/collection_detail_screen.dart';
import 'package:fladder/screens/details_screens/details_screens.dart';
import 'package:fladder/screens/library_search/library_search_screen.dart';
import 'package:fladder/screens/photo_viewer/photo_viewer_screen.dart';
import 'package:fladder/src/video_player_helper.g.dart' show SimpleItemModel;
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/string_extensions.dart';

part 'item_base_model.mapper.dart';

@MappableClass()
class ItemBaseModel with ItemBaseModelMappable {
  final String name;
  final String id;
  final OverviewModel overview;
  final String? parentId;
  final String? playlistId;
  final ImagesData? images;
  final int? childCount;
  final double? primaryRatio;
  final UserData userData;
  final bool? canDownload;
  final bool? canDelete;
  final dto.BaseItemKind? jellyType;

  const ItemBaseModel({
    required this.name,
    required this.id,
    required this.overview,
    required this.parentId,
    required this.playlistId,
    required this.images,
    required this.childCount,
    required this.primaryRatio,
    required this.userData,
    required this.canDownload,
    required this.canDelete,
    required this.jellyType,
  });

  ItemBaseModel? setProgress(double progress) {
    return copyWith(userData: userData.copyWith(progress: progress));
  }

  Widget? subTitle(SortingOptions options) => switch (options) {
        SortingOptions.parentalRating => Row(
            children: [
              const Icon(
                IconsaxPlusBold.star_1,
                size: 14,
                color: Colors.yellowAccent,
              ),
              const SizedBox(width: 6),
              Text(overview.parentalRating?.toString() ?? "--"),
            ],
          ),
        SortingOptions.communityRating => Row(
            children: [
              const Icon(
                IconsaxPlusBold.star_1,
                size: 14,
                color: Colors.yellowAccent,
              ),
              const SizedBox(width: 6),
              Text(overview.communityRating?.toStringAsFixed(2) ?? "--"),
            ],
          ),
        _ => null,
      };

  String get title => name;

  String windowTitle(AppLocalizations l10n) => name;

  ///Used for retrieving the correct id when fetching queue
  String get streamId => id;

  ItemBaseModel get parentBaseModel => copyWith(id: parentId);

  bool get emptyShow => false;

  bool get identifiable => false;

  int? get unPlayedItemCount => userData.unPlayedItemCount;

  bool get unWatched => !userData.played && userData.progress <= 0 && userData.unPlayedItemCount == 0;

  bool get watched => userData.played;

  WatchedState watchedState(AppLocalizations l10n) => userData.played ? const Played() : const Unplayed();

  String? detailedName(AppLocalizations l10n) =>
      "$name${overview.yearAired != null || overview.productionYear != null ? " (${overview.yearAired ?? overview.productionYear})" : ""}";

  String? get subText => null;
  String? subTextShort(AppLocalizations l10n) => null;
  String? label(AppLocalizations l10n) => null;

  ImagesData? get getPosters => images;

  ImageData? get bannerImage => images?.primary ?? getPosters?.randomBackDrop ?? getPosters?.primary;

  ImageData? get tvPosterLarge => getPosters?.backDrop?.lastOrNull ?? images?.primary ?? getPosters?.primary;
  ImageData? get tvPosterSmall => getPosters?.primary ?? getPosters?.backDrop?.lastOrNull;

  ImageData? get tvPosterLogo =>
      getPosters?.logo ?? images?.logo ?? parentBaseModel.images?.logo ?? parentBaseModel.getPosters?.logo;

  bool get playAble => false;

  bool get syncAble => false;

  bool get galleryItem => false;

  MediaStreamsModel? get streamModel => null;

  String playText(AppLocalizations l10n) => l10n.play(name);

  double get progress => userData.progress;

  String playButtonLabel(AppLocalizations l10n) =>
      progress != 0 ? l10n.resume(name.maxLength()) : l10n.play(name.maxLength());

  Widget get detailScreenWidget {
    switch (this) {
      case PersonModel _:
        return PersonDetailScreen(person: Person(id: id, image: images?.primary));
      case SeasonModel _:
        return ShowDetailScreen(item: this);
      case BoxSetModel _:
        return CollectionDetailScreen(item: this);
      case FolderModel _:
      case PlaylistModel _:
      case PhotoAlbumModel _:
        return LibrarySearchScreen(parentId: [id]);
      case PhotoModel _:
        final photo = this as PhotoModel;
        return PhotoViewerScreen(
          items: [photo],
        );
      case BookModel book:
        return BookDetailScreen(item: book);
      case MovieModel _:
        return MovieDetailScreen(item: this);
      case EpisodeModel _:
        return ShowDetailScreen(item: this);
      case AlbumModel album:
        return AlbumDetailScreen(item: album);
      case ArtistModel artist:
        return ArtistDetailScreen(item: artist);
      case SeriesModel series:
        return ShowDetailScreen(item: series);
      case ChannelModel channel:
        return ChannelDetailScreen(item: channel);
      default:
        // A studio comes back as a plain item — there is no model for one — so
        // it is the server's own type that says what this is.
        if (jellyType == dto.BaseItemKind.studio) return StudioDetailScreen(item: this);
        return EmptyItem(item: this);
    }
  }

  Future<void> navigateTo(BuildContext context, {WidgetRef? ref, Object? tag}) async {
    switch (this) {
      case FolderModel _:
        LibrarySearchRoute(parentId: [id])
            .withFilter(
              CollectionType.folders.defaultFilters,
            )
            .push(context);
        break;
      case BoxSetModel _:
        context.router.push(DetailsRoute(id: id, item: this, tag: tag));
        break;
      case PlaylistModel _:
        LibrarySearchRoute(parentId: [id, "folder"])
            .withFilter(
              CollectionType.folders.defaultFilters,
            )
            .push(context);
        break;
      case PhotoAlbumModel _:
        LibrarySearchRoute(parentId: [id, "photo-album"])
            .withFilter(
              CollectionType.photos.defaultFilters,
            )
            .push(context);
        break;
      case PhotoModel _:
        final photo = this as PhotoModel;
        context.router.push(
          PhotoViewerRoute(
            items: [photo],
            selected: photo.id,
          ),
        );
        break;
      case EpisodeModel model:
        context.router.push(DetailsRoute(id: model.parentId ?? id, item: this, tag: tag));
        break;
      case SeasonModel model:
        context.router.push(DetailsRoute(id: model.seriesId, item: this, tag: tag));
        break;
      case BookModel _:
      case MovieModel _:
      case SeriesModel _:
      case PersonModel _:
      default:
        context.router.push(DetailsRoute(id: id, item: this, tag: tag));
        break;
    }
  }

  factory ItemBaseModel.fromBaseDto(dto.BaseItemDto item, Ref? ref) {
    return switch (item.type) {
      BaseItemKind.photo || BaseItemKind.video => PhotoModel.fromBaseDto(item, ref),
      BaseItemKind.photoalbum => PhotoAlbumModel.fromBaseDto(item, ref),
      BaseItemKind.folder ||
      BaseItemKind.collectionfolder ||
      BaseItemKind.aggregatefolder =>
        FolderModel.fromBaseDto(item, ref),
      BaseItemKind.episode => EpisodeModel.fromBaseDto(item, ref),
      BaseItemKind.movie => MovieModel.fromBaseDto(item, ref),
      BaseItemKind.series => SeriesModel.fromBaseDto(item, ref),
      BaseItemKind.person => PersonModel.fromBaseDto(item, ref),
      BaseItemKind.season => SeasonModel.fromBaseDto(item, ref),
      BaseItemKind.boxset => BoxSetModel.fromBaseDto(item, ref),
      BaseItemKind.book => BookModel.fromBaseDto(item, ref),
      BaseItemKind.playlist => PlaylistModel.fromBaseDto(item, ref),
      BaseItemKind.musicalbum => AlbumModel.fromBaseDto(item, ref),
      BaseItemKind.musicartist => ArtistModel.fromBaseDto(item, ref),
      BaseItemKind.audio => AudioModel.fromBaseDto(item, ref),
      BaseItemKind.tvchannel => ChannelModel.fromBaseDto(item, ref),
      _ => ItemBaseModel._fromBaseDto(item, ref)
    };
  }

  factory ItemBaseModel._fromBaseDto(dto.BaseItemDto item, Ref? ref) {
    return ItemBaseModel(
      name: item.name ?? "",
      id: item.id ?? "",
      childCount: item.childCount,
      overview: OverviewModel.fromBaseItemDto(item, ref),
      userData: UserData.fromDto(item.userData),
      parentId: item.parentId,
      playlistId: item.playlistItemId,
      images: ref != null ? ImagesData.fromBaseItem(item, ref) : null,
      primaryRatio: item.primaryImageAspectRatio,
      canDelete: item.canDelete,
      canDownload: item.canDownload,
      jellyType: item.type,
    );
  }

  SimpleItemModel toSimpleItem(BuildContext? context) {
    return SimpleItemModel(
      id: id,
      title: title,
      subTitle: context != null ? label(context.localized) : null,
      overview: overview.summary,
      logoUrl: getPosters?.logo?.path ?? images?.logo?.path,
      primaryPoster: images?.primary?.path ?? getPosters?.primary?.path ?? "",
    );
  }

  /// A studio has no model of its own - it arrives as a plain item, so [type]
  /// can only call it a base type and the server's own kind is the one thing
  /// that says what it really is.
  bool get isStudio => jellyType == dto.BaseItemKind.studio;

  FladderItemType get type => switch (this) {
        MovieModel _ => FladderItemType.movie,
        SeriesModel _ => FladderItemType.series,
        SeasonModel _ => FladderItemType.season,
        PhotoAlbumModel _ => FladderItemType.photoAlbum,
        PhotoModel model => model.internalType,
        EpisodeModel _ => FladderItemType.episode,
        // A person had no case at all, so every actor fell through to the base
        // type: a folder icon over a flat card, and no way for anything reading
        // the type to tell an actor from an unknown item.
        PersonModel _ => FladderItemType.person,
        BookModel _ => FladderItemType.book,
        PlaylistModel _ => FladderItemType.playlist,
        // Without this a box set fell through to the base type, whose 0.8 made a
        // flat card out of artwork that is a poster like everything it holds.
        BoxSetModel _ => FladderItemType.boxset,
        FolderModel _ => FladderItemType.folder,
        AlbumModel _ => FladderItemType.musicAlbum,
        ArtistModel _ => FladderItemType.musicArtist,
        AudioModel _ => FladderItemType.audio,
        ItemBaseModel _ => FladderItemType.baseType,
      };

  /// Two items are the same item when they share an id.
  ///
  /// Takes an [Object], as == must. It was declared `covariant ItemBaseModel`,
  /// which does not restrict who may call it - it only inserts a cast, so any
  /// comparison against something that is not an item threw where it should
  /// have answered false. dart_mappable's generated `copyWith` compares every
  /// argument against a sentinel of its own private type, so that cast brought
  /// down any copyWith of a model holding an item - which on a show is the
  /// episode the page is currently about.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ItemBaseModel && other.id == id;
  }

  @override
  int get hashCode {
    return id.hashCode;
  }
}

// Currently supported types
enum FladderItemType {
  baseType(
    icon: IconsaxPlusLinear.folder_2,
    selectedicon: IconsaxPlusBold.folder_2,
  ),
  audio(
    icon: IconsaxPlusLinear.music,
    selectedicon: IconsaxPlusBold.music,
  ),
  musicAlbum(
    icon: IconsaxPlusLinear.music_dashboard,
    selectedicon: IconsaxPlusBold.music_dashboard,
  ),
  musicArtist(
    icon: IconsaxPlusLinear.music,
    selectedicon: IconsaxPlusBold.music,
  ),
  musicVideo(
    icon: IconsaxPlusLinear.music,
    selectedicon: IconsaxPlusBold.music,
  ),
  collectionFolder(
    icon: IconsaxPlusLinear.music,
    selectedicon: IconsaxPlusBold.music,
  ),
  video(
    icon: IconsaxPlusLinear.video,
    selectedicon: IconsaxPlusBold.video,
  ),
  movie(
    icon: IconsaxPlusLinear.video_horizontal,
    selectedicon: IconsaxPlusBold.video_horizontal,
  ),
  series(
    icon: IconsaxPlusLinear.video_vertical,
    selectedicon: IconsaxPlusBold.video_vertical,
  ),
  season(
    icon: IconsaxPlusLinear.video_vertical,
    selectedicon: IconsaxPlusBold.video_vertical,
  ),
  episode(
    icon: IconsaxPlusLinear.video_vertical,
    selectedicon: IconsaxPlusBold.video_vertical,
  ),
  photo(
    icon: IconsaxPlusLinear.picture_frame,
    selectedicon: IconsaxPlusBold.picture_frame,
  ),
  person(
    icon: IconsaxPlusLinear.user,
    selectedicon: IconsaxPlusBold.user,
  ),
  photoAlbum(
    icon: IconsaxPlusLinear.gallery,
    selectedicon: IconsaxPlusBold.gallery,
  ),
  folder(
    icon: IconsaxPlusLinear.folder,
    selectedicon: IconsaxPlusBold.folder,
  ),
  boxset(
    icon: IconsaxPlusLinear.bookmark,
    selectedicon: IconsaxPlusBold.bookmark,
  ),
  playlist(
    icon: IconsaxPlusLinear.archive_book,
    selectedicon: IconsaxPlusBold.archive_book,
  ),
  book(
    icon: IconsaxPlusLinear.book,
    selectedicon: IconsaxPlusBold.book,
  ),
  tvchannel(
    icon: IconsaxPlusLinear.slider_horizontal,
    selectedicon: IconsaxPlusBold.slider_horizontal,
  );

  const FladderItemType({required this.icon, required this.selectedicon});

  double get aspectRatio => switch (this) {
        FladderItemType.video => 0.8,
        FladderItemType.photo => 0.8,
        FladderItemType.photoAlbum => 0.8,
        FladderItemType.folder => 0.8,
        FladderItemType.musicAlbum => 0.8,
        FladderItemType.musicArtist => 0.8,
        FladderItemType.audio => 0.8,
        FladderItemType.baseType => 0.8,
        FladderItemType.tvchannel => 0.8,
        _ => 0.55,
      };

  /// The shape of the artwork itself. [aspectRatio] is the shape of a whole
  /// poster cell - image plus the title line under it - so handing it to a bare
  /// image squeezes the artwork into something far narrower than the poster
  /// actually is.
  double get imageAspectRatio => switch (this) {
        FladderItemType.episode => 16 / 9,
        FladderItemType.video ||
        FladderItemType.photo ||
        FladderItemType.photoAlbum ||
        FladderItemType.folder ||
        FladderItemType.collectionFolder ||
        FladderItemType.musicAlbum ||
        FladderItemType.musicArtist ||
        FladderItemType.audio ||
        FladderItemType.playlist ||
        FladderItemType.baseType ||
        FladderItemType.tvchannel =>
          1.0,
        _ => 2 / 3,
      };

  static Set<FladderItemType> get playable => {
        FladderItemType.series,
        FladderItemType.episode,
        FladderItemType.season,
        FladderItemType.movie,
        FladderItemType.musicVideo,
        FladderItemType.tvchannel,
      };

  static Set<FladderItemType> get musicPlayable => {
        FladderItemType.audio,
        FladderItemType.musicAlbum,
        FladderItemType.musicArtist,
      };

  static Set<FladderItemType> get galleryItem => {
        FladderItemType.photo,
        FladderItemType.video,
      };

  String label(AppLocalizations l10n, {int count = 1}) => switch (this) {
        FladderItemType.baseType => l10n.mediaTypeBase,
        FladderItemType.audio => l10n.audio(count),
        FladderItemType.collectionFolder => l10n.collectionFolder(count),
        FladderItemType.musicAlbum => l10n.musicAlbum(count),
        FladderItemType.musicArtist => l10n.mediaTypeArtists(count),
        FladderItemType.musicVideo => l10n.mediaTypeMusicVideo(count),
        FladderItemType.video => l10n.video(count),
        FladderItemType.movie => l10n.mediaTypeMovie(count),
        FladderItemType.series => l10n.mediaTypeSeries(count),
        FladderItemType.season => l10n.mediaTypeSeason(count),
        FladderItemType.episode => l10n.mediaTypeEpisode(count),
        FladderItemType.photo => l10n.mediaTypePhoto(count),
        FladderItemType.person => l10n.mediaTypePerson(count),
        FladderItemType.photoAlbum => l10n.mediaTypePhotoAlbum(count),
        FladderItemType.folder => l10n.mediaTypeFolder(count),
        FladderItemType.boxset => l10n.mediaTypeBoxset(count),
        FladderItemType.playlist => l10n.mediaTypePlaylist(count),
        FladderItemType.book => l10n.mediaTypeBook(count),
        FladderItemType.tvchannel => l10n.mediaTypeTV(count),
      };

  Set<BaseItemKind> get dtoKind => switch (this) {
        FladderItemType.baseType => {BaseItemKind.userrootfolder},
        FladderItemType.audio => {BaseItemKind.audio},
        FladderItemType.collectionFolder => {BaseItemKind.collectionfolder},
        FladderItemType.musicAlbum => {BaseItemKind.musicalbum},
        FladderItemType.musicArtist => {BaseItemKind.musicartist},
        FladderItemType.musicVideo => {BaseItemKind.musicvideo},
        FladderItemType.video => {BaseItemKind.video},
        FladderItemType.movie => {BaseItemKind.movie},
        FladderItemType.series => {BaseItemKind.series},
        FladderItemType.season => {BaseItemKind.season},
        FladderItemType.episode => {BaseItemKind.episode},
        FladderItemType.photo => {BaseItemKind.photo},
        FladderItemType.person => {
            BaseItemKind.person,
            BaseItemKind.musicartist,
          },
        FladderItemType.photoAlbum => {BaseItemKind.photoalbum},
        FladderItemType.folder => {BaseItemKind.folder},
        FladderItemType.boxset => {BaseItemKind.boxset},
        FladderItemType.playlist => {BaseItemKind.playlist},
        FladderItemType.book => {BaseItemKind.book},
        FladderItemType.tvchannel => {BaseItemKind.tvchannel},
      };

  final IconData icon;
  final IconData selectedicon;
}
