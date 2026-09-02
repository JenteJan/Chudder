// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'client_settings_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ClientSettingsModel implements DiagnosticableTreeMixin {
  String? get syncPath;
  TranscodeDownloadModel get transcodeDownloadModel;
  TranscodeMusicDownloadModel get transcodeMusicDownloadModel;
  Vector2 get position;
  Vector2 get size;
  Duration? get timeOut;
  Duration? get nextUpDateCutoff;
  Duration get updateNotificationsInterval;
  ThemeMode get themeMode;
  ColorThemes? get themeColor;

  /// Collapses a two-colour preset down to its primary. The preset itself is
  /// left alone, so turning this back off restores the pair.
  bool get singleColorTheme;
  bool get deriveColorsFromItem;
  bool get dynamicPosterColors;
  bool get amoledBlack;
  bool get blurPlaceHolders;

  /// How much disk and memory artwork is allowed to occupy. The old
  /// behaviour is [ImageCacheSize.small]; the default is deliberately larger,
  /// because the small one re-fetched pictures faster than you could scroll
  /// back to them.
  ImageCacheSize get imageCacheSize;
  bool get blurUpcomingEpisodes;
  @LocaleConvert()
  Locale? get selectedLocale;
  bool get enableMediaKeys;
  double get posterSize;
  bool get pinchPosterZoom;
  bool get mouseDragSupport;
  bool get requireWifi;

  /// Whether pressing download asks for the quality first. Cleared by the
  /// "always use these settings" box in that dialog, and restorable from
  /// Settings so the choice is not a one-way door.
  bool get askDownloadQuality;
  bool get expandSideBar;
  bool get showAllCollectionTypes;
  int get maxConcurrentDownloads;
  DynamicSchemeVariant get schemeVariant;
  BackgroundType get backgroundImage;
  bool get enableBlurEffects;
  bool get checkForUpdates;
  bool get usePosterForLibrary;
  bool get useSystemIME;
  bool get useTVExpandedLayout;
  bool get forceLeanBackMode;
  String? get lastViewedUpdate;
  String? get castServerUrl;
  int? get libraryPageSize;
  Map<GlobalHotKeys, KeyCombination> get shortcuts;

  /// Per-show answer to "favorite the episode or the whole show?" —
  /// showId → true when the user chose the show, false for the episode.
  /// Asked once per show, remembered here.
  Map<String, bool> get episodeFavoritePrefersShow;

  /// Backdrops taken out of rotation on this device, by server image tag.
  /// The file stays on the server; the app just never picks it as a
  /// background. A per-device choice because Jellyfin has nowhere to keep
  /// one per user.
  Set<String> get hiddenBackdropTags;

  /// Create a copy of ClientSettingsModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ClientSettingsModelCopyWith<ClientSettingsModel> get copyWith =>
      _$ClientSettingsModelCopyWithImpl<ClientSettingsModel>(
          this as ClientSettingsModel, _$identity);

  /// Serializes this ClientSettingsModel to a JSON map.
  Map<String, dynamic> toJson();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
      ..add(DiagnosticsProperty('type', 'ClientSettingsModel'))
      ..add(DiagnosticsProperty('syncPath', syncPath))
      ..add(
          DiagnosticsProperty('transcodeDownloadModel', transcodeDownloadModel))
      ..add(DiagnosticsProperty(
          'transcodeMusicDownloadModel', transcodeMusicDownloadModel))
      ..add(DiagnosticsProperty('position', position))
      ..add(DiagnosticsProperty('size', size))
      ..add(DiagnosticsProperty('timeOut', timeOut))
      ..add(DiagnosticsProperty('nextUpDateCutoff', nextUpDateCutoff))
      ..add(DiagnosticsProperty(
          'updateNotificationsInterval', updateNotificationsInterval))
      ..add(DiagnosticsProperty('themeMode', themeMode))
      ..add(DiagnosticsProperty('themeColor', themeColor))
      ..add(DiagnosticsProperty('singleColorTheme', singleColorTheme))
      ..add(DiagnosticsProperty('deriveColorsFromItem', deriveColorsFromItem))
      ..add(DiagnosticsProperty('dynamicPosterColors', dynamicPosterColors))
      ..add(DiagnosticsProperty('amoledBlack', amoledBlack))
      ..add(DiagnosticsProperty('blurPlaceHolders', blurPlaceHolders))
      ..add(DiagnosticsProperty('imageCacheSize', imageCacheSize))
      ..add(DiagnosticsProperty('blurUpcomingEpisodes', blurUpcomingEpisodes))
      ..add(DiagnosticsProperty('selectedLocale', selectedLocale))
      ..add(DiagnosticsProperty('enableMediaKeys', enableMediaKeys))
      ..add(DiagnosticsProperty('posterSize', posterSize))
      ..add(DiagnosticsProperty('pinchPosterZoom', pinchPosterZoom))
      ..add(DiagnosticsProperty('mouseDragSupport', mouseDragSupport))
      ..add(DiagnosticsProperty('requireWifi', requireWifi))
      ..add(DiagnosticsProperty('askDownloadQuality', askDownloadQuality))
      ..add(DiagnosticsProperty('expandSideBar', expandSideBar))
      ..add(
          DiagnosticsProperty('showAllCollectionTypes', showAllCollectionTypes))
      ..add(
          DiagnosticsProperty('maxConcurrentDownloads', maxConcurrentDownloads))
      ..add(DiagnosticsProperty('schemeVariant', schemeVariant))
      ..add(DiagnosticsProperty('backgroundImage', backgroundImage))
      ..add(DiagnosticsProperty('enableBlurEffects', enableBlurEffects))
      ..add(DiagnosticsProperty('checkForUpdates', checkForUpdates))
      ..add(DiagnosticsProperty('usePosterForLibrary', usePosterForLibrary))
      ..add(DiagnosticsProperty('useSystemIME', useSystemIME))
      ..add(DiagnosticsProperty('useTVExpandedLayout', useTVExpandedLayout))
      ..add(DiagnosticsProperty('forceLeanBackMode', forceLeanBackMode))
      ..add(DiagnosticsProperty('lastViewedUpdate', lastViewedUpdate))
      ..add(DiagnosticsProperty('castServerUrl', castServerUrl))
      ..add(DiagnosticsProperty('libraryPageSize', libraryPageSize))
      ..add(DiagnosticsProperty('shortcuts', shortcuts))
      ..add(DiagnosticsProperty(
          'episodeFavoritePrefersShow', episodeFavoritePrefersShow))
      ..add(DiagnosticsProperty('hiddenBackdropTags', hiddenBackdropTags));
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'ClientSettingsModel(syncPath: $syncPath, transcodeDownloadModel: $transcodeDownloadModel, transcodeMusicDownloadModel: $transcodeMusicDownloadModel, position: $position, size: $size, timeOut: $timeOut, nextUpDateCutoff: $nextUpDateCutoff, updateNotificationsInterval: $updateNotificationsInterval, themeMode: $themeMode, themeColor: $themeColor, singleColorTheme: $singleColorTheme, deriveColorsFromItem: $deriveColorsFromItem, dynamicPosterColors: $dynamicPosterColors, amoledBlack: $amoledBlack, blurPlaceHolders: $blurPlaceHolders, imageCacheSize: $imageCacheSize, blurUpcomingEpisodes: $blurUpcomingEpisodes, selectedLocale: $selectedLocale, enableMediaKeys: $enableMediaKeys, posterSize: $posterSize, pinchPosterZoom: $pinchPosterZoom, mouseDragSupport: $mouseDragSupport, requireWifi: $requireWifi, askDownloadQuality: $askDownloadQuality, expandSideBar: $expandSideBar, showAllCollectionTypes: $showAllCollectionTypes, maxConcurrentDownloads: $maxConcurrentDownloads, schemeVariant: $schemeVariant, backgroundImage: $backgroundImage, enableBlurEffects: $enableBlurEffects, checkForUpdates: $checkForUpdates, usePosterForLibrary: $usePosterForLibrary, useSystemIME: $useSystemIME, useTVExpandedLayout: $useTVExpandedLayout, forceLeanBackMode: $forceLeanBackMode, lastViewedUpdate: $lastViewedUpdate, castServerUrl: $castServerUrl, libraryPageSize: $libraryPageSize, shortcuts: $shortcuts, episodeFavoritePrefersShow: $episodeFavoritePrefersShow, hiddenBackdropTags: $hiddenBackdropTags)';
  }
}

