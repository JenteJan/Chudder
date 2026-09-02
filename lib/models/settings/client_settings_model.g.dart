// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_settings_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ClientSettingsModel _$ClientSettingsModelFromJson(Map<String, dynamic> json) =>
    _ClientSettingsModel(
      syncPath: json['syncPath'] as String?,
      transcodeDownloadModel: TranscodeDownloadModel.fromJson(
          json['transcodeDownloadModel'] as Map<String, dynamic>),
      transcodeMusicDownloadModel: json['transcodeMusicDownloadModel'] == null
          ? const TranscodeMusicDownloadModel()
          : TranscodeMusicDownloadModel.fromJson(
              json['transcodeMusicDownloadModel'] as Map<String, dynamic>),
      position: json['position'] == null
          ? const Vector2(x: 0, y: 0)
          : Vector2.fromJson(json['position'] as String),
      size: json['size'] == null
          ? const Vector2(x: 1280, y: 720)
          : Vector2.fromJson(json['size'] as String),
      timeOut: json['timeOut'] == null
          ? const Duration(seconds: 30)
          : Duration(microseconds: (json['timeOut'] as num).toInt()),
      nextUpDateCutoff: json['nextUpDateCutoff'] == null
          ? null
          : Duration(microseconds: (json['nextUpDateCutoff'] as num).toInt()),
      updateNotificationsInterval: json['updateNotificationsInterval'] == null
          ? const Duration(hours: 1)
          : Duration(
              microseconds:
                  (json['updateNotificationsInterval'] as num).toInt()),
      themeMode: $enumDecodeNullable(_$ThemeModeEnumMap, json['themeMode']) ??
          ThemeMode.system,
      themeColor: $enumDecodeNullable(_$ColorThemesEnumMap, json['themeColor']),
      singleColorTheme: json['singleColorTheme'] as bool? ?? true,
      deriveColorsFromItem: json['deriveColorsFromItem'] as bool? ?? false,
      dynamicPosterColors: json['dynamicPosterColors'] as bool? ?? false,
      amoledBlack: json['amoledBlack'] as bool? ?? false,
      blurPlaceHolders: json['blurPlaceHolders'] as bool? ?? true,
      imageCacheSize: $enumDecodeNullable(
              _$ImageCacheSizeEnumMap, json['imageCacheSize']) ??
          ImageCacheSize.balanced,
      blurUpcomingEpisodes: json['blurUpcomingEpisodes'] as bool? ?? false,
      selectedLocale:
          const LocaleConvert().fromJson(json['selectedLocale'] as String?),
      enableMediaKeys: json['enableMediaKeys'] as bool? ?? true,
      posterSize: (json['posterSize'] as num?)?.toDouble() ?? 0.7,
      pinchPosterZoom: json['pinchPosterZoom'] as bool? ?? false,
      mouseDragSupport: json['mouseDragSupport'] as bool? ?? false,
      requireWifi: json['requireWifi'] as bool? ?? true,
      askDownloadQuality: json['askDownloadQuality'] as bool? ?? true,
      expandSideBar: json['expandSideBar'] as bool? ?? false,
      showAllCollectionTypes: json['showAllCollectionTypes'] as bool? ?? false,
      maxConcurrentDownloads:
          (json['maxConcurrentDownloads'] as num?)?.toInt() ?? 2,
      schemeVariant: $enumDecodeNullable(
              _$DynamicSchemeVariantEnumMap, json['schemeVariant']) ??
          DynamicSchemeVariant.rainbow,
      backgroundImage: $enumDecodeNullable(
              _$BackgroundTypeEnumMap, json['backgroundImage']) ??
          BackgroundType.blurred,
      enableBlurEffects: json['enableBlurEffects'] as bool? ?? true,
      checkForUpdates: json['checkForUpdates'] as bool? ?? true,
      usePosterForLibrary: json['usePosterForLibrary'] as bool? ?? false,
      useSystemIME: json['useSystemIME'] as bool? ?? false,
      useTVExpandedLayout: json['useTVExpandedLayout'] as bool? ?? false,
      forceLeanBackMode: json['forceLeanBackMode'] as bool? ?? false,
      lastViewedUpdate: json['lastViewedUpdate'] as String?,
      castServerUrl: json['castServerUrl'] as String?,
      libraryPageSize: (json['libraryPageSize'] as num?)?.toInt(),
      shortcuts: (json['shortcuts'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry($enumDecode(_$GlobalHotKeysEnumMap, k),
                KeyCombination.fromJson(e as Map<String, dynamic>)),
          ) ??
          const {},
      episodeFavoritePrefersShow:
          (json['episodeFavoritePrefersShow'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, e as bool),
              ) ??
              const {},
      hiddenBackdropTags: (json['hiddenBackdropTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          const {},
    );

Map<String, dynamic> _$ClientSettingsModelToJson(
        _ClientSettingsModel instance) =>
    <String, dynamic>{
      'syncPath': instance.syncPath,
      'transcodeDownloadModel': instance.transcodeDownloadModel,
      'transcodeMusicDownloadModel': instance.transcodeMusicDownloadModel,
      'position': instance.position,
      'size': instance.size,
      'timeOut': instance.timeOut?.inMicroseconds,
      'nextUpDateCutoff': instance.nextUpDateCutoff?.inMicroseconds,
      'updateNotificationsInterval':
          instance.updateNotificationsInterval.inMicroseconds,
      'themeMode': _$ThemeModeEnumMap[instance.themeMode]!,
      'themeColor': _$ColorThemesEnumMap[instance.themeColor],
      'singleColorTheme': instance.singleColorTheme,
      'deriveColorsFromItem': instance.deriveColorsFromItem,
      'dynamicPosterColors': instance.dynamicPosterColors,
      'amoledBlack': instance.amoledBlack,
      'blurPlaceHolders': instance.blurPlaceHolders,
      'imageCacheSize': _$ImageCacheSizeEnumMap[instance.imageCacheSize]!,
      'blurUpcomingEpisodes': instance.blurUpcomingEpisodes,
      'selectedLocale': const LocaleConvert().toJson(instance.selectedLocale),
      'enableMediaKeys': instance.enableMediaKeys,
      'posterSize': instance.posterSize,
      'pinchPosterZoom': instance.pinchPosterZoom,
      'mouseDragSupport': instance.mouseDragSupport,
      'requireWifi': instance.requireWifi,
      'askDownloadQuality': instance.askDownloadQuality,
      'expandSideBar': instance.expandSideBar,
      'showAllCollectionTypes': instance.showAllCollectionTypes,
      'maxConcurrentDownloads': instance.maxConcurrentDownloads,
      'schemeVariant': _$DynamicSchemeVariantEnumMap[instance.schemeVariant]!,
      'backgroundImage': _$BackgroundTypeEnumMap[instance.backgroundImage]!,
      'enableBlurEffects': instance.enableBlurEffects,
      'checkForUpdates': instance.checkForUpdates,
      'usePosterForLibrary': instance.usePosterForLibrary,
      'useSystemIME': instance.useSystemIME,
      'useTVExpandedLayout': instance.useTVExpandedLayout,
      'forceLeanBackMode': instance.forceLeanBackMode,
      'lastViewedUpdate': instance.lastViewedUpdate,
      'castServerUrl': instance.castServerUrl,
      'libraryPageSize': instance.libraryPageSize,
      'shortcuts': instance.shortcuts
          .map((k, e) => MapEntry(_$GlobalHotKeysEnumMap[k]!, e)),
      'episodeFavoritePrefersShow': instance.episodeFavoritePrefersShow,
      'hiddenBackdropTags': instance.hiddenBackdropTags.toList(),
    };

const _$ThemeModeEnumMap = {
  ThemeMode.system: 'system',
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
};

const _$ColorThemesEnumMap = {
  ColorThemes.fladder: 'fladder',
  ColorThemes.chudderReversed: 'chudderReversed',
  ColorThemes.chudderBlue: 'chudderBlue',
  ColorThemes.chudderYellow: 'chudderYellow',
  ColorThemes.deepOrange: 'deepOrange',
  ColorThemes.amber: 'amber',
  ColorThemes.green: 'green',
  ColorThemes.lightGreen: 'lightGreen',
  ColorThemes.lime: 'lime',
  ColorThemes.cyan: 'cyan',
  ColorThemes.blue: 'blue',
  ColorThemes.lightBlue: 'lightBlue',
  ColorThemes.indigo: 'indigo',
  ColorThemes.deepBlue: 'deepBlue',
  ColorThemes.brown: 'brown',
  ColorThemes.purple: 'purple',
  ColorThemes.deepPurple: 'deepPurple',
  ColorThemes.blueGrey: 'blueGrey',
};

const _$ImageCacheSizeEnumMap = {
  ImageCacheSize.small: 'small',
  ImageCacheSize.balanced: 'balanced',
  ImageCacheSize.large: 'large',
};

const _$DynamicSchemeVariantEnumMap = {
  DynamicSchemeVariant.tonalSpot: 'tonalSpot',
  DynamicSchemeVariant.fidelity: 'fidelity',
  DynamicSchemeVariant.monochrome: 'monochrome',
  DynamicSchemeVariant.neutral: 'neutral',
  DynamicSchemeVariant.vibrant: 'vibrant',
  DynamicSchemeVariant.expressive: 'expressive',
  DynamicSchemeVariant.content: 'content',
  DynamicSchemeVariant.rainbow: 'rainbow',
  DynamicSchemeVariant.fruitSalad: 'fruitSalad',
};

const _$BackgroundTypeEnumMap = {
  BackgroundType.disabled: 'disabled',
  BackgroundType.enabled: 'enabled',
  BackgroundType.blurred: 'blurred',
};

const _$GlobalHotKeysEnumMap = {
  GlobalHotKeys.search: 'search',
  GlobalHotKeys.closeWindow: 'closeWindow',
  GlobalHotKeys.exit: 'exit',
  GlobalHotKeys.toggleSideBar: 'toggleSideBar',
};
