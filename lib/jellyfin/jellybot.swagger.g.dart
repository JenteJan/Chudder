// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jellybot.swagger.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaginatedResponseOfCrawlLinkDto _$PaginatedResponseOfCrawlLinkDtoFromJson(
        Map<String, dynamic> json) =>
    PaginatedResponseOfCrawlLinkDto(
      currentPage: (json['currentPage'] as num?)?.toInt(),
      totalPages: (json['totalPages'] as num?)?.toInt(),
      pageSize: (json['pageSize'] as num?)?.toInt(),
      totalCount: (json['totalCount'] as num?)?.toInt(),
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => CrawlLinkDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$PaginatedResponseOfCrawlLinkDtoToJson(
        PaginatedResponseOfCrawlLinkDto instance) =>
    <String, dynamic>{
      if (instance.currentPage case final value?) 'currentPage': value,
      if (instance.totalPages case final value?) 'totalPages': value,
      if (instance.pageSize case final value?) 'pageSize': value,
      if (instance.totalCount case final value?) 'totalCount': value,
      if (instance.items?.map((e) => e.toJson()).toList() case final value?)
        'items': value,
    };

CrawlLinkDto _$CrawlLinkDtoFromJson(Map<String, dynamic> json) => CrawlLinkDto(
      id: json['id'] as String?,
      mediaId: json['mediaId'] as String?,
      name: json['name'] as String?,
      secondName: json['secondName'] as String?,
      provider: json['provider'],
      providerId: json['providerId'] as String?,
      providerItemId: json['providerItemId'] as String?,
      providerCategory: json['providerCategory'] as String?,
      category: mediaCategoryNullableFromJson(json['category']),
      fullUrl: json['fullUrl'] as String?,
      relativeUrl: json['relativeUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      airedEpisodesCount: (json['airedEpisodesCount'] as num?)?.toInt(),
      totalEpisodesCount: (json['totalEpisodesCount'] as num?)?.toInt(),
      season: (json['season'] as num?)?.toInt(),
      quality: json['quality'] as String?,
      version: json['version'] as String?,
      productionYear: (json['productionYear'] as num?)?.toInt(),
      lastChecked: json['lastChecked'] == null
          ? null
          : DateTime.parse(json['lastChecked'] as String),
      downloaded: json['downloaded'] as bool?,
      hasError: json['hasError'] as bool?,
      createdBy: json['createdBy'] as String?,
      authorId: json['authorId'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      origin: creationOriginNullableFromJson(json['origin']),
      mediaServerType: mediaServerTypeNullableFromJson(json['mediaServerType']),
      isEnabled: json['isEnabled'] as bool?,
      disabledHosts: (json['disabledHosts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );

Map<String, dynamic> _$CrawlLinkDtoToJson(CrawlLinkDto instance) =>
    <String, dynamic>{
      if (instance.id case final value?) 'id': value,
      if (instance.mediaId case final value?) 'mediaId': value,
      if (instance.name case final value?) 'name': value,
      if (instance.secondName case final value?) 'secondName': value,
      if (instance.provider case final value?) 'provider': value,
      if (instance.providerId case final value?) 'providerId': value,
      if (instance.providerItemId case final value?) 'providerItemId': value,
      if (instance.providerCategory case final value?)
        'providerCategory': value,
      if (mediaCategoryNullableToJson(instance.category) case final value?)
        'category': value,
      if (instance.fullUrl case final value?) 'fullUrl': value,
      if (instance.relativeUrl case final value?) 'relativeUrl': value,
      if (instance.thumbnailUrl case final value?) 'thumbnailUrl': value,
      if (instance.airedEpisodesCount case final value?)
        'airedEpisodesCount': value,
      if (instance.totalEpisodesCount case final value?)
        'totalEpisodesCount': value,
      if (instance.season case final value?) 'season': value,
      if (instance.quality case final value?) 'quality': value,
      if (instance.version case final value?) 'version': value,
      if (instance.productionYear case final value?) 'productionYear': value,
      if (instance.lastChecked?.toIso8601String() case final value?)
        'lastChecked': value,
      if (instance.downloaded case final value?) 'downloaded': value,
      if (instance.hasError case final value?) 'hasError': value,
      if (instance.createdBy case final value?) 'createdBy': value,
      if (instance.authorId case final value?) 'authorId': value,
      if (instance.createdAt?.toIso8601String() case final value?)
        'createdAt': value,
      if (creationOriginNullableToJson(instance.origin) case final value?)
        'origin': value,
      if (mediaServerTypeNullableToJson(instance.mediaServerType)
          case final value?)
        'mediaServerType': value,
      if (instance.isEnabled case final value?) 'isEnabled': value,
      if (instance.disabledHosts case final value?) 'disabledHosts': value,
    };

ProviderDto _$ProviderDtoFromJson(Map<String, dynamic> json) => ProviderDto(
      displayName: json['displayName'] as String?,
      name: json['name'] as String?,
      url: json['url'] as String?,
      enabled: json['enabled'] as bool?,
      searchEnabled: json['searchEnabled'] as bool?,
      isManuallyDisabled: json['isManuallyDisabled'] as bool?,
    );

Map<String, dynamic> _$ProviderDtoToJson(ProviderDto instance) =>
    <String, dynamic>{
      if (instance.displayName case final value?) 'displayName': value,
      if (instance.name case final value?) 'name': value,
      if (instance.url case final value?) 'url': value,
      if (instance.enabled case final value?) 'enabled': value,
      if (instance.searchEnabled case final value?) 'searchEnabled': value,
      if (instance.isManuallyDisabled case final value?)
        'isManuallyDisabled': value,
    };

ExtractMediaResponse _$ExtractMediaResponseFromJson(
        Map<String, dynamic> json) =>
    ExtractMediaResponse(
      requiresSeasonSelection: json['requiresSeasonSelection'] as bool?,
      availableSeasons: (json['availableSeasons'] as num?)?.toInt(),
      mediaTitle: json['mediaTitle'] as String?,
      originalUrl: json['originalUrl'] as String?,
      crawlLink: json['crawlLink'],
      mediaExistsOnServer: json['mediaExistsOnServer'] as bool?,
      requiresExistenceConfirmation:
          json['requiresExistenceConfirmation'] as bool?,
      existingMedia: json['existingMedia'],
    );

Map<String, dynamic> _$ExtractMediaResponseToJson(
        ExtractMediaResponse instance) =>
    <String, dynamic>{
      if (instance.requiresSeasonSelection case final value?)
        'requiresSeasonSelection': value,
      if (instance.availableSeasons case final value?)
        'availableSeasons': value,
      if (instance.mediaTitle case final value?) 'mediaTitle': value,
      if (instance.originalUrl case final value?) 'originalUrl': value,
      if (instance.crawlLink case final value?) 'crawlLink': value,
      if (instance.mediaExistsOnServer case final value?)
        'mediaExistsOnServer': value,
      if (instance.requiresExistenceConfirmation case final value?)
        'requiresExistenceConfirmation': value,
      if (instance.existingMedia case final value?) 'existingMedia': value,
    };

MediaSearchResultDto _$MediaSearchResultDtoFromJson(
        Map<String, dynamic> json) =>
    MediaSearchResultDto(
      id: json['id'] as String?,
      title: json['title'] as String?,
      originalTitle: json['originalTitle'] as String?,
      productionYear: (json['productionYear'] as num?)?.toInt(),
      isShow: json['isShow'] as bool?,
      mediaUrl: json['mediaUrl'] as String?,
    );

Map<String, dynamic> _$MediaSearchResultDtoToJson(
        MediaSearchResultDto instance) =>
    <String, dynamic>{
      if (instance.id case final value?) 'id': value,
      if (instance.title case final value?) 'title': value,
      if (instance.originalTitle case final value?) 'originalTitle': value,
      if (instance.productionYear case final value?) 'productionYear': value,
      if (instance.isShow case final value?) 'isShow': value,
      if (instance.mediaUrl case final value?) 'mediaUrl': value,
    };

ProblemDetails _$ProblemDetailsFromJson(Map<String, dynamic> json) =>
    ProblemDetails(
      type: json['type'] as String?,
      title: json['title'] as String?,
      status: (json['status'] as num?)?.toInt(),
      detail: json['detail'] as String?,
      instance: json['instance'] as String?,
      extensions: json['extensions'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$ProblemDetailsToJson(ProblemDetails instance) =>
    <String, dynamic>{
      if (instance.type case final value?) 'type': value,
      if (instance.title case final value?) 'title': value,
      if (instance.status case final value?) 'status': value,
      if (instance.detail case final value?) 'detail': value,
      if (instance.instance case final value?) 'instance': value,
      if (instance.extensions case final value?) 'extensions': value,
    };

ExtractMediaRequest _$ExtractMediaRequestFromJson(Map<String, dynamic> json) =>
    ExtractMediaRequest(
      url: json['url'] as String?,
      userName: json['userName'] as String?,
      userId: json['userId'] as String?,
      mediaCategory: mediaCategoryNullableFromJson(json['mediaCategory']),
    );

Map<String, dynamic> _$ExtractMediaRequestToJson(
        ExtractMediaRequest instance) =>
    <String, dynamic>{
      if (instance.url case final value?) 'url': value,
      if (instance.userName case final value?) 'userName': value,
      if (instance.userId case final value?) 'userId': value,
      if (mediaCategoryNullableToJson(instance.mediaCategory) case final value?)
        'mediaCategory': value,
    };

SelectSeasonRequest _$SelectSeasonRequestFromJson(Map<String, dynamic> json) =>
    SelectSeasonRequest(
      url: json['url'] as String?,
      season: (json['season'] as num?)?.toInt(),
      userName: json['userName'] as String?,
      userId: json['userId'] as String?,
      mediaCategory: mediaCategoryNullableFromJson(json['mediaCategory']),
    );

Map<String, dynamic> _$SelectSeasonRequestToJson(
        SelectSeasonRequest instance) =>
    <String, dynamic>{
      if (instance.url case final value?) 'url': value,
      if (instance.season case final value?) 'season': value,
      if (instance.userName case final value?) 'userName': value,
      if (instance.userId case final value?) 'userId': value,
      if (mediaCategoryNullableToJson(instance.mediaCategory) case final value?)
        'mediaCategory': value,
    };

ExtractMediaConfirmationRequest _$ExtractMediaConfirmationRequestFromJson(
        Map<String, dynamic> json) =>
    ExtractMediaConfirmationRequest(
      crawlLinkId: json['crawlLinkId'] as String?,
      mediaTitle: json['mediaTitle'] as String?,
    );

Map<String, dynamic> _$ExtractMediaConfirmationRequestToJson(
        ExtractMediaConfirmationRequest instance) =>
    <String, dynamic>{
      if (instance.crawlLinkId case final value?) 'crawlLinkId': value,
      if (instance.mediaTitle case final value?) 'mediaTitle': value,
    };

RenameLinkResult _$RenameLinkResultFromJson(Map<String, dynamic> json) =>
    RenameLinkResult(
      isSuccess: json['isSuccess'] as bool?,
      error: json['error'] as String?,
      oldName: json['oldName'] as String?,
      newName: json['newName'] as String?,
    );

Map<String, dynamic> _$RenameLinkResultToJson(RenameLinkResult instance) =>
    <String, dynamic>{
      if (instance.isSuccess case final value?) 'isSuccess': value,
      if (instance.error case final value?) 'error': value,
      if (instance.oldName case final value?) 'oldName': value,
      if (instance.newName case final value?) 'newName': value,
    };

RenameCrawlLinkRequest _$RenameCrawlLinkRequestFromJson(
        Map<String, dynamic> json) =>
    RenameCrawlLinkRequest(
      newName: json['newName'] as String?,
    );

Map<String, dynamic> _$RenameCrawlLinkRequestToJson(
        RenameCrawlLinkRequest instance) =>
    <String, dynamic>{
      if (instance.newName case final value?) 'newName': value,
    };

UpdateCrawlLinkRequest _$UpdateCrawlLinkRequestFromJson(
        Map<String, dynamic> json) =>
    UpdateCrawlLinkRequest(
      name: json['name'] as String?,
      secondName: json['secondName'] as String?,
      url: json['url'] as String?,
      providerCategory: json['providerCategory'] as String?,
      category: json['category'],
      thumbnailUrl: json['thumbnailUrl'] as String?,
      airedEpisodesCount: (json['airedEpisodesCount'] as num?)?.toInt(),
      totalEpisodesCount: (json['totalEpisodesCount'] as num?)?.toInt(),
      season: (json['season'] as num?)?.toInt(),
      quality: json['quality'] as String?,
      version: json['version'] as String?,
      productionYear: (json['productionYear'] as num?)?.toInt(),
      lastChecked: json['lastChecked'] == null
          ? null
          : DateTime.parse(json['lastChecked'] as String),
      clearLastChecked: json['clearLastChecked'] as bool?,
      downloaded: json['downloaded'] as bool?,
      hasError: json['hasError'] as bool?,
      isEnabled: json['isEnabled'] as bool?,
      disabledHosts: (json['disabledHosts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );

Map<String, dynamic> _$UpdateCrawlLinkRequestToJson(
        UpdateCrawlLinkRequest instance) =>
    <String, dynamic>{
      if (instance.name case final value?) 'name': value,
      if (instance.secondName case final value?) 'secondName': value,
      if (instance.url case final value?) 'url': value,
      if (instance.providerCategory case final value?)
        'providerCategory': value,
      if (instance.category case final value?) 'category': value,
      if (instance.thumbnailUrl case final value?) 'thumbnailUrl': value,
      if (instance.airedEpisodesCount case final value?)
        'airedEpisodesCount': value,
      if (instance.totalEpisodesCount case final value?)
        'totalEpisodesCount': value,
      if (instance.season case final value?) 'season': value,
      if (instance.quality case final value?) 'quality': value,
      if (instance.version case final value?) 'version': value,
      if (instance.productionYear case final value?) 'productionYear': value,
      if (instance.lastChecked?.toIso8601String() case final value?)
        'lastChecked': value,
      if (instance.clearLastChecked case final value?)
        'clearLastChecked': value,
      if (instance.downloaded case final value?) 'downloaded': value,
      if (instance.hasError case final value?) 'hasError': value,
      if (instance.isEnabled case final value?) 'isEnabled': value,
      if (instance.disabledHosts case final value?) 'disabledHosts': value,
    };

UpdateDisabledHostsRequest _$UpdateDisabledHostsRequestFromJson(
        Map<String, dynamic> json) =>
    UpdateDisabledHostsRequest(
      hosts:
          (json['hosts'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
    );

Map<String, dynamic> _$UpdateDisabledHostsRequestToJson(
        UpdateDisabledHostsRequest instance) =>
    <String, dynamic>{
      if (instance.hosts case final value?) 'hosts': value,
    };

DownloadDto _$DownloadDtoFromJson(Map<String, dynamic> json) => DownloadDto(
      name: json['name'] as String?,
      fileName: json['fileName'] as String?,
      url: json['url'] as String?,
      destinationFolder: json['destinationFolder'] as String?,
      isRunning: json['isRunning'] as bool?,
      isCancelled: json['isCancelled'] as bool?,
      isCompleted: json['isCompleted'] as bool?,
      isDeadLink: json['isDeadLink'] as bool?,
      episodeIndex: (json['episodeIndex'] as num?)?.toInt(),
      progress: (json['progress'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      speedUnit: json['speedUnit'] as String?,
      averageSpeed: (json['averageSpeed'] as num?)?.toDouble(),
      averageSpeedUnit: json['averageSpeedUnit'] as String?,
      sizeReceived: (json['sizeReceived'] as num?)?.toDouble(),
      sizeUnit: json['sizeUnit'] as String?,
      totalSize: (json['totalSize'] as num?)?.toDouble(),
      totalSizeUnit: json['totalSizeUnit'] as String?,
      estimatedTime: (json['estimatedTime'] as num?)?.toInt(),
      estimatedTimeUnit: json['estimatedTimeUnit'] as String?,
    );

Map<String, dynamic> _$DownloadDtoToJson(DownloadDto instance) =>
    <String, dynamic>{
      if (instance.name case final value?) 'name': value,
      if (instance.fileName case final value?) 'fileName': value,
      if (instance.url case final value?) 'url': value,
      if (instance.destinationFolder case final value?)
        'destinationFolder': value,
      if (instance.isRunning case final value?) 'isRunning': value,
      if (instance.isCancelled case final value?) 'isCancelled': value,
      if (instance.isCompleted case final value?) 'isCompleted': value,
      if (instance.isDeadLink case final value?) 'isDeadLink': value,
      if (instance.episodeIndex case final value?) 'episodeIndex': value,
      if (instance.progress case final value?) 'progress': value,
      if (instance.speed case final value?) 'speed': value,
      if (instance.speedUnit case final value?) 'speedUnit': value,
      if (instance.averageSpeed case final value?) 'averageSpeed': value,
      if (instance.averageSpeedUnit case final value?)
        'averageSpeedUnit': value,
      if (instance.sizeReceived case final value?) 'sizeReceived': value,
      if (instance.sizeUnit case final value?) 'sizeUnit': value,
      if (instance.totalSize case final value?) 'totalSize': value,
      if (instance.totalSizeUnit case final value?) 'totalSizeUnit': value,
      if (instance.estimatedTime case final value?) 'estimatedTime': value,
      if (instance.estimatedTimeUnit case final value?)
        'estimatedTimeUnit': value,
    };

MediaServerInviteRequest _$MediaServerInviteRequestFromJson(
        Map<String, dynamic> json) =>
    MediaServerInviteRequest(
      email: json['email'] as String?,
      libraries: (json['libraries'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );

Map<String, dynamic> _$MediaServerInviteRequestToJson(
        MediaServerInviteRequest instance) =>
    <String, dynamic>{
      if (instance.email case final value?) 'email': value,
      if (instance.libraries case final value?) 'libraries': value,
    };

ScheduledJob _$ScheduledJobFromJson(Map<String, dynamic> json) => ScheduledJob(
      id: json['id'] as String?,
      type: json['type'] as String?,
      status: json['status'] as String?,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
    );

Map<String, dynamic> _$ScheduledJobToJson(ScheduledJob instance) =>
    <String, dynamic>{
      if (instance.id case final value?) 'id': value,
      if (instance.type case final value?) 'type': value,
      if (instance.status case final value?) 'status': value,
      if (instance.startedAt?.toIso8601String() case final value?)
        'startedAt': value,
    };

TriggerJobRequest _$TriggerJobRequestFromJson(Map<String, dynamic> json) =>
    TriggerJobRequest(
      jobType: json['jobType'] as String?,
    );

Map<String, dynamic> _$TriggerJobRequestToJson(TriggerJobRequest instance) =>
    <String, dynamic>{
      if (instance.jobType case final value?) 'jobType': value,
    };

LiveTvChannelDto _$LiveTvChannelDtoFromJson(Map<String, dynamic> json) =>
    LiveTvChannelDto(
      id: json['id'] as String?,
      name: json['name'] as String?,
      iconUrl: json['iconUrl'] as String?,
      category: liveTvChannelCategoryNullableFromJson(json['category']),
      streamUrl: json['streamUrl'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$LiveTvChannelDtoToJson(LiveTvChannelDto instance) =>
    <String, dynamic>{
      if (instance.id case final value?) 'id': value,
      if (instance.name case final value?) 'name': value,
      if (instance.iconUrl case final value?) 'iconUrl': value,
      if (liveTvChannelCategoryNullableToJson(instance.category)
          case final value?)
        'category': value,
      if (instance.streamUrl case final value?) 'streamUrl': value,
      if (instance.createdAt?.toIso8601String() case final value?)
        'createdAt': value,
      if (instance.updatedAt?.toIso8601String() case final value?)
        'updatedAt': value,
    };

DebridLinkResult _$DebridLinkResultFromJson(Map<String, dynamic> json) =>
    DebridLinkResult(
      isSuccess: json['isSuccess'] as bool?,
      error: json['error'] as String?,
      debridedUrl: json['debridedUrl'] as String?,
    );

Map<String, dynamic> _$DebridLinkResultToJson(DebridLinkResult instance) =>
    <String, dynamic>{
      if (instance.isSuccess case final value?) 'isSuccess': value,
      if (instance.error case final value?) 'error': value,
      if (instance.debridedUrl case final value?) 'debridedUrl': value,
    };

DebridLinkRequest _$DebridLinkRequestFromJson(Map<String, dynamic> json) =>
    DebridLinkRequest(
      link: json['link'] as String?,
    );

Map<String, dynamic> _$DebridLinkRequestToJson(DebridLinkRequest instance) =>
    <String, dynamic>{
      if (instance.link case final value?) 'link': value,
    };

RemoveLinkResult _$RemoveLinkResultFromJson(Map<String, dynamic> json) =>
    RemoveLinkResult(
      isSuccess: json['isSuccess'] as bool?,
      error: json['error'] as String?,
      removedLink: json['removedLink'] as String?,
    );

Map<String, dynamic> _$RemoveLinkResultToJson(RemoveLinkResult instance) =>
    <String, dynamic>{
      if (instance.isSuccess case final value?) 'isSuccess': value,
      if (instance.error case final value?) 'error': value,
      if (instance.removedLink case final value?) 'removedLink': value,
    };

RemoveCorruptedFileResult _$RemoveCorruptedFileResultFromJson(
        Map<String, dynamic> json) =>
    RemoveCorruptedFileResult(
      isSuccess: json['isSuccess'] as bool?,
      error: json['error'] as String?,
      episodesRemoved: (json['episodesRemoved'] as num?)?.toInt(),
    );

Map<String, dynamic> _$RemoveCorruptedFileResultToJson(
        RemoveCorruptedFileResult instance) =>
    <String, dynamic>{
      if (instance.isSuccess case final value?) 'isSuccess': value,
      if (instance.error case final value?) 'error': value,
      if (instance.episodesRemoved case final value?) 'episodesRemoved': value,
    };

RemoveCorruptedFileRequest _$RemoveCorruptedFileRequestFromJson(
        Map<String, dynamic> json) =>
    RemoveCorruptedFileRequest(
      crawlLinkId: json['crawlLinkId'] as String?,
      episodeIndexes: (json['episodeIndexes'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
    );

Map<String, dynamic> _$RemoveCorruptedFileRequestToJson(
        RemoveCorruptedFileRequest instance) =>
    <String, dynamic>{
      if (instance.crawlLinkId case final value?) 'crawlLinkId': value,
      if (instance.episodeIndexes case final value?) 'episodeIndexes': value,
    };

IProvider _$IProviderFromJson(Map<String, dynamic> json) => IProvider(
      id: json['id'] as String?,
      displayName: json['displayName'] as String?,
      name: json['name'] as String?,
      url: json['url'] as String?,
      enabled: json['enabled'] as bool?,
      searchEnabled: json['searchEnabled'] as bool?,
      isManuallyDisabled: json['isManuallyDisabled'] as bool?,
      crawlLinksRef: (json['crawlLinksRef'] as List<dynamic>?)
              ?.map((e) => ICrawlLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$IProviderToJson(IProvider instance) => <String, dynamic>{
      if (instance.id case final value?) 'id': value,
      if (instance.displayName case final value?) 'displayName': value,
      if (instance.name case final value?) 'name': value,
      if (instance.url case final value?) 'url': value,
      if (instance.enabled case final value?) 'enabled': value,
      if (instance.searchEnabled case final value?) 'searchEnabled': value,
      if (instance.isManuallyDisabled case final value?)
        'isManuallyDisabled': value,
      if (instance.crawlLinksRef?.map((e) => e.toJson()).toList()
          case final value?)
        'crawlLinksRef': value,
    };

ICrawlLink _$ICrawlLinkFromJson(Map<String, dynamic> json) => ICrawlLink(
      id: json['id'] as String?,
      mediaId: json['mediaId'] as String?,
      name: json['name'] as String?,
      secondName: json['secondName'] as String?,
      formattedName: json['formattedName'] as String?,
      providerId: json['providerId'] as String?,
      providerRef: json['providerRef'] == null
          ? null
          : IProvider.fromJson(json['providerRef'] as Map<String, dynamic>),
      providerItemId: json['providerItemId'] as String?,
      providerCategory: json['providerCategory'] as String?,
      category: mediaCategoryNullableFromJson(json['category']),
      url: json['url'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      airedEpisodesCount: (json['airedEpisodesCount'] as num?)?.toInt(),
      totalEpisodesCount: (json['totalEpisodesCount'] as num?)?.toInt(),
      season: (json['season'] as num?)?.toInt(),
      quality: json['quality'] as String?,
      version: json['version'] as String?,
      productionYear: (json['productionYear'] as num?)?.toInt(),
      lastChecked: json['lastChecked'] == null
          ? null
          : DateTime.parse(json['lastChecked'] as String),
      downloaded: json['downloaded'] as bool?,
      hasError: json['hasError'] as bool?,
      createdBy: json['createdBy'] as String?,
      authorId: json['authorId'] as String?,
      isEnabled: json['isEnabled'] as bool?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      origin: creationOriginNullableFromJson(json['origin']),
      mediaServerType: mediaServerTypeNullableFromJson(json['mediaServerType']),
      runningCrawl: json['runningCrawl'],
    );

Map<String, dynamic> _$ICrawlLinkToJson(ICrawlLink instance) =>
    <String, dynamic>{
      if (instance.id case final value?) 'id': value,
      if (instance.mediaId case final value?) 'mediaId': value,
      if (instance.name case final value?) 'name': value,
      if (instance.secondName case final value?) 'secondName': value,
      if (instance.formattedName case final value?) 'formattedName': value,
      if (instance.providerId case final value?) 'providerId': value,
      if (instance.providerRef?.toJson() case final value?)
        'providerRef': value,
      if (instance.providerItemId case final value?) 'providerItemId': value,
      if (instance.providerCategory case final value?)
        'providerCategory': value,
      if (mediaCategoryNullableToJson(instance.category) case final value?)
        'category': value,
      if (instance.url case final value?) 'url': value,
      if (instance.thumbnailUrl case final value?) 'thumbnailUrl': value,
      if (instance.airedEpisodesCount case final value?)
        'airedEpisodesCount': value,
      if (instance.totalEpisodesCount case final value?)
        'totalEpisodesCount': value,
      if (instance.season case final value?) 'season': value,
      if (instance.quality case final value?) 'quality': value,
      if (instance.version case final value?) 'version': value,
      if (instance.productionYear case final value?) 'productionYear': value,
      if (instance.lastChecked?.toIso8601String() case final value?)
        'lastChecked': value,
      if (instance.downloaded case final value?) 'downloaded': value,
      if (instance.hasError case final value?) 'hasError': value,
      if (instance.createdBy case final value?) 'createdBy': value,
      if (instance.authorId case final value?) 'authorId': value,
      if (instance.isEnabled case final value?) 'isEnabled': value,
      if (instance.createdAt?.toIso8601String() case final value?)
        'createdAt': value,
      if (creationOriginNullableToJson(instance.origin) case final value?)
        'origin': value,
      if (mediaServerTypeNullableToJson(instance.mediaServerType)
          case final value?)
        'mediaServerType': value,
      if (instance.runningCrawl case final value?) 'runningCrawl': value,
    };

IScheduledCrawl _$IScheduledCrawlFromJson(Map<String, dynamic> json) =>
    IScheduledCrawl(
      id: json['id'] as String?,
      crawlLinkId: json['crawlLinkId'] as String?,
      jobId: json['jobId'] as String?,
      crawlLinkRef: json['crawlLinkRef'] == null
          ? null
          : ICrawlLink.fromJson(json['crawlLinkRef'] as Map<String, dynamic>),
      name: json['name'] as String?,
      mediaName: json['mediaName'] as String?,
      mediaFolder: json['mediaFolder'] as String?,
      url: json['url'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      downloadLinks: (json['downloadLinks'] as List<dynamic>?)
              ?.map((e) => DownloadLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      extractedLinks: (json['extractedLinks'] as List<dynamic>?)
              ?.map((e) => DownloadLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      failedEpisodes: (json['failedEpisodes'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      successfulDownloads: (json['successfulDownloads'] as num?)?.toInt(),
      skippedDownloads: (json['skippedDownloads'] as num?)?.toInt(),
      status: crawlStatusNullableFromJson(json['status']),
      hasError: json['hasError'] as bool?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      extractedItemInfo: json['extractedItemInfo'],
    );

Map<String, dynamic> _$IScheduledCrawlToJson(IScheduledCrawl instance) =>
    <String, dynamic>{
      if (instance.id case final value?) 'id': value,
      if (instance.crawlLinkId case final value?) 'crawlLinkId': value,
      if (instance.jobId case final value?) 'jobId': value,
      if (instance.crawlLinkRef?.toJson() case final value?)
        'crawlLinkRef': value,
      if (instance.name case final value?) 'name': value,
      if (instance.mediaName case final value?) 'mediaName': value,
      if (instance.mediaFolder case final value?) 'mediaFolder': value,
      if (instance.url case final value?) 'url': value,
      if (instance.thumbnailUrl case final value?) 'thumbnailUrl': value,
      if (instance.downloadLinks?.map((e) => e.toJson()).toList()
          case final value?)
        'downloadLinks': value,
      if (instance.extractedLinks?.map((e) => e.toJson()).toList()
          case final value?)
        'extractedLinks': value,
      if (instance.failedEpisodes case final value?) 'failedEpisodes': value,
      if (instance.successfulDownloads case final value?)
        'successfulDownloads': value,
      if (instance.skippedDownloads case final value?)
        'skippedDownloads': value,
      if (crawlStatusNullableToJson(instance.status) case final value?)
        'status': value,
      if (instance.hasError case final value?) 'hasError': value,
      if (instance.createdAt?.toIso8601String() case final value?)
        'createdAt': value,
      if (instance.extractedItemInfo case final value?)
        'extractedItemInfo': value,
    };

DownloadLink _$DownloadLinkFromJson(Map<String, dynamic> json) => DownloadLink(
      index: (json['index'] as num?)?.toInt(),
      link: json['link'] as String?,
      version: json['version'] as String?,
      qualityLabel: json['quality_label'] as String?,
      quality: mediaQualityNullableFromJson(json['quality']),
      size: (json['size'] as num?)?.toDouble(),
      sizeUnit: json['size_unit'] as String?,
      fileHost: json['file_host'] as String?,
      isFullSeason: json['is_full_season'] as bool?,
    );

Map<String, dynamic> _$DownloadLinkToJson(DownloadLink instance) =>
    <String, dynamic>{
      if (instance.index case final value?) 'index': value,
      if (instance.link case final value?) 'link': value,
      if (instance.version case final value?) 'version': value,
      if (instance.qualityLabel case final value?) 'quality_label': value,
      if (mediaQualityNullableToJson(instance.quality) case final value?)
        'quality': value,
      if (instance.size case final value?) 'size': value,
      if (instance.sizeUnit case final value?) 'size_unit': value,
      if (instance.fileHost case final value?) 'file_host': value,
      if (instance.isFullSeason case final value?) 'is_full_season': value,
    };

IExtractedItemInfo _$IExtractedItemInfoFromJson(Map<String, dynamic> json) =>
    IExtractedItemInfo(
      provider: json['provider'] == null
          ? null
          : IProvider.fromJson(json['provider'] as Map<String, dynamic>),
      title: json['title'] as String?,
      originalTitle: json['originalTitle'] as String?,
      relativeUrl: json['relativeUrl'] as String?,
      version: json['version'] as String?,
      providerId: json['providerId'] as String?,
      season: (json['season'] as num?)?.toInt(),
      airedEpisodesCount: (json['airedEpisodesCount'] as num?)?.toInt(),
      totalEpisodesCount: (json['totalEpisodesCount'] as num?)?.toInt(),
      seasonCount: (json['seasonCount'] as num?)?.toInt(),
      quality: json['quality'] as String?,
      providerCategory: json['providerCategory'] as String?,
      productionYear: (json['productionYear'] as num?)?.toInt(),
      category: mediaCategoryNullableFromJson(json['category']),
      downloadLinks: (json['downloadLinks'] as List<dynamic>?)
              ?.map((e) => DownloadLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );

Map<String, dynamic> _$IExtractedItemInfoToJson(IExtractedItemInfo instance) =>
    <String, dynamic>{
      if (instance.provider?.toJson() case final value?) 'provider': value,
      if (instance.title case final value?) 'title': value,
      if (instance.originalTitle case final value?) 'originalTitle': value,
      if (instance.relativeUrl case final value?) 'relativeUrl': value,
      if (instance.version case final value?) 'version': value,
      if (instance.providerId case final value?) 'providerId': value,
      if (instance.season case final value?) 'season': value,
      if (instance.airedEpisodesCount case final value?)
        'airedEpisodesCount': value,
      if (instance.totalEpisodesCount case final value?)
        'totalEpisodesCount': value,
      if (instance.seasonCount case final value?) 'seasonCount': value,
      if (instance.quality case final value?) 'quality': value,
      if (instance.providerCategory case final value?)
        'providerCategory': value,
      if (instance.productionYear case final value?) 'productionYear': value,
      if (mediaCategoryNullableToJson(instance.category) case final value?)
        'category': value,
      if (instance.downloadLinks?.map((e) => e.toJson()).toList()
          case final value?)
        'downloadLinks': value,
      if (instance.thumbnailUrl case final value?) 'thumbnailUrl': value,
    };

ISearchFilter _$ISearchFilterFromJson(Map<String, dynamic> json) =>
    ISearchFilter(
      label: json['label'] as String?,
      name: json['name'] as String?,
      $value: json['value'] as String?,
      valueLabel: json['valueLabel'] as String?,
      options: (json['options'] as List<dynamic>?)
              ?.map((e) =>
                  ISearchFilterOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$ISearchFilterToJson(ISearchFilter instance) =>
    <String, dynamic>{
      if (instance.label case final value?) 'label': value,
      if (instance.name case final value?) 'name': value,
      if (instance.$value case final value?) 'value': value,
      if (instance.valueLabel case final value?) 'valueLabel': value,
      if (instance.options?.map((e) => e.toJson()).toList() case final value?)
        'options': value,
    };

ISearchFilterOption _$ISearchFilterOptionFromJson(Map<String, dynamic> json) =>
    ISearchFilterOption(
      label: json['label'] as String?,
      $value: json['value'] as String?,
    );

Map<String, dynamic> _$ISearchFilterOptionToJson(
        ISearchFilterOption instance) =>
    <String, dynamic>{
      if (instance.label case final value?) 'label': value,
      if (instance.$value case final value?) 'value': value,
    };

PaginatedResponseOfProviderSearchItemDto
    _$PaginatedResponseOfProviderSearchItemDtoFromJson(
            Map<String, dynamic> json) =>
        PaginatedResponseOfProviderSearchItemDto(
          currentPage: (json['currentPage'] as num?)?.toInt(),
          totalPages: (json['totalPages'] as num?)?.toInt(),
          pageSize: (json['pageSize'] as num?)?.toInt(),
          totalCount: (json['totalCount'] as num?)?.toInt(),
          items: (json['items'] as List<dynamic>?)
                  ?.map((e) =>
                      ProviderSearchItemDto.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [],
        );

Map<String, dynamic> _$PaginatedResponseOfProviderSearchItemDtoToJson(
        PaginatedResponseOfProviderSearchItemDto instance) =>
    <String, dynamic>{
      if (instance.currentPage case final value?) 'currentPage': value,
      if (instance.totalPages case final value?) 'totalPages': value,
      if (instance.pageSize case final value?) 'pageSize': value,
      if (instance.totalCount case final value?) 'totalCount': value,
      if (instance.items?.map((e) => e.toJson()).toList() case final value?)
        'items': value,
    };

ProviderSearchItemDto _$ProviderSearchItemDtoFromJson(
        Map<String, dynamic> json) =>
    ProviderSearchItemDto(
      title: json['title'] as String?,
      description: json['description'] as String?,
      url: json['url'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      season: (json['season'] as num?)?.toInt(),
      quality: json['quality'] as String?,
      language: json['language'] as String?,
    );

Map<String, dynamic> _$ProviderSearchItemDtoToJson(
        ProviderSearchItemDto instance) =>
    <String, dynamic>{
      if (instance.title case final value?) 'title': value,
      if (instance.description case final value?) 'description': value,
      if (instance.url case final value?) 'url': value,
      if (instance.thumbnailUrl case final value?) 'thumbnailUrl': value,
      if (instance.season case final value?) 'season': value,
      if (instance.quality case final value?) 'quality': value,
      if (instance.language case final value?) 'language': value,
    };

ApiMediaSearchRequest _$ApiMediaSearchRequestFromJson(
        Map<String, dynamic> json) =>
    ApiMediaSearchRequest(
      filters: (json['filters'] as List<dynamic>?)
              ?.map((e) => SearchFilter.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      page: (json['page'] as num?)?.toInt(),
      pageSize: (json['pageSize'] as num?)?.toInt(),
      query: json['query'] as String?,
      category: mediaCategoryNullableFromJson(json['category']),
      exactMatch: json['exactMatch'] as bool?,
      minScore: (json['minScore'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$ApiMediaSearchRequestToJson(
        ApiMediaSearchRequest instance) =>
    <String, dynamic>{
      if (instance.filters?.map((e) => e.toJson()).toList() case final value?)
        'filters': value,
      if (instance.page case final value?) 'page': value,
      if (instance.pageSize case final value?) 'pageSize': value,
      if (instance.query case final value?) 'query': value,
      if (mediaCategoryNullableToJson(instance.category) case final value?)
        'category': value,
      if (instance.exactMatch case final value?) 'exactMatch': value,
      if (instance.minScore case final value?) 'minScore': value,
    };

SearchFilter _$SearchFilterFromJson(Map<String, dynamic> json) => SearchFilter(
      label: json['label'] as String?,
      name: json['name'] as String?,
      $value: json['value'] as String?,
      valueLabel: json['valueLabel'] as String?,
      options: (json['options'] as List<dynamic>?)
              ?.map((e) =>
                  ISearchFilterOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$SearchFilterToJson(SearchFilter instance) =>
    <String, dynamic>{
      if (instance.label case final value?) 'label': value,
      if (instance.name case final value?) 'name': value,
      if (instance.$value case final value?) 'value': value,
      if (instance.valueLabel case final value?) 'valueLabel': value,
      if (instance.options?.map((e) => e.toJson()).toList() case final value?)
        'options': value,
    };

MediaSearchRequest _$MediaSearchRequestFromJson(Map<String, dynamic> json) =>
    MediaSearchRequest(
      query: json['query'] as String?,
      category: mediaCategoryNullableFromJson(json['category']),
      exactMatch: json['exactMatch'] as bool?,
      minScore: (json['minScore'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$MediaSearchRequestToJson(MediaSearchRequest instance) =>
    <String, dynamic>{
      if (instance.query case final value?) 'query': value,
      if (mediaCategoryNullableToJson(instance.category) case final value?)
        'category': value,
      if (instance.exactMatch case final value?) 'exactMatch': value,
      if (instance.minScore case final value?) 'minScore': value,
    };

ApiTorrentsUploadPost$RequestBody _$ApiTorrentsUploadPost$RequestBodyFromJson(
        Map<String, dynamic> json) =>
    ApiTorrentsUploadPost$RequestBody(
      file: json['file'] as String?,
      mediaName: json['mediaName'] as String?,
      mediaCategory: mediaCategoryNullableFromJson(json['mediaCategory']),
      authorId: json['authorId'] as String?,
    );

Map<String, dynamic> _$ApiTorrentsUploadPost$RequestBodyToJson(
        ApiTorrentsUploadPost$RequestBody instance) =>
    <String, dynamic>{
      if (instance.file case final value?) 'file': value,
      if (instance.mediaName case final value?) 'mediaName': value,
      if (mediaCategoryNullableToJson(instance.mediaCategory) case final value?)
        'mediaCategory': value,
      if (instance.authorId case final value?) 'authorId': value,
    };