/// @nodoc
abstract mixin class $ClientSettingsModelCopyWith<$Res> {
  factory $ClientSettingsModelCopyWith(
          ClientSettingsModel value, $Res Function(ClientSettingsModel) _then) =
      _$ClientSettingsModelCopyWithImpl;
  @useResult
  $Res call(
      {String? syncPath,
      TranscodeDownloadModel transcodeDownloadModel,
      TranscodeMusicDownloadModel transcodeMusicDownloadModel,
      Vector2 position,
      Vector2 size,
      Duration? timeOut,
      Duration? nextUpDateCutoff,
      Duration updateNotificationsInterval,
      ThemeMode themeMode,
      ColorThemes? themeColor,
      bool singleColorTheme,
      bool deriveColorsFromItem,
      bool dynamicPosterColors,
      bool amoledBlack,
      bool blurPlaceHolders,
      ImageCacheSize imageCacheSize,
      bool blurUpcomingEpisodes,
      @LocaleConvert() Locale? selectedLocale,
      bool enableMediaKeys,
      double posterSize,
      bool pinchPosterZoom,
      bool mouseDragSupport,
      bool requireWifi,
      bool askDownloadQuality,
      bool expandSideBar,
      bool showAllCollectionTypes,
      int maxConcurrentDownloads,
      DynamicSchemeVariant schemeVariant,
      BackgroundType backgroundImage,
      bool enableBlurEffects,
      bool checkForUpdates,
      bool usePosterForLibrary,
      bool useSystemIME,
      bool useTVExpandedLayout,
      bool forceLeanBackMode,
      String? lastViewedUpdate,
      String? castServerUrl,
      int? libraryPageSize,
      Map<GlobalHotKeys, KeyCombination> shortcuts,
      Map<String, bool> episodeFavoritePrefersShow,
      Set<String> hiddenBackdropTags});

  $TranscodeDownloadModelCopyWith<$Res> get transcodeDownloadModel;
}

/// @nodoc
class _$ClientSettingsModelCopyWithImpl<$Res>
    implements $ClientSettingsModelCopyWith<$Res> {
  _$ClientSettingsModelCopyWithImpl(this._self, this._then);

  final ClientSettingsModel _self;
  final $Res Function(ClientSettingsModel) _then;

  /// Create a copy of ClientSettingsModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? syncPath = freezed,
    Object? transcodeDownloadModel = null,
    Object? transcodeMusicDownloadModel = null,
    Object? position = null,
    Object? size = null,
    Object? timeOut = freezed,
    Object? nextUpDateCutoff = freezed,
    Object? updateNotificationsInterval = null,
    Object? themeMode = null,
    Object? themeColor = freezed,
    Object? singleColorTheme = null,
    Object? deriveColorsFromItem = null,
    Object? dynamicPosterColors = null,
    Object? amoledBlack = null,
    Object? blurPlaceHolders = null,
    Object? imageCacheSize = null,
    Object? blurUpcomingEpisodes = null,
    Object? selectedLocale = freezed,
    Object? enableMediaKeys = null,
    Object? posterSize = null,
    Object? pinchPosterZoom = null,
    Object? mouseDragSupport = null,
    Object? requireWifi = null,
    Object? askDownloadQuality = null,
    Object? expandSideBar = null,
    Object? showAllCollectionTypes = null,
    Object? maxConcurrentDownloads = null,
    Object? schemeVariant = null,
    Object? backgroundImage = null,
    Object? enableBlurEffects = null,
    Object? checkForUpdates = null,
    Object? usePosterForLibrary = null,
    Object? useSystemIME = null,
    Object? useTVExpandedLayout = null,
    Object? forceLeanBackMode = null,
    Object? lastViewedUpdate = freezed,
    Object? castServerUrl = freezed,
    Object? libraryPageSize = freezed,
    Object? shortcuts = null,
    Object? episodeFavoritePrefersShow = null,
    Object? hiddenBackdropTags = null,
  }) {
    return _then(_self.copyWith(
      syncPath: freezed == syncPath
          ? _self.syncPath
          : syncPath // ignore: cast_nullable_to_non_nullable
              as String?,
      transcodeDownloadModel: null == transcodeDownloadModel
          ? _self.transcodeDownloadModel
          : transcodeDownloadModel // ignore: cast_nullable_to_non_nullable
              as TranscodeDownloadModel,
      transcodeMusicDownloadModel: null == transcodeMusicDownloadModel
          ? _self.transcodeMusicDownloadModel
          : transcodeMusicDownloadModel // ignore: cast_nullable_to_non_nullable
              as TranscodeMusicDownloadModel,
      position: null == position
          ? _self.position
          : position // ignore: cast_nullable_to_non_nullable
              as Vector2,
      size: null == size
          ? _self.size
          : size // ignore: cast_nullable_to_non_nullable
              as Vector2,
      timeOut: freezed == timeOut
          ? _self.timeOut
          : timeOut // ignore: cast_nullable_to_non_nullable
              as Duration?,
      nextUpDateCutoff: freezed == nextUpDateCutoff
          ? _self.nextUpDateCutoff
          : nextUpDateCutoff // ignore: cast_nullable_to_non_nullable
              as Duration?,
      updateNotificationsInterval: null == updateNotificationsInterval
          ? _self.updateNotificationsInterval
          : updateNotificationsInterval // ignore: cast_nullable_to_non_nullable
              as Duration,
      themeMode: null == themeMode
          ? _self.themeMode
          : themeMode // ignore: cast_nullable_to_non_nullable
              as ThemeMode,
      themeColor: freezed == themeColor
          ? _self.themeColor
          : themeColor // ignore: cast_nullable_to_non_nullable
              as ColorThemes?,
      singleColorTheme: null == singleColorTheme
          ? _self.singleColorTheme
          : singleColorTheme // ignore: cast_nullable_to_non_nullable
              as bool,
      deriveColorsFromItem: null == deriveColorsFromItem
          ? _self.deriveColorsFromItem
          : deriveColorsFromItem // ignore: cast_nullable_to_non_nullable
              as bool,
      dynamicPosterColors: null == dynamicPosterColors
          ? _self.dynamicPosterColors
          : dynamicPosterColors // ignore: cast_nullable_to_non_nullable
              as bool,
      amoledBlack: null == amoledBlack
          ? _self.amoledBlack
          : amoledBlack // ignore: cast_nullable_to_non_nullable
              as bool,
      blurPlaceHolders: null == blurPlaceHolders
          ? _self.blurPlaceHolders
          : blurPlaceHolders // ignore: cast_nullable_to_non_nullable
              as bool,
      imageCacheSize: null == imageCacheSize
          ? _self.imageCacheSize
          : imageCacheSize // ignore: cast_nullable_to_non_nullable
              as ImageCacheSize,
      blurUpcomingEpisodes: null == blurUpcomingEpisodes
          ? _self.blurUpcomingEpisodes
          : blurUpcomingEpisodes // ignore: cast_nullable_to_non_nullable
              as bool,
      selectedLocale: freezed == selectedLocale
          ? _self.selectedLocale
          : selectedLocale // ignore: cast_nullable_to_non_nullable
              as Locale?,
      enableMediaKeys: null == enableMediaKeys
          ? _self.enableMediaKeys
          : enableMediaKeys // ignore: cast_nullable_to_non_nullable
              as bool,
      posterSize: null == posterSize
          ? _self.posterSize
          : posterSize // ignore: cast_nullable_to_non_nullable
              as double,
      pinchPosterZoom: null == pinchPosterZoom
          ? _self.pinchPosterZoom
          : pinchPosterZoom // ignore: cast_nullable_to_non_nullable
              as bool,
      mouseDragSupport: null == mouseDragSupport
          ? _self.mouseDragSupport
          : mouseDragSupport // ignore: cast_nullable_to_non_nullable
              as bool,
      requireWifi: null == requireWifi
          ? _self.requireWifi
          : requireWifi // ignore: cast_nullable_to_non_nullable
              as bool,
      askDownloadQuality: null == askDownloadQuality
          ? _self.askDownloadQuality
          : askDownloadQuality // ignore: cast_nullable_to_non_nullable
              as bool,
      expandSideBar: null == expandSideBar
          ? _self.expandSideBar
          : expandSideBar // ignore: cast_nullable_to_non_nullable
              as bool,
      showAllCollectionTypes: null == showAllCollectionTypes
          ? _self.showAllCollectionTypes
          : showAllCollectionTypes // ignore: cast_nullable_to_non_nullable
              as bool,
      maxConcurrentDownloads: null == maxConcurrentDownloads
          ? _self.maxConcurrentDownloads
          : maxConcurrentDownloads // ignore: cast_nullable_to_non_nullable
              as int,
      schemeVariant: null == schemeVariant
          ? _self.schemeVariant
          : schemeVariant // ignore: cast_nullable_to_non_nullable
              as DynamicSchemeVariant,
      backgroundImage: null == backgroundImage
          ? _self.backgroundImage
          : backgroundImage // ignore: cast_nullable_to_non_nullable
              as BackgroundType,
      enableBlurEffects: null == enableBlurEffects
          ? _self.enableBlurEffects
          : enableBlurEffects // ignore: cast_nullable_to_non_nullable
              as bool,
      checkForUpdates: null == checkForUpdates
          ? _self.checkForUpdates
          : checkForUpdates // ignore: cast_nullable_to_non_nullable
              as bool,
      usePosterForLibrary: null == usePosterForLibrary
          ? _self.usePosterForLibrary
          : usePosterForLibrary // ignore: cast_nullable_to_non_nullable
              as bool,
      useSystemIME: null == useSystemIME
          ? _self.useSystemIME
          : useSystemIME // ignore: cast_nullable_to_non_nullable
              as bool,
      useTVExpandedLayout: null == useTVExpandedLayout
          ? _self.useTVExpandedLayout
          : useTVExpandedLayout // ignore: cast_nullable_to_non_nullable
              as bool,
      forceLeanBackMode: null == forceLeanBackMode
          ? _self.forceLeanBackMode
          : forceLeanBackMode // ignore: cast_nullable_to_non_nullable
              as bool,
      lastViewedUpdate: freezed == lastViewedUpdate
          ? _self.lastViewedUpdate
          : lastViewedUpdate // ignore: cast_nullable_to_non_nullable
              as String?,
      castServerUrl: freezed == castServerUrl
          ? _self.castServerUrl
          : castServerUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      libraryPageSize: freezed == libraryPageSize
          ? _self.libraryPageSize
          : libraryPageSize // ignore: cast_nullable_to_non_nullable
              as int?,
      shortcuts: null == shortcuts
          ? _self.shortcuts
          : shortcuts // ignore: cast_nullable_to_non_nullable
              as Map<GlobalHotKeys, KeyCombination>,
      episodeFavoritePrefersShow: null == episodeFavoritePrefersShow
          ? _self.episodeFavoritePrefersShow
          : episodeFavoritePrefersShow // ignore: cast_nullable_to_non_nullable
              as Map<String, bool>,
      hiddenBackdropTags: null == hiddenBackdropTags
          ? _self.hiddenBackdropTags
          : hiddenBackdropTags // ignore: cast_nullable_to_non_nullable
              as Set<String>,
    ));
  }

  /// Create a copy of ClientSettingsModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $TranscodeDownloadModelCopyWith<$Res> get transcodeDownloadModel {
    return $TranscodeDownloadModelCopyWith<$Res>(_self.transcodeDownloadModel,
        (value) {
      return _then(_self.copyWith(transcodeDownloadModel: value));
    });
  }
}

/// Adds pattern-matching-related methods to [ClientSettingsModel].
extension ClientSettingsModelPatterns on ClientSettingsModel {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_ClientSettingsModel value)? internal,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ClientSettingsModel() when internal != null:
        return internal(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_ClientSettingsModel value) internal,
  }) {
    final _that = this;
    switch (_that) {
      case _ClientSettingsModel():
        return internal(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_ClientSettingsModel value)? internal,
  }) {
    final _that = this;
    switch (_that) {
      case _ClientSettingsModel() when internal != null:
        return internal(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String? syncPath,
            TranscodeDownloadModel transcodeDownloadModel,
            TranscodeMusicDownloadModel transcodeMusicDownloadModel,
            Vector2 position,
            Vector2 size,
            Duration? timeOut,
            Duration? nextUpDateCutoff,
            Duration updateNotificationsInterval,
            ThemeMode themeMode,
            ColorThemes? themeColor,
            bool singleColorTheme,
            bool deriveColorsFromItem,
            bool dynamicPosterColors,
            bool amoledBlack,
            bool blurPlaceHolders,
            ImageCacheSize imageCacheSize,
            bool blurUpcomingEpisodes,
            @LocaleConvert() Locale? selectedLocale,
            bool enableMediaKeys,
            double posterSize,
            bool pinchPosterZoom,
            bool mouseDragSupport,
            bool requireWifi,
            bool askDownloadQuality,
            bool expandSideBar,
            bool showAllCollectionTypes,
            int maxConcurrentDownloads,
            DynamicSchemeVariant schemeVariant,
            BackgroundType backgroundImage,
            bool enableBlurEffects,
            bool checkForUpdates,
            bool usePosterForLibrary,
            bool useSystemIME,
            bool useTVExpandedLayout,
            bool forceLeanBackMode,
            String? lastViewedUpdate,
            String? castServerUrl,
            int? libraryPageSize,
            Map<GlobalHotKeys, KeyCombination> shortcuts,
            Map<String, bool> episodeFavoritePrefersShow,
            Set<String> hiddenBackdropTags)?
        internal,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ClientSettingsModel() when internal != null:
        return internal(
            _that.syncPath,
            _that.transcodeDownloadModel,
            _that.transcodeMusicDownloadModel,
            _that.position,
            _that.size,
            _that.timeOut,
            _that.nextUpDateCutoff,
            _that.updateNotificationsInterval,
            _that.themeMode,
            _that.themeColor,
            _that.singleColorTheme,
            _that.deriveColorsFromItem,
            _that.dynamicPosterColors,
            _that.amoledBlack,
            _that.blurPlaceHolders,
            _that.imageCacheSize,
            _that.blurUpcomingEpisodes,
            _that.selectedLocale,
            _that.enableMediaKeys,
            _that.posterSize,
            _that.pinchPosterZoom,
            _that.mouseDragSupport,
            _that.requireWifi,
            _that.askDownloadQuality,
            _that.expandSideBar,
            _that.showAllCollectionTypes,
            _that.maxConcurrentDownloads,
            _that.schemeVariant,
            _that.backgroundImage,
            _that.enableBlurEffects,
            _that.checkForUpdates,
            _that.usePosterForLibrary,
            _that.useSystemIME,
            _that.useTVExpandedLayout,
            _that.forceLeanBackMode,
            _that.lastViewedUpdate,
            _that.castServerUrl,
            _that.libraryPageSize,
            _that.shortcuts,
            _that.episodeFavoritePrefersShow,
            _that.hiddenBackdropTags);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String? syncPath,
            TranscodeDownloadModel transcodeDownloadModel,
            TranscodeMusicDownloadModel transcodeMusicDownloadModel,
            Vector2 position,
            Vector2 size,
            Duration? timeOut,
            Duration? nextUpDateCutoff,
            Duration updateNotificationsInterval,
            ThemeMode themeMode,
            ColorThemes? themeColor,
            bool singleColorTheme,
            bool deriveColorsFromItem,
            bool dynamicPosterColors,
            bool amoledBlack,
            bool blurPlaceHolders,
            ImageCacheSize imageCacheSize,
            bool blurUpcomingEpisodes,
            @LocaleConvert() Locale? selectedLocale,
            bool enableMediaKeys,
            double posterSize,
            bool pinchPosterZoom,
            bool mouseDragSupport,
            bool requireWifi,
            bool askDownloadQuality,
            bool expandSideBar,
            bool showAllCollectionTypes,
            int maxConcurrentDownloads,
            DynamicSchemeVariant schemeVariant,
            BackgroundType backgroundImage,
            bool enableBlurEffects,
            bool checkForUpdates,
            bool usePosterForLibrary,
            bool useSystemIME,
            bool useTVExpandedLayout,
            bool forceLeanBackMode,
            String? lastViewedUpdate,
            String? castServerUrl,
            int? libraryPageSize,
            Map<GlobalHotKeys, KeyCombination> shortcuts,
            Map<String, bool> episodeFavoritePrefersShow,
            Set<String> hiddenBackdropTags)
        internal,
  }) {
    final _that = this;
    switch (_that) {
      case _ClientSettingsModel():
        return internal(
            _that.syncPath,
            _that.transcodeDownloadModel,
            _that.transcodeMusicDownloadModel,
            _that.position,
            _that.size,
            _that.timeOut,
            _that.nextUpDateCutoff,
            _that.updateNotificationsInterval,
            _that.themeMode,
            _that.themeColor,
            _that.singleColorTheme,
            _that.deriveColorsFromItem,
            _that.dynamicPosterColors,
            _that.amoledBlack,
            _that.blurPlaceHolders,
            _that.imageCacheSize,
            _that.blurUpcomingEpisodes,
            _that.selectedLocale,
            _that.enableMediaKeys,
            _that.posterSize,
            _that.pinchPosterZoom,
            _that.mouseDragSupport,
            _that.requireWifi,
            _that.askDownloadQuality,
            _that.expandSideBar,
            _that.showAllCollectionTypes,
            _that.maxConcurrentDownloads,
            _that.schemeVariant,
            _that.backgroundImage,
            _that.enableBlurEffects,
            _that.checkForUpdates,
            _that.usePosterForLibrary,
            _that.useSystemIME,
            _that.useTVExpandedLayout,
            _that.forceLeanBackMode,
            _that.lastViewedUpdate,
            _that.castServerUrl,
            _that.libraryPageSize,
            _that.shortcuts,
            _that.episodeFavoritePrefersShow,
            _that.hiddenBackdropTags);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String? syncPath,
            TranscodeDownloadModel transcodeDownloadModel,
            TranscodeMusicDownloadModel transcodeMusicDownloadModel,
            Vector2 position,
            Vector2 size,
            Duration? timeOut,
            Duration? nextUpDateCutoff,
            Duration updateNotificationsInterval,
            ThemeMode themeMode,
            ColorThemes? themeColor,
            bool singleColorTheme,
            bool deriveColorsFromItem,
            bool dynamicPosterColors,
            bool amoledBlack,
            bool blurPlaceHolders,
            ImageCacheSize imageCacheSize,
            bool blurUpcomingEpisodes,
            @LocaleConvert() Locale? selectedLocale,
            bool enableMediaKeys,
            double posterSize,
            bool pinchPosterZoom,
            bool mouseDragSupport,
            bool requireWifi,
            bool askDownloadQuality,
            bool expandSideBar,
            bool showAllCollectionTypes,
            int maxConcurrentDownloads,
            DynamicSchemeVariant schemeVariant,
            BackgroundType backgroundImage,
            bool enableBlurEffects,
            bool checkForUpdates,
            bool usePosterForLibrary,
            bool useSystemIME,
            bool useTVExpandedLayout,
            bool forceLeanBackMode,
            String? lastViewedUpdate,
            String? castServerUrl,
            int? libraryPageSize,
            Map<GlobalHotKeys, KeyCombination> shortcuts,
            Map<String, bool> episodeFavoritePrefersShow,
            Set<String> hiddenBackdropTags)?
        internal,
  }) {
    final _that = this;
    switch (_that) {
      case _ClientSettingsModel() when internal != null:
        return internal(
            _that.syncPath,
            _that.transcodeDownloadModel,
            _that.transcodeMusicDownloadModel,
            _that.position,
            _that.size,
            _that.timeOut,
            _that.nextUpDateCutoff,
            _that.updateNotificationsInterval,
            _that.themeMode,
            _that.themeColor,
            _that.singleColorTheme,
            _that.deriveColorsFromItem,
            _that.dynamicPosterColors,
            _that.amoledBlack,
            _that.blurPlaceHolders,
            _that.imageCacheSize,
            _that.blurUpcomingEpisodes,
            _that.selectedLocale,
            _that.enableMediaKeys,
            _that.posterSize,
            _that.pinchPosterZoom,
            _that.mouseDragSupport,
            _that.requireWifi,
            _that.askDownloadQuality,
            _that.expandSideBar,
            _that.showAllCollectionTypes,
            _that.maxConcurrentDownloads,
            _that.schemeVariant,
            _that.backgroundImage,
            _that.enableBlurEffects,
            _that.checkForUpdates,
            _that.usePosterForLibrary,
            _that.useSystemIME,
            _that.useTVExpandedLayout,
            _that.forceLeanBackMode,
            _that.lastViewedUpdate,
            _that.castServerUrl,
            _that.libraryPageSize,
            _that.shortcuts,
            _that.episodeFavoritePrefersShow,
            _that.hiddenBackdropTags);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _ClientSettingsModel extends ClientSettingsModel
    with DiagnosticableTreeMixin {
  _ClientSettingsModel(
      {this.syncPath,
      required this.transcodeDownloadModel,
      this.transcodeMusicDownloadModel = const TranscodeMusicDownloadModel(),
      this.position = const Vector2(x: 0, y: 0),
      this.size = const Vector2(x: 1280, y: 720),
      this.timeOut = const Duration(seconds: 30),
      this.nextUpDateCutoff,
      this.updateNotificationsInterval = const Duration(hours: 1),
      this.themeMode = ThemeMode.system,
      this.themeColor,
      this.singleColorTheme = true,
      this.deriveColorsFromItem = false,
      this.dynamicPosterColors = false,
      this.amoledBlack = false,
      this.blurPlaceHolders = true,
      this.imageCacheSize = ImageCacheSize.balanced,
      this.blurUpcomingEpisodes = false,
      @LocaleConvert() this.selectedLocale,
      this.enableMediaKeys = true,
      this.posterSize = 0.7,
      this.pinchPosterZoom = false,
      this.mouseDragSupport = false,
      this.requireWifi = true,
      this.askDownloadQuality = true,
      this.expandSideBar = false,
      this.showAllCollectionTypes = false,
      this.maxConcurrentDownloads = 2,
      this.schemeVariant = DynamicSchemeVariant.rainbow,
      this.backgroundImage = BackgroundType.blurred,
      this.enableBlurEffects = true,
      this.checkForUpdates = true,
      this.usePosterForLibrary = false,
      this.useSystemIME = false,
      this.useTVExpandedLayout = false,
      this.forceLeanBackMode = false,
      this.lastViewedUpdate,
      this.castServerUrl,
      this.libraryPageSize,
      final Map<GlobalHotKeys, KeyCombination> shortcuts = const {},
      final Map<String, bool> episodeFavoritePrefersShow = const {},
      final Set<String> hiddenBackdropTags = const {}})
      : _shortcuts = shortcuts,
        _episodeFavoritePrefersShow = episodeFavoritePrefersShow,
        _hiddenBackdropTags = hiddenBackdropTags,
        super._();
  factory _ClientSettingsModel.fromJson(Map<String, dynamic> json) =>
      _$ClientSettingsModelFromJson(json);

  @override
  final String? syncPath;
  @override
  final TranscodeDownloadModel transcodeDownloadModel;
  @override
  @JsonKey()
  final TranscodeMusicDownloadModel transcodeMusicDownloadModel;
  @override
  @JsonKey()
  final Vector2 position;
  @override
  @JsonKey()
  final Vector2 size;
  @override
  @JsonKey()
  final Duration? timeOut;
  @override
  final Duration? nextUpDateCutoff;
  @override
  @JsonKey()
  final Duration updateNotificationsInterval;
  @override
  @JsonKey()
  final ThemeMode themeMode;
  @override
  final ColorThemes? themeColor;

  /// Collapses a two-colour preset down to its primary. The preset itself is
  /// left alone, so turning this back off restores the pair.
  @override
  @JsonKey()
  final bool singleColorTheme;
  @override
  @JsonKey()
  final bool deriveColorsFromItem;
  @override
  @JsonKey()
  final bool dynamicPosterColors;
  @override
  @JsonKey()
  final bool amoledBlack;
  @override
  @JsonKey()
  final bool blurPlaceHolders;

  /// How much disk and memory artwork is allowed to occupy. The old
  /// behaviour is [ImageCacheSize.small]; the default is deliberately larger,
  /// because the small one re-fetched pictures faster than you could scroll
  /// back to them.
  @override
  @JsonKey()
  final ImageCacheSize imageCacheSize;
  @override
  @JsonKey()
  final bool blurUpcomingEpisodes;
  @override
  @LocaleConvert()
  final Locale? selectedLocale;
  @override
  @JsonKey()
  final bool enableMediaKeys;
  @override
  @JsonKey()
  final double posterSize;
  @override
  @JsonKey()
  final bool pinchPosterZoom;
  @override
  @JsonKey()
  final bool mouseDragSupport;
  @override
  @JsonKey()
  final bool requireWifi;

  /// Whether pressing download asks for the quality first. Cleared by the
  /// "always use these settings" box in that dialog, and restorable from
  /// Settings so the choice is not a one-way door.
  @override
  @JsonKey()
  final bool askDownloadQuality;
  @override
  @JsonKey()
  final bool expandSideBar;
  @override
  @JsonKey()
  final bool showAllCollectionTypes;
  @override
  @JsonKey()
  final int maxConcurrentDownloads;
  @override
  @JsonKey()
  final DynamicSchemeVariant schemeVariant;
  @override
  @JsonKey()
  final BackgroundType backgroundImage;
  @override
  @JsonKey()
  final bool enableBlurEffects;
  @override
  @JsonKey()
  final bool checkForUpdates;
  @override
  @JsonKey()
  final bool usePosterForLibrary;
  @override
  @JsonKey()
  final bool useSystemIME;
  @override
  @JsonKey()
  final bool useTVExpandedLayout;
  @override
  @JsonKey()
  final bool forceLeanBackMode;
  @override
  final String? lastViewedUpdate;
  @override
  final String? castServerUrl;
  @override
  final int? libraryPageSize;
  final Map<GlobalHotKeys, KeyCombination> _shortcuts;
  @override
  @JsonKey()
  Map<GlobalHotKeys, KeyCombination> get shortcuts {
    if (_shortcuts is EqualUnmodifiableMapView) return _shortcuts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_shortcuts);
  }

  /// Per-show answer to "favorite the episode or the whole show?" —
  /// showId → true when the user chose the show, false for the episode.
  /// Asked once per show, remembered here.
  final Map<String, bool> _episodeFavoritePrefersShow;

  /// Per-show answer to "favorite the episode or the whole show?" —
  /// showId → true when the user chose the show, false for the episode.
  /// Asked once per show, remembered here.
  @override
  @JsonKey()
  Map<String, bool> get episodeFavoritePrefersShow {
    if (_episodeFavoritePrefersShow is EqualUnmodifiableMapView)
      return _episodeFavoritePrefersShow;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_episodeFavoritePrefersShow);
  }

  /// Backdrops taken out of rotation on this device, by server image tag.
  /// The file stays on the server; the app just never picks it as a
  /// background. A per-device choice because Jellyfin has nowhere to keep
  /// one per user.
  final Set<String> _hiddenBackdropTags;

  /// Backdrops taken out of rotation on this device, by server image tag.
  /// The file stays on the server; the app just never picks it as a
  /// background. A per-device choice because Jellyfin has nowhere to keep
  /// one per user.
  @override
  @JsonKey()
  Set<String> get hiddenBackdropTags {
    if (_hiddenBackdropTags is EqualUnmodifiableSetView)
      return _hiddenBackdropTags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_hiddenBackdropTags);
  }

  /// Create a copy of ClientSettingsModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ClientSettingsModelCopyWith<_ClientSettingsModel> get copyWith =>
      __$ClientSettingsModelCopyWithImpl<_ClientSettingsModel>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ClientSettingsModelToJson(
      this,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
      ..add(DiagnosticsProperty('type', 'ClientSettingsModel.internal'))
      ..add(DiagnosticsProperty('syncPath', syncPath))
      ..add(
          DiagnosticsProperty('transcodeDownloadModel', transcodeDownloadModel))
      ..add(DiagnosticsProperty(
          'transcodeMusicDownloadModel', transcodeMusicDownloadModel))
      ..add(DiagnosticsProperty('position', position))
      ..add(DiagnosticsProperty('size', size))
      ..add(DiagnosticsProperty('timeOut', timeOut))
      ..add(DiagnosticsProperty('nextUpDateCutoff', nextUpDateCutoff))
      ..add(DiagnosticsProperty(
          'updateNotificationsInterval', updateNotificationsInterval))
      ..add(DiagnosticsProperty('themeMode', themeMode))
      ..add(DiagnosticsProperty('themeColor', themeColor))
      ..add(DiagnosticsProperty('singleColorTheme', singleColorTheme))
      ..add(DiagnosticsProperty('deriveColorsFromItem', deriveColorsFromItem))
      ..add(DiagnosticsProperty('dynamicPosterColors', dynamicPosterColors))
      ..add(DiagnosticsProperty('amoledBlack', amoledBlack))
      ..add(DiagnosticsProperty('blurPlaceHolders', blurPlaceHolders))
      ..add(DiagnosticsProperty('imageCacheSize', imageCacheSize))
      ..add(DiagnosticsProperty('blurUpcomingEpisodes', blurUpcomingEpisodes))
      ..add(DiagnosticsProperty('selectedLocale', selectedLocale))
      ..add(DiagnosticsProperty('enableMediaKeys', enableMediaKeys))
      ..add(DiagnosticsProperty('posterSize', posterSize))
      ..add(DiagnosticsProperty('pinchPosterZoom', pinchPosterZoom))
      ..add(DiagnosticsProperty('mouseDragSupport', mouseDragSupport))
      ..add(DiagnosticsProperty('requireWifi', requireWifi))
      ..add(DiagnosticsProperty('askDownloadQuality', askDownloadQuality))
      ..add(DiagnosticsProperty('expandSideBar', expandSideBar))
      ..add(
          DiagnosticsProperty('showAllCollectionTypes', showAllCollectionTypes))
      ..add(
          DiagnosticsProperty('maxConcurrentDownloads', maxConcurrentDownloads))
      ..add(DiagnosticsProperty('schemeVariant', schemeVariant))
      ..add(DiagnosticsProperty('backgroundImage', backgroundImage))
      ..add(DiagnosticsProperty('enableBlurEffects', enableBlurEffects))
      ..add(DiagnosticsProperty('checkForUpdates', checkForUpdates))
      ..add(DiagnosticsProperty('usePosterForLibrary', usePosterForLibrary))
      ..add(DiagnosticsProperty('useSystemIME', useSystemIME))
      ..add(DiagnosticsProperty('useTVExpandedLayout', useTVExpandedLayout))
      ..add(DiagnosticsProperty('forceLeanBackMode', forceLeanBackMode))
      ..add(DiagnosticsProperty('lastViewedUpdate', lastViewedUpdate))
      ..add(DiagnosticsProperty('castServerUrl', castServerUrl))
      ..add(DiagnosticsProperty('libraryPageSize', libraryPageSize))
      ..add(DiagnosticsProperty('shortcuts', shortcuts))
      ..add(DiagnosticsProperty(
          'episodeFavoritePrefersShow', episodeFavoritePrefersShow))
      ..add(DiagnosticsProperty('hiddenBackdropTags', hiddenBackdropTags));
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'ClientSettingsModel.internal(syncPath: $syncPath, transcodeDownloadModel: $transcodeDownloadModel, transcodeMusicDownloadModel: $transcodeMusicDownloadModel, position: $position, size: $size, timeOut: $timeOut, nextUpDateCutoff: $nextUpDateCutoff, updateNotificationsInterval: $updateNotificationsInterval, themeMode: $themeMode, themeColor: $themeColor, singleColorTheme: $singleColorTheme, deriveColorsFromItem: $deriveColorsFromItem, dynamicPosterColors: $dynamicPosterColors, amoledBlack: $amoledBlack, blurPlaceHolders: $blurPlaceHolders, imageCacheSize: $imageCacheSize, blurUpcomingEpisodes: $blurUpcomingEpisodes, selectedLocale: $selectedLocale, enableMediaKeys: $enableMediaKeys, posterSize: $posterSize, pinchPosterZoom: $pinchPosterZoom, mouseDragSupport: $mouseDragSupport, requireWifi: $requireWifi, askDownloadQuality: $askDownloadQuality, expandSideBar: $expandSideBar, showAllCollectionTypes: $showAllCollectionTypes, maxConcurrentDownloads: $maxConcurrentDownloads, schemeVariant: $schemeVariant, backgroundImage: $backgroundImage, enableBlurEffects: $enableBlurEffects, checkForUpdates: $checkForUpdates, usePosterForLibrary: $usePosterForLibrary, useSystemIME: $useSystemIME, useTVExpandedLayout: $useTVExpandedLayout, forceLeanBackMode: $forceLeanBackMode, lastViewedUpdate: $lastViewedUpdate, castServerUrl: $castServerUrl, libraryPageSize: $libraryPageSize, shortcuts: $shortcuts, episodeFavoritePrefersShow: $episodeFavoritePrefersShow, hiddenBackdropTags: $hiddenBackdropTags)';
  }
}

/// @nodoc
abstract mixin class _$ClientSettingsModelCopyWith<$Res>
    implements $ClientSettingsModelCopyWith<$Res> {
  factory _$ClientSettingsModelCopyWith(_ClientSettingsModel value,
          $Res Function(_ClientSettingsModel) _then) =
      __$ClientSettingsModelCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String? syncPath,
      TranscodeDownloadModel transcodeDownloadModel,
      TranscodeMusicDownloadModel transcodeMusicDownloadModel,
      Vector2 position,
      Vector2 size,
      Duration? timeOut,
      Duration? nextUpDateCutoff,
      Duration updateNotificationsInterval,
      ThemeMode themeMode,
      ColorThemes? themeColor,
      bool singleColorTheme,
      bool deriveColorsFromItem,
      bool dynamicPosterColors,
      bool amoledBlack,
      bool blurPlaceHolders,
      ImageCacheSize imageCacheSize,
      bool blurUpcomingEpisodes,
      @LocaleConvert() Locale? selectedLocale,
      bool enableMediaKeys,
      double posterSize,
      bool pinchPosterZoom,
      bool mouseDragSupport,
      bool requireWifi,
      bool askDownloadQuality,
      bool expandSideBar,
      bool showAllCollectionTypes,
      int maxConcurrentDownloads,
      DynamicSchemeVariant schemeVariant,
      BackgroundType backgroundImage,
      bool enableBlurEffects,
      bool checkForUpdates,
      bool usePosterForLibrary,
      bool useSystemIME,
      bool useTVExpandedLayout,
      bool forceLeanBackMode,
      String? lastViewedUpdate,
      String? castServerUrl,
      int? libraryPageSize,
      Map<GlobalHotKeys, KeyCombination> shortcuts,
      Map<String, bool> episodeFavoritePrefersShow,
      Set<String> hiddenBackdropTags});

  @override
  $TranscodeDownloadModelCopyWith<$Res> get transcodeDownloadModel;
}

/// @nodoc
class __$ClientSettingsModelCopyWithImpl<$Res>
    implements _$ClientSettingsModelCopyWith<$Res> {
  __$ClientSettingsModelCopyWithImpl(this._self, this._then);

  final _ClientSettingsModel _self;
  final $Res Function(_ClientSettingsModel) _then;

  /// Create a copy of ClientSettingsModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? syncPath = freezed,
    Object? transcodeDownloadModel = null,
    Object? transcodeMusicDownloadModel = null,
    Object? position = null,
    Object? size = null,
    Object? timeOut = freezed,
    Object? nextUpDateCutoff = freezed,
    Object? updateNotificationsInterval = null,
    Object? themeMode = null,
    Object? themeColor = freezed,
    Object? singleColorTheme = null,
    Object? deriveColorsFromItem = null,
    Object? dynamicPosterColors = null,
    Object? amoledBlack = null,
    Object? blurPlaceHolders = null,
    Object? imageCacheSize = null,
    Object? blurUpcomingEpisodes = null,
    Object? selectedLocale = freezed,
    Object? enableMediaKeys = null,
    Object? posterSize = null,
    Object? pinchPosterZoom = null,
    Object? mouseDragSupport = null,
    Object? requireWifi = null,
    Object? askDownloadQuality = null,
    Object? expandSideBar = null,
    Object? showAllCollectionTypes = null,
    Object? maxConcurrentDownloads = null,
    Object? schemeVariant = null,
    Object? backgroundImage = null,
    Object? enableBlurEffects = null,
    Object? checkForUpdates = null,
    Object? usePosterForLibrary = null,
    Object? useSystemIME = null,
    Object? useTVExpandedLayout = null,
    Object? forceLeanBackMode = null,
    Object? lastViewedUpdate = freezed,
    Object? castServerUrl = freezed,
    Object? libraryPageSize = freezed,
    Object? shortcuts = null,
    Object? episodeFavoritePrefersShow = null,
    Object? hiddenBackdropTags = null,
  }) {
    return _then(_ClientSettingsModel(
      syncPath: freezed == syncPath
          ? _self.syncPath
          : syncPath // ignore: cast_nullable_to_non_nullable
              as String?,
      transcodeDownloadModel: null == transcodeDownloadModel
          ? _self.transcodeDownloadModel
          : transcodeDownloadModel // ignore: cast_nullable_to_non_nullable
              as TranscodeDownloadModel,
      transcodeMusicDownloadModel: null == transcodeMusicDownloadModel
          ? _self.transcodeMusicDownloadModel
          : transcodeMusicDownloadModel // ignore: cast_nullable_to_non_nullable
              as TranscodeMusicDownloadModel,
      position: null == position
          ? _self.position
          : position // ignore: cast_nullable_to_non_nullable
              as Vector2,
      size: null == size
          ? _self.size
          : size // ignore: cast_nullable_to_non_nullable
              as Vector2,
      timeOut: freezed == timeOut
          ? _self.timeOut
          : timeOut // ignore: cast_nullable_to_non_nullable
              as Duration?,
      nextUpDateCutoff: freezed == nextUpDateCutoff
          ? _self.nextUpDateCutoff
          : nextUpDateCutoff // ignore: cast_nullable_to_non_nullable
              as Duration?,
      updateNotificationsInterval: null == updateNotificationsInterval
          ? _self.updateNotificationsInterval
          : updateNotificationsInterval // ignore: cast_nullable_to_non_nullable
              as Duration,
      themeMode: null == themeMode
          ? _self.themeMode
          : themeMode // ignore: cast_nullable_to_non_nullable
              as ThemeMode,
      themeColor: freezed == themeColor
          ? _self.themeColor
          : themeColor // ignore: cast_nullable_to_non_nullable
              as ColorThemes?,
      singleColorTheme: null == singleColorTheme
          ? _self.singleColorTheme
          : singleColorTheme // ignore: cast_nullable_to_non_nullable
              as bool,
      deriveColorsFromItem: null == deriveColorsFromItem
          ? _self.deriveColorsFromItem
          : deriveColorsFromItem // ignore: cast_nullable_to_non_nullable
              as bool,
      dynamicPosterColors: null == dynamicPosterColors
          ? _self.dynamicPosterColors
          : dynamicPosterColors // ignore: cast_nullable_to_non_nullable
              as bool,
      amoledBlack: null == amoledBlack
          ? _self.amoledBlack
          : amoledBlack // ignore: cast_nullable_to_non_nullable
              as bool,
      blurPlaceHolders: null == blurPlaceHolders
          ? _self.blurPlaceHolders
          : blurPlaceHolders // ignore: cast_nullable_to_non_nullable
              as bool,
      imageCacheSize: null == imageCacheSize
          ? _self.imageCacheSize
          : imageCacheSize // ignore: cast_nullable_to_non_nullable
              as ImageCacheSize,
      blurUpcomingEpisodes: null == blurUpcomingEpisodes
          ? _self.blurUpcomingEpisodes
          : blurUpcomingEpisodes // ignore: cast_nullable_to_non_nullable
              as bool,
      selectedLocale: freezed == selectedLocale
          ? _self.selectedLocale
          : selectedLocale // ignore: cast_nullable_to_non_nullable
              as Locale?,
      enableMediaKeys: null == enableMediaKeys
          ? _self.enableMediaKeys
          : enableMediaKeys // ignore: cast_nullable_to_non_nullable
              as bool,
      posterSize: null == posterSize
          ? _self.posterSize
          : posterSize // ignore: cast_nullable_to_non_nullable
              as double,
      pinchPosterZoom: null == pinchPosterZoom
          ? _self.pinchPosterZoom
          : pinchPosterZoom // ignore: cast_nullable_to_non_nullable
              as bool,
      mouseDragSupport: null == mouseDragSupport
          ? _self.mouseDragSupport
          : mouseDragSupport // ignore: cast_nullable_to_non_nullable
              as bool,
      requireWifi: null == requireWifi
          ? _self.requireWifi
          : requireWifi // ignore: cast_nullable_to_non_nullable
              as bool,
      askDownloadQuality: null == askDownloadQuality
          ? _self.askDownloadQuality
          : askDownloadQuality // ignore: cast_nullable_to_non_nullable
              as bool,
      expandSideBar: null == expandSideBar
          ? _self.expandSideBar
          : expandSideBar // ignore: cast_nullable_to_non_nullable
              as bool,
      showAllCollectionTypes: null == showAllCollectionTypes
          ? _self.showAllCollectionTypes
          : showAllCollectionTypes // ignore: cast_nullable_to_non_nullable
              as bool,
      maxConcurrentDownloads: null == maxConcurrentDownloads
          ? _self.maxConcurrentDownloads
          : maxConcurrentDownloads // ignore: cast_nullable_to_non_nullable
              as int,
      schemeVariant: null == schemeVariant
          ? _self.schemeVariant
          : schemeVariant // ignore: cast_nullable_to_non_nullable
              as DynamicSchemeVariant,
      backgroundImage: null == backgroundImage
          ? _self.backgroundImage
          : backgroundImage // ignore: cast_nullable_to_non_nullable
              as BackgroundType,
      enableBlurEffects: null == enableBlurEffects
          ? _self.enableBlurEffects
          : enableBlurEffects // ignore: cast_nullable_to_non_nullable
              as bool,
      checkForUpdates: null == checkForUpdates
          ? _self.checkForUpdates
          : checkForUpdates // ignore: cast_nullable_to_non_nullable
              as bool,
      usePosterForLibrary: null == usePosterForLibrary
          ? _self.usePosterForLibrary
          : usePosterForLibrary // ignore: cast_nullable_to_non_nullable
              as bool,
      useSystemIME: null == useSystemIME
          ? _self.useSystemIME
          : useSystemIME // ignore: cast_nullable_to_non_nullable
              as bool,
      useTVExpandedLayout: null == useTVExpandedLayout
          ? _self.useTVExpandedLayout
          : useTVExpandedLayout // ignore: cast_nullable_to_non_nullable
              as bool,
      forceLeanBackMode: null == forceLeanBackMode
          ? _self.forceLeanBackMode
          : forceLeanBackMode // ignore: cast_nullable_to_non_nullable
              as bool,
      lastViewedUpdate: freezed == lastViewedUpdate
          ? _self.lastViewedUpdate
          : lastViewedUpdate // ignore: cast_nullable_to_non_nullable
              as String?,
      castServerUrl: freezed == castServerUrl
          ? _self.castServerUrl
          : castServerUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      libraryPageSize: freezed == libraryPageSize
          ? _self.libraryPageSize
          : libraryPageSize // ignore: cast_nullable_to_non_nullable
              as int?,
      shortcuts: null == shortcuts
          ? _self._shortcuts
          : shortcuts // ignore: cast_nullable_to_non_nullable
              as Map<GlobalHotKeys, KeyCombination>,
      episodeFavoritePrefersShow: null == episodeFavoritePrefersShow
          ? _self._episodeFavoritePrefersShow
          : episodeFavoritePrefersShow // ignore: cast_nullable_to_non_nullable
              as Map<String, bool>,
      hiddenBackdropTags: null == hiddenBackdropTags
          ? _self._hiddenBackdropTags
          : hiddenBackdropTags // ignore: cast_nullable_to_non_nullable
              as Set<String>,
    ));
  }

  /// Create a copy of ClientSettingsModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $TranscodeDownloadModelCopyWith<$Res> get transcodeDownloadModel {
    return $TranscodeDownloadModelCopyWith<$Res>(_self.transcodeDownloadModel,
        (value) {
      return _then(_self.copyWith(transcodeDownloadModel: value));
    });
  }
}

// dart format on
