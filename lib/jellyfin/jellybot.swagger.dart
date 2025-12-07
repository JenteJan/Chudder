// ignore_for_file: type=lint

import 'package:json_annotation/json_annotation.dart';
import 'package:json_annotation/json_annotation.dart' as json;
import 'package:collection/collection.dart';
import 'dart:convert';

import 'package:chopper/chopper.dart';

import 'client_mapping.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show MultipartFile;
import 'package:chopper/chopper.dart' as chopper;
import 'jellybot.enums.swagger.dart' as enums;
export 'jellybot.enums.swagger.dart';

part 'jellybot.swagger.chopper.dart';
part 'jellybot.swagger.g.dart';

// **************************************************************************
// SwaggerChopperGenerator
// **************************************************************************

@ChopperApi()
abstract class Jellybot extends ChopperService {
  static Jellybot create({
    ChopperClient? client,
    http.Client? httpClient,
    Authenticator? authenticator,
    ErrorConverter? errorConverter,
    Converter? converter,
    Uri? baseUrl,
    List<Interceptor>? interceptors,
  }) {
    if (client != null) {
      return _$Jellybot(client);
    }

    final newClient = ChopperClient(
      services: [_$Jellybot()],
      converter: converter ?? $JsonSerializableConverter(),
      interceptors: interceptors ?? [],
      client: httpClient,
      authenticator: authenticator,
      errorConverter: errorConverter,
      baseUrl: baseUrl,
    );
    return _$Jellybot(newClient);
  }

  ///
  Future<chopper.Response> apiHealthGet() {
    return _apiHealthGet();
  }

  ///
  @GET(path: '/api/health')
  Future<chopper.Response> _apiHealthGet();

  ///
  ///@param date
  Future<chopper.Response<String>> apiLogsGet({DateTime? date}) {
    return _apiLogsGet(date: date);
  }

  ///
  ///@param date
  @GET(path: '/api/logs')
  Future<chopper.Response<String>> _apiLogsGet({@Query('date') DateTime? date});

  ///Gets added crawl links, the results are paginated.
  ///@param page The page index.
  ///@param limit The number of elements to return.
  Future<chopper.Response<PaginatedResponseOfCrawlLinkDto>> apiCrawlLinksGet({
    int? page,
    int? limit,
  }) {
    generatedMapping.putIfAbsent(
      PaginatedResponseOfCrawlLinkDto,
      () => PaginatedResponseOfCrawlLinkDto.fromJsonFactory,
    );

    return _apiCrawlLinksGet(page: page, limit: limit);
  }

  ///Gets added crawl links, the results are paginated.
  ///@param page The page index.
  ///@param limit The number of elements to return.
  @GET(path: '/api/crawl-links')
  Future<chopper.Response<PaginatedResponseOfCrawlLinkDto>> _apiCrawlLinksGet({
    @Query('page') int? page,
    @Query('limit') int? limit,
  });

  ///Adds a crawl link, it will return the extracted crawl link. You will need to
  ///confirm the link by calling the confirm-add endpoint and send the crawl link object.
  ///It allows for the third-party to edit the details of the crawl link before saving it.
  Future<chopper.Response<CrawlLinkDto>> apiCrawlLinksPost({
    required ExtractMediaRequest? body,
  }) {
    generatedMapping.putIfAbsent(
      CrawlLinkDto,
      () => CrawlLinkDto.fromJsonFactory,
    );

    return _apiCrawlLinksPost(body: body);
  }

  ///Adds a crawl link, it will return the extracted crawl link. You will need to
  ///confirm the link by calling the confirm-add endpoint and send the crawl link object.
  ///It allows for the third-party to edit the details of the crawl link before saving it.
  @POST(path: '/api/crawl-links', optionalBody: true)
  Future<chopper.Response<CrawlLinkDto>> _apiCrawlLinksPost({
    @Body() required ExtractMediaRequest? body,
  });

  ///Deletes a crawl link.
  ///@param id The id of the crawl link to delete.
  Future<chopper.Response> apiCrawlLinksDelete({String? id}) {
    return _apiCrawlLinksDelete(id: id);
  }

  ///Deletes a crawl link.
  ///@param id The id of the crawl link to delete.
  @DELETE(path: '/api/crawl-links')
  Future<chopper.Response> _apiCrawlLinksDelete({@Query('id') String? id});

  ///Saves a crawl link to the database, this endpoint should be called after calling the add link endpoint.
  Future<chopper.Response<CrawlLinkDto>> apiCrawlLinksConfirmAddPost({
    required ExtractMediaConfirmationRequest? body,
  }) {
    generatedMapping.putIfAbsent(
      CrawlLinkDto,
      () => CrawlLinkDto.fromJsonFactory,
    );

    return _apiCrawlLinksConfirmAddPost(body: body);
  }

  ///Saves a crawl link to the database, this endpoint should be called after calling the add link endpoint.
  @POST(path: '/api/crawl-links/confirm-add', optionalBody: true)
  Future<chopper.Response<CrawlLinkDto>> _apiCrawlLinksConfirmAddPost({
    @Body() required ExtractMediaConfirmationRequest? body,
  });

  ///Changes the name of the show for an added link.
  ///@param crawlLinkId The id of the crawl link to rename.
  Future<chopper.Response<RenameLinkResult>> apiCrawlLinksCrawlLinkIdRenamePut({
    required String? crawlLinkId,
    required RenameCrawlLinkRequest? body,
  }) {
    generatedMapping.putIfAbsent(
      RenameLinkResult,
      () => RenameLinkResult.fromJsonFactory,
    );

    return _apiCrawlLinksCrawlLinkIdRenamePut(
      crawlLinkId: crawlLinkId,
      body: body,
    );
  }

  ///Changes the name of the show for an added link.
  ///@param crawlLinkId The id of the crawl link to rename.
  @PUT(path: '/api/crawl-links/{crawlLinkId}/rename', optionalBody: true)
  Future<chopper.Response<RenameLinkResult>>
  _apiCrawlLinksCrawlLinkIdRenamePut({
    @Path('crawlLinkId') required String? crawlLinkId,
    @Body() required RenameCrawlLinkRequest? body,
  });

  ///Downloads the debrided file from a specified file host and URL.
  ///@param fileHost The name of the file hosting service.
  ///@param url The URL of the file to be debrided.
  Future<chopper.Response<String>> apiDebridFileHostGet({
    required String? fileHost,
    String? url,
  }) {
    return _apiDebridFileHostGet(fileHost: fileHost, url: url);
  }

  ///Downloads the debrided file from a specified file host and URL.
  ///@param fileHost The name of the file hosting service.
  ///@param url The URL of the file to be debrided.
  @GET(path: '/api/debrid/{fileHost}')
  Future<chopper.Response<String>> _apiDebridFileHostGet({
    @Path('fileHost') required String? fileHost,
    @Query('url') String? url,
  });

  ///Gets all running or queued downloads
  Future<chopper.Response<List<DownloadDto>>> apiDownloadsGet() {
    generatedMapping.putIfAbsent(
      DownloadDto,
      () => DownloadDto.fromJsonFactory,
    );

    return _apiDownloadsGet();
  }

  ///Gets all running or queued downloads
  @GET(path: '/api/downloads')
  Future<chopper.Response<List<DownloadDto>>> _apiDownloadsGet();

  ///Cancels a download by its file url
  ///@param url The file url
  Future<chopper.Response> apiDownloadsDelete({String? url}) {
    return _apiDownloadsDelete(url: url);
  }

  ///Cancels a download by its file url
  ///@param url The file url
  @DELETE(path: '/api/downloads')
  Future<chopper.Response> _apiDownloadsDelete({@Query('url') String? url});

  ///
  Future<chopper.Response<String>> apiIptvAtlasProGet() {
    return _apiIptvAtlasProGet();
  }

  ///
  @GET(path: '/api/iptv/atlas-pro')
  Future<chopper.Response<String>> _apiIptvAtlasProGet();

  ///
  Future<chopper.Response<List<ScheduledJob>>> apiJobsGet() {
    generatedMapping.putIfAbsent(
      ScheduledJob,
      () => ScheduledJob.fromJsonFactory,
    );

    return _apiJobsGet();
  }

  ///
  @GET(path: '/api/jobs')
  Future<chopper.Response<List<ScheduledJob>>> _apiJobsGet();

  ///Trigger a cron job
  Future<chopper.Response> apiJobsPost({required TriggerJobRequest? body}) {
    return _apiJobsPost(body: body);
  }

  ///Trigger a cron job
  @POST(path: '/api/jobs', optionalBody: true)
  Future<chopper.Response> _apiJobsPost({
    @Body() required TriggerJobRequest? body,
  });

  ///Cancels a running cron job
  Future<chopper.Response> apiJobsDelete({required ScheduledJob? body}) {
    return _apiJobsDelete(body: body);
  }

  ///Cancels a running cron job
  @DELETE(path: '/api/jobs')
  Future<chopper.Response> _apiJobsDelete({
    @Body() required ScheduledJob? body,
  });

  ///
  Future<chopper.Response<String>> apiMegaDebridCallbackPost() {
    return _apiMegaDebridCallbackPost();
  }

  ///
  @POST(path: '/api/mega-debrid/callback', optionalBody: true)
  Future<chopper.Response<String>> _apiMegaDebridCallbackPost();

  ///Gets the list of enabled providers.
  ///@param searchEnabled Indicates if it should return only providers which have the search functionality.
  Future<chopper.Response<List<IProvider>>> apiProvidersGet({
    bool? searchEnabled,
  }) {
    generatedMapping.putIfAbsent(IProvider, () => IProvider.fromJsonFactory);

    return _apiProvidersGet(searchEnabled: searchEnabled);
  }

  ///Gets the list of enabled providers.
  ///@param searchEnabled Indicates if it should return only providers which have the search functionality.
  @GET(path: '/api/providers')
  Future<chopper.Response<List<IProvider>>> _apiProvidersGet({
    @Query('searchEnabled') bool? searchEnabled,
  });

  ///Gets the available search filters for a given provider and a media category
  ///@param providerId
  ///@param mediaCategory
  Future<chopper.Response<List<ISearchFilter>>>
  apiProvidersProviderIdSearchFiltersGet({
    required String? providerId,
    enums.MediaCategory? mediaCategory,
  }) {
    generatedMapping.putIfAbsent(
      ISearchFilter,
      () => ISearchFilter.fromJsonFactory,
    );

    return _apiProvidersProviderIdSearchFiltersGet(
      providerId: providerId,
      mediaCategory: mediaCategory?.value?.toString(),
    );
  }

  ///Gets the available search filters for a given provider and a media category
  ///@param providerId
  ///@param mediaCategory
  @GET(path: '/api/providers/{providerId}/search-filters')
  Future<chopper.Response<List<ISearchFilter>>>
  _apiProvidersProviderIdSearchFiltersGet({
    @Path('providerId') required String? providerId,
    @Query('mediaCategory') String? mediaCategory,
  });

  ///Search the provider website and gets the results. The results are paginated.
  ///@param providerId The provider id on which to perform the search
  Future<chopper.Response<PaginatedResponseOfProviderSearchItemDto>>
  apiProvidersProviderIdSearchPost({
    required String? providerId,
    required ApiMediaSearchRequest? body,
  }) {
    generatedMapping.putIfAbsent(
      PaginatedResponseOfProviderSearchItemDto,
      () => PaginatedResponseOfProviderSearchItemDto.fromJsonFactory,
    );

    return _apiProvidersProviderIdSearchPost(
      providerId: providerId,
      body: body,
    );
  }

  ///Search the provider website and gets the results. The results are paginated.
  ///@param providerId The provider id on which to perform the search
  @POST(path: '/api/providers/{providerId}/search', optionalBody: true)
  Future<chopper.Response<PaginatedResponseOfProviderSearchItemDto>>
  _apiProvidersProviderIdSearchPost({
    @Path('providerId') required String? providerId,
    @Body() required ApiMediaSearchRequest? body,
  });
}

@JsonSerializable(explicitToJson: true)
class PaginatedResponseOfCrawlLinkDto {
  const PaginatedResponseOfCrawlLinkDto({
    this.currentPage,
    this.totalPages,
    this.pageSize,
    this.totalCount,
    this.items,
  });

  factory PaginatedResponseOfCrawlLinkDto.fromJson(Map<String, dynamic> json) =>
      _$PaginatedResponseOfCrawlLinkDtoFromJson(json);

  static const toJsonFactory = _$PaginatedResponseOfCrawlLinkDtoToJson;
  Map<String, dynamic> toJson() =>
      _$PaginatedResponseOfCrawlLinkDtoToJson(this);

  @JsonKey(name: 'currentPage', includeIfNull: false)
  final int? currentPage;
  @JsonKey(name: 'totalPages', includeIfNull: false)
  final int? totalPages;
  @JsonKey(name: 'pageSize', includeIfNull: false)
  final int? pageSize;
  @JsonKey(name: 'totalCount', includeIfNull: false)
  final int? totalCount;
  @JsonKey(name: 'items', includeIfNull: false, defaultValue: <CrawlLinkDto>[])
  final List<CrawlLinkDto>? items;
  static const fromJsonFactory = _$PaginatedResponseOfCrawlLinkDtoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PaginatedResponseOfCrawlLinkDto &&
            (identical(other.currentPage, currentPage) ||
                const DeepCollectionEquality().equals(
                  other.currentPage,
                  currentPage,
                )) &&
            (identical(other.totalPages, totalPages) ||
                const DeepCollectionEquality().equals(
                  other.totalPages,
                  totalPages,
                )) &&
            (identical(other.pageSize, pageSize) ||
                const DeepCollectionEquality().equals(
                  other.pageSize,
                  pageSize,
                )) &&
            (identical(other.totalCount, totalCount) ||
                const DeepCollectionEquality().equals(
                  other.totalCount,
                  totalCount,
                )) &&
            (identical(other.items, items) ||
                const DeepCollectionEquality().equals(other.items, items)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(currentPage) ^
      const DeepCollectionEquality().hash(totalPages) ^
      const DeepCollectionEquality().hash(pageSize) ^
      const DeepCollectionEquality().hash(totalCount) ^
      const DeepCollectionEquality().hash(items) ^
      runtimeType.hashCode;
}

extension $PaginatedResponseOfCrawlLinkDtoExtension
    on PaginatedResponseOfCrawlLinkDto {
  PaginatedResponseOfCrawlLinkDto copyWith({
    int? currentPage,
    int? totalPages,
    int? pageSize,
    int? totalCount,
    List<CrawlLinkDto>? items,
  }) {
    return PaginatedResponseOfCrawlLinkDto(
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      pageSize: pageSize ?? this.pageSize,
      totalCount: totalCount ?? this.totalCount,
      items: items ?? this.items,
    );
  }

  PaginatedResponseOfCrawlLinkDto copyWithWrapped({
    Wrapped<int?>? currentPage,
    Wrapped<int?>? totalPages,
    Wrapped<int?>? pageSize,
    Wrapped<int?>? totalCount,
    Wrapped<List<CrawlLinkDto>?>? items,
  }) {
    return PaginatedResponseOfCrawlLinkDto(
      currentPage: (currentPage != null ? currentPage.value : this.currentPage),
      totalPages: (totalPages != null ? totalPages.value : this.totalPages),
      pageSize: (pageSize != null ? pageSize.value : this.pageSize),
      totalCount: (totalCount != null ? totalCount.value : this.totalCount),
      items: (items != null ? items.value : this.items),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class CrawlLinkDto {
  const CrawlLinkDto({
    this.id,
    this.mediaId,
    this.name,
    this.secondName,
    this.provider,
    this.providerId,
    this.providerItemId,
    this.providerCategory,
    this.category,
    this.fullUrl,
    this.relativeUrl,
    this.thumbnailUrl,
    this.airedEpisodesCount,
    this.totalEpisodesCount,
    this.season,
    this.quality,
    this.version,
    this.productionYear,
    this.downloaded,
    this.hasError,
    this.createdBy,
    this.authorId,
    this.createdAt,
    this.origin,
    this.mediaServerType,
    this.isEnabled,
  });

  factory CrawlLinkDto.fromJson(Map<String, dynamic> json) =>
      _$CrawlLinkDtoFromJson(json);

  static const toJsonFactory = _$CrawlLinkDtoToJson;
  Map<String, dynamic> toJson() => _$CrawlLinkDtoToJson(this);

  @JsonKey(name: 'id', includeIfNull: false)
  final String? id;
  @JsonKey(name: 'mediaId', includeIfNull: false)
  final String? mediaId;
  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'secondName', includeIfNull: false)
  final String? secondName;
  @JsonKey(name: 'provider', includeIfNull: false)
  final dynamic provider;
  @JsonKey(name: 'providerId', includeIfNull: false)
  final String? providerId;
  @JsonKey(name: 'providerItemId', includeIfNull: false)
  final String? providerItemId;
  @JsonKey(name: 'providerCategory', includeIfNull: false)
  final String? providerCategory;
  @JsonKey(
    name: 'category',
    includeIfNull: false,
    toJson: mediaCategoryNullableToJson,
    fromJson: mediaCategoryNullableFromJson,
  )
  final enums.MediaCategory? category;
  @JsonKey(name: 'fullUrl', includeIfNull: false)
  final String? fullUrl;
  @JsonKey(name: 'relativeUrl', includeIfNull: false)
  final String? relativeUrl;
  @JsonKey(name: 'thumbnailUrl', includeIfNull: false)
  final String? thumbnailUrl;
  @JsonKey(name: 'airedEpisodesCount', includeIfNull: false)
  final int? airedEpisodesCount;
  @JsonKey(name: 'totalEpisodesCount', includeIfNull: false)
  final int? totalEpisodesCount;
  @JsonKey(name: 'season', includeIfNull: false)
  final int? season;
  @JsonKey(name: 'quality', includeIfNull: false)
  final String? quality;
  @JsonKey(name: 'version', includeIfNull: false)
  final String? version;
  @JsonKey(name: 'productionYear', includeIfNull: false)
  final int? productionYear;
  @JsonKey(name: 'downloaded', includeIfNull: false)
  final bool? downloaded;
  @JsonKey(name: 'hasError', includeIfNull: false)
  final bool? hasError;
  @JsonKey(name: 'createdBy', includeIfNull: false)
  final String? createdBy;
  @JsonKey(name: 'authorId', includeIfNull: false)
  final String? authorId;
  @JsonKey(name: 'createdAt', includeIfNull: false)
  final DateTime? createdAt;
  @JsonKey(
    name: 'origin',
    includeIfNull: false,
    toJson: creationOriginNullableToJson,
    fromJson: creationOriginNullableFromJson,
  )
  final enums.CreationOrigin? origin;
  @JsonKey(
    name: 'mediaServerType',
    includeIfNull: false,
    toJson: mediaServerTypeNullableToJson,
    fromJson: mediaServerTypeNullableFromJson,
  )
  final enums.MediaServerType? mediaServerType;
  @JsonKey(name: 'isEnabled', includeIfNull: false)
  final bool? isEnabled;
  static const fromJsonFactory = _$CrawlLinkDtoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CrawlLinkDto &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.mediaId, mediaId) ||
                const DeepCollectionEquality().equals(
                  other.mediaId,
                  mediaId,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.secondName, secondName) ||
                const DeepCollectionEquality().equals(
                  other.secondName,
                  secondName,
                )) &&
            (identical(other.provider, provider) ||
                const DeepCollectionEquality().equals(
                  other.provider,
                  provider,
                )) &&
            (identical(other.providerId, providerId) ||
                const DeepCollectionEquality().equals(
                  other.providerId,
                  providerId,
                )) &&
            (identical(other.providerItemId, providerItemId) ||
                const DeepCollectionEquality().equals(
                  other.providerItemId,
                  providerItemId,
                )) &&
            (identical(other.providerCategory, providerCategory) ||
                const DeepCollectionEquality().equals(
                  other.providerCategory,
                  providerCategory,
                )) &&
            (identical(other.category, category) ||
                const DeepCollectionEquality().equals(
                  other.category,
                  category,
                )) &&
            (identical(other.fullUrl, fullUrl) ||
                const DeepCollectionEquality().equals(
                  other.fullUrl,
                  fullUrl,
                )) &&
            (identical(other.relativeUrl, relativeUrl) ||
                const DeepCollectionEquality().equals(
                  other.relativeUrl,
                  relativeUrl,
                )) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                const DeepCollectionEquality().equals(
                  other.thumbnailUrl,
                  thumbnailUrl,
                )) &&
            (identical(other.airedEpisodesCount, airedEpisodesCount) ||
                const DeepCollectionEquality().equals(
                  other.airedEpisodesCount,
                  airedEpisodesCount,
                )) &&
            (identical(other.totalEpisodesCount, totalEpisodesCount) ||
                const DeepCollectionEquality().equals(
                  other.totalEpisodesCount,
                  totalEpisodesCount,
                )) &&
            (identical(other.season, season) ||
                const DeepCollectionEquality().equals(other.season, season)) &&
            (identical(other.quality, quality) ||
                const DeepCollectionEquality().equals(
                  other.quality,
                  quality,
                )) &&
            (identical(other.version, version) ||
                const DeepCollectionEquality().equals(
                  other.version,
                  version,
                )) &&
            (identical(other.productionYear, productionYear) ||
                const DeepCollectionEquality().equals(
                  other.productionYear,
                  productionYear,
                )) &&
            (identical(other.downloaded, downloaded) ||
                const DeepCollectionEquality().equals(
                  other.downloaded,
                  downloaded,
                )) &&
            (identical(other.hasError, hasError) ||
                const DeepCollectionEquality().equals(
                  other.hasError,
                  hasError,
                )) &&
            (identical(other.createdBy, createdBy) ||
                const DeepCollectionEquality().equals(
                  other.createdBy,
                  createdBy,
                )) &&
            (identical(other.authorId, authorId) ||
                const DeepCollectionEquality().equals(
                  other.authorId,
                  authorId,
                )) &&
            (identical(other.createdAt, createdAt) ||
                const DeepCollectionEquality().equals(
                  other.createdAt,
                  createdAt,
                )) &&
            (identical(other.origin, origin) ||
                const DeepCollectionEquality().equals(other.origin, origin)) &&
            (identical(other.mediaServerType, mediaServerType) ||
                const DeepCollectionEquality().equals(
                  other.mediaServerType,
                  mediaServerType,
                )) &&
            (identical(other.isEnabled, isEnabled) ||
                const DeepCollectionEquality().equals(
                  other.isEnabled,
                  isEnabled,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(mediaId) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(secondName) ^
      const DeepCollectionEquality().hash(provider) ^
      const DeepCollectionEquality().hash(providerId) ^
      const DeepCollectionEquality().hash(providerItemId) ^
      const DeepCollectionEquality().hash(providerCategory) ^
      const DeepCollectionEquality().hash(category) ^
      const DeepCollectionEquality().hash(fullUrl) ^
      const DeepCollectionEquality().hash(relativeUrl) ^
      const DeepCollectionEquality().hash(thumbnailUrl) ^
      const DeepCollectionEquality().hash(airedEpisodesCount) ^
      const DeepCollectionEquality().hash(totalEpisodesCount) ^
      const DeepCollectionEquality().hash(season) ^
      const DeepCollectionEquality().hash(quality) ^
      const DeepCollectionEquality().hash(version) ^
      const DeepCollectionEquality().hash(productionYear) ^
      const DeepCollectionEquality().hash(downloaded) ^
      const DeepCollectionEquality().hash(hasError) ^
      const DeepCollectionEquality().hash(createdBy) ^
      const DeepCollectionEquality().hash(authorId) ^
      const DeepCollectionEquality().hash(createdAt) ^
      const DeepCollectionEquality().hash(origin) ^
      const DeepCollectionEquality().hash(mediaServerType) ^
      const DeepCollectionEquality().hash(isEnabled) ^
      runtimeType.hashCode;
}

extension $CrawlLinkDtoExtension on CrawlLinkDto {
  CrawlLinkDto copyWith({
    String? id,
    String? mediaId,
    String? name,
    String? secondName,
    dynamic provider,
    String? providerId,
    String? providerItemId,
    String? providerCategory,
    enums.MediaCategory? category,
    String? fullUrl,
    String? relativeUrl,
    String? thumbnailUrl,
    int? airedEpisodesCount,
    int? totalEpisodesCount,
    int? season,
    String? quality,
    String? version,
    int? productionYear,
    bool? downloaded,
    bool? hasError,
    String? createdBy,
    String? authorId,
    DateTime? createdAt,
    enums.CreationOrigin? origin,
    enums.MediaServerType? mediaServerType,
    bool? isEnabled,
  }) {
    return CrawlLinkDto(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      name: name ?? this.name,
      secondName: secondName ?? this.secondName,
      provider: provider ?? this.provider,
      providerId: providerId ?? this.providerId,
      providerItemId: providerItemId ?? this.providerItemId,
      providerCategory: providerCategory ?? this.providerCategory,
      category: category ?? this.category,
      fullUrl: fullUrl ?? this.fullUrl,
      relativeUrl: relativeUrl ?? this.relativeUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      airedEpisodesCount: airedEpisodesCount ?? this.airedEpisodesCount,
      totalEpisodesCount: totalEpisodesCount ?? this.totalEpisodesCount,
      season: season ?? this.season,
      quality: quality ?? this.quality,
      version: version ?? this.version,
      productionYear: productionYear ?? this.productionYear,
      downloaded: downloaded ?? this.downloaded,
      hasError: hasError ?? this.hasError,
      createdBy: createdBy ?? this.createdBy,
      authorId: authorId ?? this.authorId,
      createdAt: createdAt ?? this.createdAt,
      origin: origin ?? this.origin,
      mediaServerType: mediaServerType ?? this.mediaServerType,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  CrawlLinkDto copyWithWrapped({
    Wrapped<String?>? id,
    Wrapped<String?>? mediaId,
    Wrapped<String?>? name,
    Wrapped<String?>? secondName,
    Wrapped<dynamic>? provider,
    Wrapped<String?>? providerId,
    Wrapped<String?>? providerItemId,
    Wrapped<String?>? providerCategory,
    Wrapped<enums.MediaCategory?>? category,
    Wrapped<String?>? fullUrl,
    Wrapped<String?>? relativeUrl,
    Wrapped<String?>? thumbnailUrl,
    Wrapped<int?>? airedEpisodesCount,
    Wrapped<int?>? totalEpisodesCount,
    Wrapped<int?>? season,
    Wrapped<String?>? quality,
    Wrapped<String?>? version,
    Wrapped<int?>? productionYear,
    Wrapped<bool?>? downloaded,
    Wrapped<bool?>? hasError,
    Wrapped<String?>? createdBy,
    Wrapped<String?>? authorId,
    Wrapped<DateTime?>? createdAt,
    Wrapped<enums.CreationOrigin?>? origin,
    Wrapped<enums.MediaServerType?>? mediaServerType,
    Wrapped<bool?>? isEnabled,
  }) {
    return CrawlLinkDto(
      id: (id != null ? id.value : this.id),
      mediaId: (mediaId != null ? mediaId.value : this.mediaId),
      name: (name != null ? name.value : this.name),
      secondName: (secondName != null ? secondName.value : this.secondName),
      provider: (provider != null ? provider.value : this.provider),
      providerId: (providerId != null ? providerId.value : this.providerId),
      providerItemId: (providerItemId != null
          ? providerItemId.value
          : this.providerItemId),
      providerCategory: (providerCategory != null
          ? providerCategory.value
          : this.providerCategory),
      category: (category != null ? category.value : this.category),
      fullUrl: (fullUrl != null ? fullUrl.value : this.fullUrl),
      relativeUrl: (relativeUrl != null ? relativeUrl.value : this.relativeUrl),
      thumbnailUrl: (thumbnailUrl != null
          ? thumbnailUrl.value
          : this.thumbnailUrl),
      airedEpisodesCount: (airedEpisodesCount != null
          ? airedEpisodesCount.value
          : this.airedEpisodesCount),
      totalEpisodesCount: (totalEpisodesCount != null
          ? totalEpisodesCount.value
          : this.totalEpisodesCount),
      season: (season != null ? season.value : this.season),
      quality: (quality != null ? quality.value : this.quality),
      version: (version != null ? version.value : this.version),
      productionYear: (productionYear != null
          ? productionYear.value
          : this.productionYear),
      downloaded: (downloaded != null ? downloaded.value : this.downloaded),
      hasError: (hasError != null ? hasError.value : this.hasError),
      createdBy: (createdBy != null ? createdBy.value : this.createdBy),
      authorId: (authorId != null ? authorId.value : this.authorId),
      createdAt: (createdAt != null ? createdAt.value : this.createdAt),
      origin: (origin != null ? origin.value : this.origin),
      mediaServerType: (mediaServerType != null
          ? mediaServerType.value
          : this.mediaServerType),
      isEnabled: (isEnabled != null ? isEnabled.value : this.isEnabled),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ProviderDto {
  const ProviderDto({
    this.displayName,
    this.name,
    this.url,
    this.enabled,
    this.searchEnabled,
  });

  factory ProviderDto.fromJson(Map<String, dynamic> json) =>
      _$ProviderDtoFromJson(json);

  static const toJsonFactory = _$ProviderDtoToJson;
  Map<String, dynamic> toJson() => _$ProviderDtoToJson(this);

  @JsonKey(name: 'displayName', includeIfNull: false)
  final String? displayName;
  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'url', includeIfNull: false)
  final String? url;
  @JsonKey(name: 'enabled', includeIfNull: false)
  final bool? enabled;
  @JsonKey(name: 'searchEnabled', includeIfNull: false)
  final bool? searchEnabled;
  static const fromJsonFactory = _$ProviderDtoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ProviderDto &&
            (identical(other.displayName, displayName) ||
                const DeepCollectionEquality().equals(
                  other.displayName,
                  displayName,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.enabled, enabled) ||
                const DeepCollectionEquality().equals(
                  other.enabled,
                  enabled,
                )) &&
            (identical(other.searchEnabled, searchEnabled) ||
                const DeepCollectionEquality().equals(
                  other.searchEnabled,
                  searchEnabled,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(displayName) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(enabled) ^
      const DeepCollectionEquality().hash(searchEnabled) ^
      runtimeType.hashCode;
}

extension $ProviderDtoExtension on ProviderDto {
  ProviderDto copyWith({
    String? displayName,
    String? name,
    String? url,
    bool? enabled,
    bool? searchEnabled,
  }) {
    return ProviderDto(
      displayName: displayName ?? this.displayName,
      name: name ?? this.name,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      searchEnabled: searchEnabled ?? this.searchEnabled,
    );
  }

  ProviderDto copyWithWrapped({
    Wrapped<String?>? displayName,
    Wrapped<String?>? name,
    Wrapped<String?>? url,
    Wrapped<bool?>? enabled,
    Wrapped<bool?>? searchEnabled,
  }) {
    return ProviderDto(
      displayName: (displayName != null ? displayName.value : this.displayName),
      name: (name != null ? name.value : this.name),
      url: (url != null ? url.value : this.url),
      enabled: (enabled != null ? enabled.value : this.enabled),
      searchEnabled: (searchEnabled != null
          ? searchEnabled.value
          : this.searchEnabled),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ProblemDetails {
  const ProblemDetails({
    this.type,
    this.title,
    this.status,
    this.detail,
    this.instance,
    this.extensions,
  });

  factory ProblemDetails.fromJson(Map<String, dynamic> json) =>
      _$ProblemDetailsFromJson(json);

  static const toJsonFactory = _$ProblemDetailsToJson;
  Map<String, dynamic> toJson() => _$ProblemDetailsToJson(this);

  @JsonKey(name: 'type', includeIfNull: false)
  final String? type;
  @JsonKey(name: 'title', includeIfNull: false)
  final String? title;
  @JsonKey(name: 'status', includeIfNull: false)
  final int? status;
  @JsonKey(name: 'detail', includeIfNull: false)
  final String? detail;
  @JsonKey(name: 'instance', includeIfNull: false)
  final String? instance;
  @JsonKey(name: 'extensions', includeIfNull: false)
  final Map<String, dynamic>? extensions;
  static const fromJsonFactory = _$ProblemDetailsFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ProblemDetails &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)) &&
            (identical(other.title, title) ||
                const DeepCollectionEquality().equals(other.title, title)) &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.detail, detail) ||
                const DeepCollectionEquality().equals(other.detail, detail)) &&
            (identical(other.instance, instance) ||
                const DeepCollectionEquality().equals(
                  other.instance,
                  instance,
                )) &&
            (identical(other.extensions, extensions) ||
                const DeepCollectionEquality().equals(
                  other.extensions,
                  extensions,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(type) ^
      const DeepCollectionEquality().hash(title) ^
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(detail) ^
      const DeepCollectionEquality().hash(instance) ^
      const DeepCollectionEquality().hash(extensions) ^
      runtimeType.hashCode;
}

extension $ProblemDetailsExtension on ProblemDetails {
  ProblemDetails copyWith({
    String? type,
    String? title,
    int? status,
    String? detail,
    String? instance,
    Map<String, dynamic>? extensions,
  }) {
    return ProblemDetails(
      type: type ?? this.type,
      title: title ?? this.title,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      instance: instance ?? this.instance,
      extensions: extensions ?? this.extensions,
    );
  }

  ProblemDetails copyWithWrapped({
    Wrapped<String?>? type,
    Wrapped<String?>? title,
    Wrapped<int?>? status,
    Wrapped<String?>? detail,
    Wrapped<String?>? instance,
    Wrapped<Map<String, dynamic>?>? extensions,
  }) {
    return ProblemDetails(
      type: (type != null ? type.value : this.type),
      title: (title != null ? title.value : this.title),
      status: (status != null ? status.value : this.status),
      detail: (detail != null ? detail.value : this.detail),
      instance: (instance != null ? instance.value : this.instance),
      extensions: (extensions != null ? extensions.value : this.extensions),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ExtractMediaRequest {
  const ExtractMediaRequest({
    this.url,
    this.userName,
    this.userId,
    this.mediaCategory,
  });

  factory ExtractMediaRequest.fromJson(Map<String, dynamic> json) =>
      _$ExtractMediaRequestFromJson(json);

  static const toJsonFactory = _$ExtractMediaRequestToJson;
  Map<String, dynamic> toJson() => _$ExtractMediaRequestToJson(this);

  @JsonKey(name: 'url', includeIfNull: false)
  final String? url;
  @JsonKey(name: 'userName', includeIfNull: false)
  final String? userName;
  @JsonKey(name: 'userId', includeIfNull: false)
  final String? userId;
  @JsonKey(
    name: 'mediaCategory',
    includeIfNull: false,
    toJson: mediaCategoryNullableToJson,
    fromJson: mediaCategoryNullableFromJson,
  )
  final enums.MediaCategory? mediaCategory;
  static const fromJsonFactory = _$ExtractMediaRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExtractMediaRequest &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.userName, userName) ||
                const DeepCollectionEquality().equals(
                  other.userName,
                  userName,
                )) &&
            (identical(other.userId, userId) ||
                const DeepCollectionEquality().equals(other.userId, userId)) &&
            (identical(other.mediaCategory, mediaCategory) ||
                const DeepCollectionEquality().equals(
                  other.mediaCategory,
                  mediaCategory,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(userName) ^
      const DeepCollectionEquality().hash(userId) ^
      const DeepCollectionEquality().hash(mediaCategory) ^
      runtimeType.hashCode;
}

extension $ExtractMediaRequestExtension on ExtractMediaRequest {
  ExtractMediaRequest copyWith({
    String? url,
    String? userName,
    String? userId,
    enums.MediaCategory? mediaCategory,
  }) {
    return ExtractMediaRequest(
      url: url ?? this.url,
      userName: userName ?? this.userName,
      userId: userId ?? this.userId,
      mediaCategory: mediaCategory ?? this.mediaCategory,
    );
  }

  ExtractMediaRequest copyWithWrapped({
    Wrapped<String?>? url,
    Wrapped<String?>? userName,
    Wrapped<String?>? userId,
    Wrapped<enums.MediaCategory?>? mediaCategory,
  }) {
    return ExtractMediaRequest(
      url: (url != null ? url.value : this.url),
      userName: (userName != null ? userName.value : this.userName),
      userId: (userId != null ? userId.value : this.userId),
      mediaCategory: (mediaCategory != null
          ? mediaCategory.value
          : this.mediaCategory),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ExtractMediaConfirmationRequest {
  const ExtractMediaConfirmationRequest({this.crawlLinkId, this.mediaTitle});

  factory ExtractMediaConfirmationRequest.fromJson(Map<String, dynamic> json) =>
      _$ExtractMediaConfirmationRequestFromJson(json);

  static const toJsonFactory = _$ExtractMediaConfirmationRequestToJson;
  Map<String, dynamic> toJson() =>
      _$ExtractMediaConfirmationRequestToJson(this);

  @JsonKey(name: 'crawlLinkId', includeIfNull: false)
  final String? crawlLinkId;
  @JsonKey(name: 'mediaTitle', includeIfNull: false)
  final String? mediaTitle;
  static const fromJsonFactory = _$ExtractMediaConfirmationRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExtractMediaConfirmationRequest &&
            (identical(other.crawlLinkId, crawlLinkId) ||
                const DeepCollectionEquality().equals(
                  other.crawlLinkId,
                  crawlLinkId,
                )) &&
            (identical(other.mediaTitle, mediaTitle) ||
                const DeepCollectionEquality().equals(
                  other.mediaTitle,
                  mediaTitle,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(crawlLinkId) ^
      const DeepCollectionEquality().hash(mediaTitle) ^
      runtimeType.hashCode;
}

extension $ExtractMediaConfirmationRequestExtension
    on ExtractMediaConfirmationRequest {
  ExtractMediaConfirmationRequest copyWith({
    String? crawlLinkId,
    String? mediaTitle,
  }) {
    return ExtractMediaConfirmationRequest(
      crawlLinkId: crawlLinkId ?? this.crawlLinkId,
      mediaTitle: mediaTitle ?? this.mediaTitle,
    );
  }

  ExtractMediaConfirmationRequest copyWithWrapped({
    Wrapped<String?>? crawlLinkId,
    Wrapped<String?>? mediaTitle,
  }) {
    return ExtractMediaConfirmationRequest(
      crawlLinkId: (crawlLinkId != null ? crawlLinkId.value : this.crawlLinkId),
      mediaTitle: (mediaTitle != null ? mediaTitle.value : this.mediaTitle),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class RenameLinkResult {
  const RenameLinkResult({
    this.isSuccess,
    this.error,
    this.oldName,
    this.newName,
  });

  factory RenameLinkResult.fromJson(Map<String, dynamic> json) =>
      _$RenameLinkResultFromJson(json);

  static const toJsonFactory = _$RenameLinkResultToJson;
  Map<String, dynamic> toJson() => _$RenameLinkResultToJson(this);

  @JsonKey(name: 'isSuccess', includeIfNull: false)
  final bool? isSuccess;
  @JsonKey(name: 'error', includeIfNull: false)
  final String? error;
  @JsonKey(name: 'oldName', includeIfNull: false)
  final String? oldName;
  @JsonKey(name: 'newName', includeIfNull: false)
  final String? newName;
  static const fromJsonFactory = _$RenameLinkResultFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is RenameLinkResult &&
            (identical(other.isSuccess, isSuccess) ||
                const DeepCollectionEquality().equals(
                  other.isSuccess,
                  isSuccess,
                )) &&
            (identical(other.error, error) ||
                const DeepCollectionEquality().equals(other.error, error)) &&
            (identical(other.oldName, oldName) ||
                const DeepCollectionEquality().equals(
                  other.oldName,
                  oldName,
                )) &&
            (identical(other.newName, newName) ||
                const DeepCollectionEquality().equals(other.newName, newName)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(isSuccess) ^
      const DeepCollectionEquality().hash(error) ^
      const DeepCollectionEquality().hash(oldName) ^
      const DeepCollectionEquality().hash(newName) ^
      runtimeType.hashCode;
}

extension $RenameLinkResultExtension on RenameLinkResult {
  RenameLinkResult copyWith({
    bool? isSuccess,
    String? error,
    String? oldName,
    String? newName,
  }) {
    return RenameLinkResult(
      isSuccess: isSuccess ?? this.isSuccess,
      error: error ?? this.error,
      oldName: oldName ?? this.oldName,
      newName: newName ?? this.newName,
    );
  }

  RenameLinkResult copyWithWrapped({
    Wrapped<bool?>? isSuccess,
    Wrapped<String?>? error,
    Wrapped<String?>? oldName,
    Wrapped<String?>? newName,
  }) {
    return RenameLinkResult(
      isSuccess: (isSuccess != null ? isSuccess.value : this.isSuccess),
      error: (error != null ? error.value : this.error),
      oldName: (oldName != null ? oldName.value : this.oldName),
      newName: (newName != null ? newName.value : this.newName),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class RenameCrawlLinkRequest {
  const RenameCrawlLinkRequest({this.newName});

  factory RenameCrawlLinkRequest.fromJson(Map<String, dynamic> json) =>
      _$RenameCrawlLinkRequestFromJson(json);

  static const toJsonFactory = _$RenameCrawlLinkRequestToJson;
  Map<String, dynamic> toJson() => _$RenameCrawlLinkRequestToJson(this);

  @JsonKey(name: 'newName', includeIfNull: false)
  final String? newName;
  static const fromJsonFactory = _$RenameCrawlLinkRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is RenameCrawlLinkRequest &&
            (identical(other.newName, newName) ||
                const DeepCollectionEquality().equals(other.newName, newName)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(newName) ^ runtimeType.hashCode;
}

extension $RenameCrawlLinkRequestExtension on RenameCrawlLinkRequest {
  RenameCrawlLinkRequest copyWith({String? newName}) {
    return RenameCrawlLinkRequest(newName: newName ?? this.newName);
  }

  RenameCrawlLinkRequest copyWithWrapped({Wrapped<String?>? newName}) {
    return RenameCrawlLinkRequest(
      newName: (newName != null ? newName.value : this.newName),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DownloadDto {
  const DownloadDto({
    this.name,
    this.fileName,
    this.url,
    this.destinationFolder,
    this.isRunning,
    this.isCancelled,
    this.isCompleted,
    this.isDeadLink,
    this.episodeIndex,
    this.progress,
    this.speed,
    this.speedUnit,
    this.averageSpeed,
    this.averageSpeedUnit,
    this.sizeReceived,
    this.sizeUnit,
    this.totalSize,
    this.totalSizeUnit,
    this.estimatedTime,
    this.estimatedTimeUnit,
  });

  factory DownloadDto.fromJson(Map<String, dynamic> json) =>
      _$DownloadDtoFromJson(json);

  static const toJsonFactory = _$DownloadDtoToJson;
  Map<String, dynamic> toJson() => _$DownloadDtoToJson(this);

  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'fileName', includeIfNull: false)
  final String? fileName;
  @JsonKey(name: 'url', includeIfNull: false)
  final String? url;
  @JsonKey(name: 'destinationFolder', includeIfNull: false)
  final String? destinationFolder;
  @JsonKey(name: 'isRunning', includeIfNull: false)
  final bool? isRunning;
  @JsonKey(name: 'isCancelled', includeIfNull: false)
  final bool? isCancelled;
  @JsonKey(name: 'isCompleted', includeIfNull: false)
  final bool? isCompleted;
  @JsonKey(name: 'isDeadLink', includeIfNull: false)
  final bool? isDeadLink;
  @JsonKey(name: 'episodeIndex', includeIfNull: false)
  final int? episodeIndex;
  @JsonKey(name: 'progress', includeIfNull: false)
  final double? progress;
  @JsonKey(name: 'speed', includeIfNull: false)
  final double? speed;
  @JsonKey(name: 'speedUnit', includeIfNull: false)
  final String? speedUnit;
  @JsonKey(name: 'averageSpeed', includeIfNull: false)
  final double? averageSpeed;
  @JsonKey(name: 'averageSpeedUnit', includeIfNull: false)
  final String? averageSpeedUnit;
  @JsonKey(name: 'sizeReceived', includeIfNull: false)
  final double? sizeReceived;
  @JsonKey(name: 'sizeUnit', includeIfNull: false)
  final String? sizeUnit;
  @JsonKey(name: 'totalSize', includeIfNull: false)
  final double? totalSize;
  @JsonKey(name: 'totalSizeUnit', includeIfNull: false)
  final String? totalSizeUnit;
  @JsonKey(name: 'estimatedTime', includeIfNull: false)
  final int? estimatedTime;
  @JsonKey(name: 'estimatedTimeUnit', includeIfNull: false)
  final String? estimatedTimeUnit;
  static const fromJsonFactory = _$DownloadDtoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DownloadDto &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.fileName, fileName) ||
                const DeepCollectionEquality().equals(
                  other.fileName,
                  fileName,
                )) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.destinationFolder, destinationFolder) ||
                const DeepCollectionEquality().equals(
                  other.destinationFolder,
                  destinationFolder,
                )) &&
            (identical(other.isRunning, isRunning) ||
                const DeepCollectionEquality().equals(
                  other.isRunning,
                  isRunning,
                )) &&
            (identical(other.isCancelled, isCancelled) ||
                const DeepCollectionEquality().equals(
                  other.isCancelled,
                  isCancelled,
                )) &&
            (identical(other.isCompleted, isCompleted) ||
                const DeepCollectionEquality().equals(
                  other.isCompleted,
                  isCompleted,
                )) &&
            (identical(other.isDeadLink, isDeadLink) ||
                const DeepCollectionEquality().equals(
                  other.isDeadLink,
                  isDeadLink,
                )) &&
            (identical(other.episodeIndex, episodeIndex) ||
                const DeepCollectionEquality().equals(
                  other.episodeIndex,
                  episodeIndex,
                )) &&
            (identical(other.progress, progress) ||
                const DeepCollectionEquality().equals(
                  other.progress,
                  progress,
                )) &&
            (identical(other.speed, speed) ||
                const DeepCollectionEquality().equals(other.speed, speed)) &&
            (identical(other.speedUnit, speedUnit) ||
                const DeepCollectionEquality().equals(
                  other.speedUnit,
                  speedUnit,
                )) &&
            (identical(other.averageSpeed, averageSpeed) ||
                const DeepCollectionEquality().equals(
                  other.averageSpeed,
                  averageSpeed,
                )) &&
            (identical(other.averageSpeedUnit, averageSpeedUnit) ||
                const DeepCollectionEquality().equals(
                  other.averageSpeedUnit,
                  averageSpeedUnit,
                )) &&
            (identical(other.sizeReceived, sizeReceived) ||
                const DeepCollectionEquality().equals(
                  other.sizeReceived,
                  sizeReceived,
                )) &&
            (identical(other.sizeUnit, sizeUnit) ||
                const DeepCollectionEquality().equals(
                  other.sizeUnit,
                  sizeUnit,
                )) &&
            (identical(other.totalSize, totalSize) ||
                const DeepCollectionEquality().equals(
                  other.totalSize,
                  totalSize,
                )) &&
            (identical(other.totalSizeUnit, totalSizeUnit) ||
                const DeepCollectionEquality().equals(
                  other.totalSizeUnit,
                  totalSizeUnit,
                )) &&
            (identical(other.estimatedTime, estimatedTime) ||
                const DeepCollectionEquality().equals(
                  other.estimatedTime,
                  estimatedTime,
                )) &&
            (identical(other.estimatedTimeUnit, estimatedTimeUnit) ||
                const DeepCollectionEquality().equals(
                  other.estimatedTimeUnit,
                  estimatedTimeUnit,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(fileName) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(destinationFolder) ^
      const DeepCollectionEquality().hash(isRunning) ^
      const DeepCollectionEquality().hash(isCancelled) ^
      const DeepCollectionEquality().hash(isCompleted) ^
      const DeepCollectionEquality().hash(isDeadLink) ^
      const DeepCollectionEquality().hash(episodeIndex) ^
      const DeepCollectionEquality().hash(progress) ^
      const DeepCollectionEquality().hash(speed) ^
      const DeepCollectionEquality().hash(speedUnit) ^
      const DeepCollectionEquality().hash(averageSpeed) ^
      const DeepCollectionEquality().hash(averageSpeedUnit) ^
      const DeepCollectionEquality().hash(sizeReceived) ^
      const DeepCollectionEquality().hash(sizeUnit) ^
      const DeepCollectionEquality().hash(totalSize) ^
      const DeepCollectionEquality().hash(totalSizeUnit) ^
      const DeepCollectionEquality().hash(estimatedTime) ^
      const DeepCollectionEquality().hash(estimatedTimeUnit) ^
      runtimeType.hashCode;
}

extension $DownloadDtoExtension on DownloadDto {
  DownloadDto copyWith({
    String? name,
    String? fileName,
    String? url,
    String? destinationFolder,
    bool? isRunning,
    bool? isCancelled,
    bool? isCompleted,
    bool? isDeadLink,
    int? episodeIndex,
    double? progress,
    double? speed,
    String? speedUnit,
    double? averageSpeed,
    String? averageSpeedUnit,
    double? sizeReceived,
    String? sizeUnit,
    double? totalSize,
    String? totalSizeUnit,
    int? estimatedTime,
    String? estimatedTimeUnit,
  }) {
    return DownloadDto(
      name: name ?? this.name,
      fileName: fileName ?? this.fileName,
      url: url ?? this.url,
      destinationFolder: destinationFolder ?? this.destinationFolder,
      isRunning: isRunning ?? this.isRunning,
      isCancelled: isCancelled ?? this.isCancelled,
      isCompleted: isCompleted ?? this.isCompleted,
      isDeadLink: isDeadLink ?? this.isDeadLink,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      speedUnit: speedUnit ?? this.speedUnit,
      averageSpeed: averageSpeed ?? this.averageSpeed,
      averageSpeedUnit: averageSpeedUnit ?? this.averageSpeedUnit,
      sizeReceived: sizeReceived ?? this.sizeReceived,
      sizeUnit: sizeUnit ?? this.sizeUnit,
      totalSize: totalSize ?? this.totalSize,
      totalSizeUnit: totalSizeUnit ?? this.totalSizeUnit,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      estimatedTimeUnit: estimatedTimeUnit ?? this.estimatedTimeUnit,
    );
  }

  DownloadDto copyWithWrapped({
    Wrapped<String?>? name,
    Wrapped<String?>? fileName,
    Wrapped<String?>? url,
    Wrapped<String?>? destinationFolder,
    Wrapped<bool?>? isRunning,
    Wrapped<bool?>? isCancelled,
    Wrapped<bool?>? isCompleted,
    Wrapped<bool?>? isDeadLink,
    Wrapped<int?>? episodeIndex,
    Wrapped<double?>? progress,
    Wrapped<double?>? speed,
    Wrapped<String?>? speedUnit,
    Wrapped<double?>? averageSpeed,
    Wrapped<String?>? averageSpeedUnit,
    Wrapped<double?>? sizeReceived,
    Wrapped<String?>? sizeUnit,
    Wrapped<double?>? totalSize,
    Wrapped<String?>? totalSizeUnit,
    Wrapped<int?>? estimatedTime,
    Wrapped<String?>? estimatedTimeUnit,
  }) {
    return DownloadDto(
      name: (name != null ? name.value : this.name),
      fileName: (fileName != null ? fileName.value : this.fileName),
      url: (url != null ? url.value : this.url),
      destinationFolder: (destinationFolder != null
          ? destinationFolder.value
          : this.destinationFolder),
      isRunning: (isRunning != null ? isRunning.value : this.isRunning),
      isCancelled: (isCancelled != null ? isCancelled.value : this.isCancelled),
      isCompleted: (isCompleted != null ? isCompleted.value : this.isCompleted),
      isDeadLink: (isDeadLink != null ? isDeadLink.value : this.isDeadLink),
      episodeIndex: (episodeIndex != null
          ? episodeIndex.value
          : this.episodeIndex),
      progress: (progress != null ? progress.value : this.progress),
      speed: (speed != null ? speed.value : this.speed),
      speedUnit: (speedUnit != null ? speedUnit.value : this.speedUnit),
      averageSpeed: (averageSpeed != null
          ? averageSpeed.value
          : this.averageSpeed),
      averageSpeedUnit: (averageSpeedUnit != null
          ? averageSpeedUnit.value
          : this.averageSpeedUnit),
      sizeReceived: (sizeReceived != null
          ? sizeReceived.value
          : this.sizeReceived),
      sizeUnit: (sizeUnit != null ? sizeUnit.value : this.sizeUnit),
      totalSize: (totalSize != null ? totalSize.value : this.totalSize),
      totalSizeUnit: (totalSizeUnit != null
          ? totalSizeUnit.value
          : this.totalSizeUnit),
      estimatedTime: (estimatedTime != null
          ? estimatedTime.value
          : this.estimatedTime),
      estimatedTimeUnit: (estimatedTimeUnit != null
          ? estimatedTimeUnit.value
          : this.estimatedTimeUnit),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ScheduledJob {
  const ScheduledJob({this.id, this.type, this.status, this.startedAt});

  factory ScheduledJob.fromJson(Map<String, dynamic> json) =>
      _$ScheduledJobFromJson(json);

  static const toJsonFactory = _$ScheduledJobToJson;
  Map<String, dynamic> toJson() => _$ScheduledJobToJson(this);

  @JsonKey(name: 'id', includeIfNull: false)
  final String? id;
  @JsonKey(name: 'type', includeIfNull: false)
  final String? type;
  @JsonKey(name: 'status', includeIfNull: false)
  final String? status;
  @JsonKey(name: 'startedAt', includeIfNull: false)
  final DateTime? startedAt;
  static const fromJsonFactory = _$ScheduledJobFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScheduledJob &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)) &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.startedAt, startedAt) ||
                const DeepCollectionEquality().equals(
                  other.startedAt,
                  startedAt,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(type) ^
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(startedAt) ^
      runtimeType.hashCode;
}

extension $ScheduledJobExtension on ScheduledJob {
  ScheduledJob copyWith({
    String? id,
    String? type,
    String? status,
    DateTime? startedAt,
  }) {
    return ScheduledJob(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  ScheduledJob copyWithWrapped({
    Wrapped<String?>? id,
    Wrapped<String?>? type,
    Wrapped<String?>? status,
    Wrapped<DateTime?>? startedAt,
  }) {
    return ScheduledJob(
      id: (id != null ? id.value : this.id),
      type: (type != null ? type.value : this.type),
      status: (status != null ? status.value : this.status),
      startedAt: (startedAt != null ? startedAt.value : this.startedAt),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class TriggerJobRequest {
  const TriggerJobRequest({this.jobType});

  factory TriggerJobRequest.fromJson(Map<String, dynamic> json) =>
      _$TriggerJobRequestFromJson(json);

  static const toJsonFactory = _$TriggerJobRequestToJson;
  Map<String, dynamic> toJson() => _$TriggerJobRequestToJson(this);

  @JsonKey(name: 'jobType', includeIfNull: false)
  final String? jobType;
  static const fromJsonFactory = _$TriggerJobRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TriggerJobRequest &&
            (identical(other.jobType, jobType) ||
                const DeepCollectionEquality().equals(other.jobType, jobType)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(jobType) ^ runtimeType.hashCode;
}

extension $TriggerJobRequestExtension on TriggerJobRequest {
  TriggerJobRequest copyWith({String? jobType}) {
    return TriggerJobRequest(jobType: jobType ?? this.jobType);
  }

  TriggerJobRequest copyWithWrapped({Wrapped<String?>? jobType}) {
    return TriggerJobRequest(
      jobType: (jobType != null ? jobType.value : this.jobType),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class IProvider {
  const IProvider({
    this.id,
    this.displayName,
    this.name,
    this.url,
    this.enabled,
    this.searchEnabled,
    this.crawlLinksRef,
  });

  factory IProvider.fromJson(Map<String, dynamic> json) =>
      _$IProviderFromJson(json);

  static const toJsonFactory = _$IProviderToJson;
  Map<String, dynamic> toJson() => _$IProviderToJson(this);

  @JsonKey(name: 'id', includeIfNull: false)
  final String? id;
  @JsonKey(name: 'displayName', includeIfNull: false)
  final String? displayName;
  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'url', includeIfNull: false)
  final String? url;
  @JsonKey(name: 'enabled', includeIfNull: false)
  final bool? enabled;
  @JsonKey(name: 'searchEnabled', includeIfNull: false)
  final bool? searchEnabled;
  @JsonKey(
    name: 'crawlLinksRef',
    includeIfNull: false,
    defaultValue: <ICrawlLink>[],
  )
  final List<ICrawlLink>? crawlLinksRef;
  static const fromJsonFactory = _$IProviderFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is IProvider &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.displayName, displayName) ||
                const DeepCollectionEquality().equals(
                  other.displayName,
                  displayName,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.enabled, enabled) ||
                const DeepCollectionEquality().equals(
                  other.enabled,
                  enabled,
                )) &&
            (identical(other.searchEnabled, searchEnabled) ||
                const DeepCollectionEquality().equals(
                  other.searchEnabled,
                  searchEnabled,
                )) &&
            (identical(other.crawlLinksRef, crawlLinksRef) ||
                const DeepCollectionEquality().equals(
                  other.crawlLinksRef,
                  crawlLinksRef,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(displayName) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(enabled) ^
      const DeepCollectionEquality().hash(searchEnabled) ^
      const DeepCollectionEquality().hash(crawlLinksRef) ^
      runtimeType.hashCode;
}

extension $IProviderExtension on IProvider {
  IProvider copyWith({
    String? id,
    String? displayName,
    String? name,
    String? url,
    bool? enabled,
    bool? searchEnabled,
    List<ICrawlLink>? crawlLinksRef,
  }) {
    return IProvider(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      name: name ?? this.name,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      searchEnabled: searchEnabled ?? this.searchEnabled,
      crawlLinksRef: crawlLinksRef ?? this.crawlLinksRef,
    );
  }

  IProvider copyWithWrapped({
    Wrapped<String?>? id,
    Wrapped<String?>? displayName,
    Wrapped<String?>? name,
    Wrapped<String?>? url,
    Wrapped<bool?>? enabled,
    Wrapped<bool?>? searchEnabled,
    Wrapped<List<ICrawlLink>?>? crawlLinksRef,
  }) {
    return IProvider(
      id: (id != null ? id.value : this.id),
      displayName: (displayName != null ? displayName.value : this.displayName),
      name: (name != null ? name.value : this.name),
      url: (url != null ? url.value : this.url),
      enabled: (enabled != null ? enabled.value : this.enabled),
      searchEnabled: (searchEnabled != null
          ? searchEnabled.value
          : this.searchEnabled),
      crawlLinksRef: (crawlLinksRef != null
          ? crawlLinksRef.value
          : this.crawlLinksRef),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ICrawlLink {
  const ICrawlLink({
    this.id,
    this.mediaId,
    this.name,
    this.secondName,
    this.formattedName,
    this.providerId,
    this.providerRef,
    this.providerItemId,
    this.providerCategory,
    this.category,
    this.url,
    this.thumbnailUrl,
    this.airedEpisodesCount,
    this.totalEpisodesCount,
    this.season,
    this.quality,
    this.version,
    this.productionYear,
    this.downloaded,
    this.hasError,
    this.createdBy,
    this.authorId,
    this.isEnabled,
    this.createdAt,
    this.origin,
    this.mediaServerType,
    this.runningCrawl,
  });

  factory ICrawlLink.fromJson(Map<String, dynamic> json) =>
      _$ICrawlLinkFromJson(json);

  static const toJsonFactory = _$ICrawlLinkToJson;
  Map<String, dynamic> toJson() => _$ICrawlLinkToJson(this);

  @JsonKey(name: 'id', includeIfNull: false)
  final String? id;
  @JsonKey(name: 'mediaId', includeIfNull: false)
  final String? mediaId;
  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'secondName', includeIfNull: false)
  final String? secondName;
  @JsonKey(name: 'formattedName', includeIfNull: false)
  final String? formattedName;
  @JsonKey(name: 'providerId', includeIfNull: false)
  final String? providerId;
  @JsonKey(name: 'providerRef', includeIfNull: false)
  final IProvider? providerRef;
  @JsonKey(name: 'providerItemId', includeIfNull: false)
  final String? providerItemId;
  @JsonKey(name: 'providerCategory', includeIfNull: false)
  final String? providerCategory;
  @JsonKey(
    name: 'category',
    includeIfNull: false,
    toJson: mediaCategoryNullableToJson,
    fromJson: mediaCategoryNullableFromJson,
  )
  final enums.MediaCategory? category;
  @JsonKey(name: 'url', includeIfNull: false)
  final String? url;
  @JsonKey(name: 'thumbnailUrl', includeIfNull: false)
  final String? thumbnailUrl;
  @JsonKey(name: 'airedEpisodesCount', includeIfNull: false)
  final int? airedEpisodesCount;
  @JsonKey(name: 'totalEpisodesCount', includeIfNull: false)
  final int? totalEpisodesCount;
  @JsonKey(name: 'season', includeIfNull: false)
  final int? season;
  @JsonKey(name: 'quality', includeIfNull: false)
  final String? quality;
  @JsonKey(name: 'version', includeIfNull: false)
  final String? version;
  @JsonKey(name: 'productionYear', includeIfNull: false)
  final int? productionYear;
  @JsonKey(name: 'downloaded', includeIfNull: false)
  final bool? downloaded;
  @JsonKey(name: 'hasError', includeIfNull: false)
  final bool? hasError;
  @JsonKey(name: 'createdBy', includeIfNull: false)
  final String? createdBy;
  @JsonKey(name: 'authorId', includeIfNull: false)
  final String? authorId;
  @JsonKey(name: 'isEnabled', includeIfNull: false)
  final bool? isEnabled;
  @JsonKey(name: 'createdAt', includeIfNull: false)
  final DateTime? createdAt;
  @JsonKey(
    name: 'origin',
    includeIfNull: false,
    toJson: creationOriginNullableToJson,
    fromJson: creationOriginNullableFromJson,
  )
  final enums.CreationOrigin? origin;
  @JsonKey(
    name: 'mediaServerType',
    includeIfNull: false,
    toJson: mediaServerTypeNullableToJson,
    fromJson: mediaServerTypeNullableFromJson,
  )
  final enums.MediaServerType? mediaServerType;
  @JsonKey(name: 'runningCrawl', includeIfNull: false)
  final dynamic runningCrawl;
  static const fromJsonFactory = _$ICrawlLinkFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ICrawlLink &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.mediaId, mediaId) ||
                const DeepCollectionEquality().equals(
                  other.mediaId,
                  mediaId,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.secondName, secondName) ||
                const DeepCollectionEquality().equals(
                  other.secondName,
                  secondName,
                )) &&
            (identical(other.formattedName, formattedName) ||
                const DeepCollectionEquality().equals(
                  other.formattedName,
                  formattedName,
                )) &&
            (identical(other.providerId, providerId) ||
                const DeepCollectionEquality().equals(
                  other.providerId,
                  providerId,
                )) &&
            (identical(other.providerRef, providerRef) ||
                const DeepCollectionEquality().equals(
                  other.providerRef,
                  providerRef,
                )) &&
            (identical(other.providerItemId, providerItemId) ||
                const DeepCollectionEquality().equals(
                  other.providerItemId,
                  providerItemId,
                )) &&
            (identical(other.providerCategory, providerCategory) ||
                const DeepCollectionEquality().equals(
                  other.providerCategory,
                  providerCategory,
                )) &&
            (identical(other.category, category) ||
                const DeepCollectionEquality().equals(
                  other.category,
                  category,
                )) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                const DeepCollectionEquality().equals(
                  other.thumbnailUrl,
                  thumbnailUrl,
                )) &&
            (identical(other.airedEpisodesCount, airedEpisodesCount) ||
                const DeepCollectionEquality().equals(
                  other.airedEpisodesCount,
                  airedEpisodesCount,
                )) &&
            (identical(other.totalEpisodesCount, totalEpisodesCount) ||
                const DeepCollectionEquality().equals(
                  other.totalEpisodesCount,
                  totalEpisodesCount,
                )) &&
            (identical(other.season, season) ||
                const DeepCollectionEquality().equals(other.season, season)) &&
            (identical(other.quality, quality) ||
                const DeepCollectionEquality().equals(
                  other.quality,
                  quality,
                )) &&
            (identical(other.version, version) ||
                const DeepCollectionEquality().equals(
                  other.version,
                  version,
                )) &&
            (identical(other.productionYear, productionYear) ||
                const DeepCollectionEquality().equals(
                  other.productionYear,
                  productionYear,
                )) &&
            (identical(other.downloaded, downloaded) ||
                const DeepCollectionEquality().equals(
                  other.downloaded,
                  downloaded,
                )) &&
            (identical(other.hasError, hasError) ||
                const DeepCollectionEquality().equals(
                  other.hasError,
                  hasError,
                )) &&
            (identical(other.createdBy, createdBy) ||
                const DeepCollectionEquality().equals(
                  other.createdBy,
                  createdBy,
                )) &&
            (identical(other.authorId, authorId) ||
                const DeepCollectionEquality().equals(
                  other.authorId,
                  authorId,
                )) &&
            (identical(other.isEnabled, isEnabled) ||
                const DeepCollectionEquality().equals(
                  other.isEnabled,
                  isEnabled,
                )) &&
            (identical(other.createdAt, createdAt) ||
                const DeepCollectionEquality().equals(
                  other.createdAt,
                  createdAt,
                )) &&
            (identical(other.origin, origin) ||
                const DeepCollectionEquality().equals(other.origin, origin)) &&
            (identical(other.mediaServerType, mediaServerType) ||
                const DeepCollectionEquality().equals(
                  other.mediaServerType,
                  mediaServerType,
                )) &&
            (identical(other.runningCrawl, runningCrawl) ||
                const DeepCollectionEquality().equals(
                  other.runningCrawl,
                  runningCrawl,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(mediaId) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(secondName) ^
      const DeepCollectionEquality().hash(formattedName) ^
      const DeepCollectionEquality().hash(providerId) ^
      const DeepCollectionEquality().hash(providerRef) ^
      const DeepCollectionEquality().hash(providerItemId) ^
      const DeepCollectionEquality().hash(providerCategory) ^
      const DeepCollectionEquality().hash(category) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(thumbnailUrl) ^
      const DeepCollectionEquality().hash(airedEpisodesCount) ^
      const DeepCollectionEquality().hash(totalEpisodesCount) ^
      const DeepCollectionEquality().hash(season) ^
      const DeepCollectionEquality().hash(quality) ^
      const DeepCollectionEquality().hash(version) ^
      const DeepCollectionEquality().hash(productionYear) ^
      const DeepCollectionEquality().hash(downloaded) ^
      const DeepCollectionEquality().hash(hasError) ^
      const DeepCollectionEquality().hash(createdBy) ^
      const DeepCollectionEquality().hash(authorId) ^
      const DeepCollectionEquality().hash(isEnabled) ^
      const DeepCollectionEquality().hash(createdAt) ^
      const DeepCollectionEquality().hash(origin) ^
      const DeepCollectionEquality().hash(mediaServerType) ^
      const DeepCollectionEquality().hash(runningCrawl) ^
      runtimeType.hashCode;
}

extension $ICrawlLinkExtension on ICrawlLink {
  ICrawlLink copyWith({
    String? id,
    String? mediaId,
    String? name,
    String? secondName,
    String? formattedName,
    String? providerId,
    IProvider? providerRef,
    String? providerItemId,
    String? providerCategory,
    enums.MediaCategory? category,
    String? url,
    String? thumbnailUrl,
    int? airedEpisodesCount,
    int? totalEpisodesCount,
    int? season,
    String? quality,
    String? version,
    int? productionYear,
    bool? downloaded,
    bool? hasError,
    String? createdBy,
    String? authorId,
    bool? isEnabled,
    DateTime? createdAt,
    enums.CreationOrigin? origin,
    enums.MediaServerType? mediaServerType,
    dynamic runningCrawl,
  }) {
    return ICrawlLink(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      name: name ?? this.name,
      secondName: secondName ?? this.secondName,
      formattedName: formattedName ?? this.formattedName,
      providerId: providerId ?? this.providerId,
      providerRef: providerRef ?? this.providerRef,
      providerItemId: providerItemId ?? this.providerItemId,
      providerCategory: providerCategory ?? this.providerCategory,
      category: category ?? this.category,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      airedEpisodesCount: airedEpisodesCount ?? this.airedEpisodesCount,
      totalEpisodesCount: totalEpisodesCount ?? this.totalEpisodesCount,
      season: season ?? this.season,
      quality: quality ?? this.quality,
      version: version ?? this.version,
      productionYear: productionYear ?? this.productionYear,
      downloaded: downloaded ?? this.downloaded,
      hasError: hasError ?? this.hasError,
      createdBy: createdBy ?? this.createdBy,
      authorId: authorId ?? this.authorId,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      origin: origin ?? this.origin,
      mediaServerType: mediaServerType ?? this.mediaServerType,
      runningCrawl: runningCrawl ?? this.runningCrawl,
    );
  }

  ICrawlLink copyWithWrapped({
    Wrapped<String?>? id,
    Wrapped<String?>? mediaId,
    Wrapped<String?>? name,
    Wrapped<String?>? secondName,
    Wrapped<String?>? formattedName,
    Wrapped<String?>? providerId,
    Wrapped<IProvider?>? providerRef,
    Wrapped<String?>? providerItemId,
    Wrapped<String?>? providerCategory,
    Wrapped<enums.MediaCategory?>? category,
    Wrapped<String?>? url,
    Wrapped<String?>? thumbnailUrl,
    Wrapped<int?>? airedEpisodesCount,
    Wrapped<int?>? totalEpisodesCount,
    Wrapped<int?>? season,
    Wrapped<String?>? quality,
    Wrapped<String?>? version,
    Wrapped<int?>? productionYear,
    Wrapped<bool?>? downloaded,
    Wrapped<bool?>? hasError,
    Wrapped<String?>? createdBy,
    Wrapped<String?>? authorId,
    Wrapped<bool?>? isEnabled,
    Wrapped<DateTime?>? createdAt,
    Wrapped<enums.CreationOrigin?>? origin,
    Wrapped<enums.MediaServerType?>? mediaServerType,
    Wrapped<dynamic>? runningCrawl,
  }) {
    return ICrawlLink(
      id: (id != null ? id.value : this.id),
      mediaId: (mediaId != null ? mediaId.value : this.mediaId),
      name: (name != null ? name.value : this.name),
      secondName: (secondName != null ? secondName.value : this.secondName),
      formattedName: (formattedName != null
          ? formattedName.value
          : this.formattedName),
      providerId: (providerId != null ? providerId.value : this.providerId),
      providerRef: (providerRef != null ? providerRef.value : this.providerRef),
      providerItemId: (providerItemId != null
          ? providerItemId.value
          : this.providerItemId),
      providerCategory: (providerCategory != null
          ? providerCategory.value
          : this.providerCategory),
      category: (category != null ? category.value : this.category),
      url: (url != null ? url.value : this.url),
      thumbnailUrl: (thumbnailUrl != null
          ? thumbnailUrl.value
          : this.thumbnailUrl),
      airedEpisodesCount: (airedEpisodesCount != null
          ? airedEpisodesCount.value
          : this.airedEpisodesCount),
      totalEpisodesCount: (totalEpisodesCount != null
          ? totalEpisodesCount.value
          : this.totalEpisodesCount),
      season: (season != null ? season.value : this.season),
      quality: (quality != null ? quality.value : this.quality),
      version: (version != null ? version.value : this.version),
      productionYear: (productionYear != null
          ? productionYear.value
          : this.productionYear),
      downloaded: (downloaded != null ? downloaded.value : this.downloaded),
      hasError: (hasError != null ? hasError.value : this.hasError),
      createdBy: (createdBy != null ? createdBy.value : this.createdBy),
      authorId: (authorId != null ? authorId.value : this.authorId),
      isEnabled: (isEnabled != null ? isEnabled.value : this.isEnabled),
      createdAt: (createdAt != null ? createdAt.value : this.createdAt),
      origin: (origin != null ? origin.value : this.origin),
      mediaServerType: (mediaServerType != null
          ? mediaServerType.value
          : this.mediaServerType),
      runningCrawl: (runningCrawl != null
          ? runningCrawl.value
          : this.runningCrawl),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class IScheduledCrawl {
  const IScheduledCrawl({
    this.id,
    this.crawlLinkId,
    this.jobId,
    this.crawlLinkRef,
    this.name,
    this.mediaName,
    this.mediaFolder,
    this.url,
    this.thumbnailUrl,
    this.downloadLinks,
    this.extractedLinks,
    this.failedEpisodes,
    this.status,
    this.hasError,
    this.createdAt,
    this.extractedItemInfo,
  });

  factory IScheduledCrawl.fromJson(Map<String, dynamic> json) =>
      _$IScheduledCrawlFromJson(json);

  static const toJsonFactory = _$IScheduledCrawlToJson;
  Map<String, dynamic> toJson() => _$IScheduledCrawlToJson(this);

  @JsonKey(name: 'id', includeIfNull: false)
  final String? id;
  @JsonKey(name: 'crawlLinkId', includeIfNull: false)
  final String? crawlLinkId;
  @JsonKey(name: 'jobId', includeIfNull: false)
  final String? jobId;
  @JsonKey(name: 'crawlLinkRef', includeIfNull: false)
  final ICrawlLink? crawlLinkRef;
  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'mediaName', includeIfNull: false)
  final String? mediaName;
  @JsonKey(name: 'mediaFolder', includeIfNull: false)
  final String? mediaFolder;
  @JsonKey(name: 'url', includeIfNull: false)
  final String? url;
  @JsonKey(name: 'thumbnailUrl', includeIfNull: false)
  final String? thumbnailUrl;
  @JsonKey(
    name: 'downloadLinks',
    includeIfNull: false,
    defaultValue: <DownloadLink>[],
  )
  final List<DownloadLink>? downloadLinks;
  @JsonKey(
    name: 'extractedLinks',
    includeIfNull: false,
    defaultValue: <DownloadLink>[],
  )
  final List<DownloadLink>? extractedLinks;
  @JsonKey(name: 'failedEpisodes', includeIfNull: false, defaultValue: <int>[])
  final List<int>? failedEpisodes;
  @JsonKey(
    name: 'status',
    includeIfNull: false,
    toJson: crawlStatusNullableToJson,
    fromJson: crawlStatusNullableFromJson,
  )
  final enums.CrawlStatus? status;
  @JsonKey(name: 'hasError', includeIfNull: false)
  final bool? hasError;
  @JsonKey(name: 'createdAt', includeIfNull: false)
  final DateTime? createdAt;
  @JsonKey(name: 'extractedItemInfo', includeIfNull: false)
  final dynamic extractedItemInfo;
  static const fromJsonFactory = _$IScheduledCrawlFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is IScheduledCrawl &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.crawlLinkId, crawlLinkId) ||
                const DeepCollectionEquality().equals(
                  other.crawlLinkId,
                  crawlLinkId,
                )) &&
            (identical(other.jobId, jobId) ||
                const DeepCollectionEquality().equals(other.jobId, jobId)) &&
            (identical(other.crawlLinkRef, crawlLinkRef) ||
                const DeepCollectionEquality().equals(
                  other.crawlLinkRef,
                  crawlLinkRef,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.mediaName, mediaName) ||
                const DeepCollectionEquality().equals(
                  other.mediaName,
                  mediaName,
                )) &&
            (identical(other.mediaFolder, mediaFolder) ||
                const DeepCollectionEquality().equals(
                  other.mediaFolder,
                  mediaFolder,
                )) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                const DeepCollectionEquality().equals(
                  other.thumbnailUrl,
                  thumbnailUrl,
                )) &&
            (identical(other.downloadLinks, downloadLinks) ||
                const DeepCollectionEquality().equals(
                  other.downloadLinks,
                  downloadLinks,
                )) &&
            (identical(other.extractedLinks, extractedLinks) ||
                const DeepCollectionEquality().equals(
                  other.extractedLinks,
                  extractedLinks,
                )) &&
            (identical(other.failedEpisodes, failedEpisodes) ||
                const DeepCollectionEquality().equals(
                  other.failedEpisodes,
                  failedEpisodes,
                )) &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.hasError, hasError) ||
                const DeepCollectionEquality().equals(
                  other.hasError,
                  hasError,
                )) &&
            (identical(other.createdAt, createdAt) ||
                const DeepCollectionEquality().equals(
                  other.createdAt,
                  createdAt,
                )) &&
            (identical(other.extractedItemInfo, extractedItemInfo) ||
                const DeepCollectionEquality().equals(
                  other.extractedItemInfo,
                  extractedItemInfo,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(crawlLinkId) ^
      const DeepCollectionEquality().hash(jobId) ^
      const DeepCollectionEquality().hash(crawlLinkRef) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(mediaName) ^
      const DeepCollectionEquality().hash(mediaFolder) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(thumbnailUrl) ^
      const DeepCollectionEquality().hash(downloadLinks) ^
      const DeepCollectionEquality().hash(extractedLinks) ^
      const DeepCollectionEquality().hash(failedEpisodes) ^
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(hasError) ^
      const DeepCollectionEquality().hash(createdAt) ^
      const DeepCollectionEquality().hash(extractedItemInfo) ^
      runtimeType.hashCode;
}

extension $IScheduledCrawlExtension on IScheduledCrawl {
  IScheduledCrawl copyWith({
    String? id,
    String? crawlLinkId,
    String? jobId,
    ICrawlLink? crawlLinkRef,
    String? name,
    String? mediaName,
    String? mediaFolder,
    String? url,
    String? thumbnailUrl,
    List<DownloadLink>? downloadLinks,
    List<DownloadLink>? extractedLinks,
    List<int>? failedEpisodes,
    enums.CrawlStatus? status,
    bool? hasError,
    DateTime? createdAt,
    dynamic extractedItemInfo,
  }) {
    return IScheduledCrawl(
      id: id ?? this.id,
      crawlLinkId: crawlLinkId ?? this.crawlLinkId,
      jobId: jobId ?? this.jobId,
      crawlLinkRef: crawlLinkRef ?? this.crawlLinkRef,
      name: name ?? this.name,
      mediaName: mediaName ?? this.mediaName,
      mediaFolder: mediaFolder ?? this.mediaFolder,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      downloadLinks: downloadLinks ?? this.downloadLinks,
      extractedLinks: extractedLinks ?? this.extractedLinks,
      failedEpisodes: failedEpisodes ?? this.failedEpisodes,
      status: status ?? this.status,
      hasError: hasError ?? this.hasError,
      createdAt: createdAt ?? this.createdAt,
      extractedItemInfo: extractedItemInfo ?? this.extractedItemInfo,
    );
  }

  IScheduledCrawl copyWithWrapped({
    Wrapped<String?>? id,
    Wrapped<String?>? crawlLinkId,
    Wrapped<String?>? jobId,
    Wrapped<ICrawlLink?>? crawlLinkRef,
    Wrapped<String?>? name,
    Wrapped<String?>? mediaName,
    Wrapped<String?>? mediaFolder,
    Wrapped<String?>? url,
    Wrapped<String?>? thumbnailUrl,
    Wrapped<List<DownloadLink>?>? downloadLinks,
    Wrapped<List<DownloadLink>?>? extractedLinks,
    Wrapped<List<int>?>? failedEpisodes,
    Wrapped<enums.CrawlStatus?>? status,
    Wrapped<bool?>? hasError,
    Wrapped<DateTime?>? createdAt,
    Wrapped<dynamic>? extractedItemInfo,
  }) {
    return IScheduledCrawl(
      id: (id != null ? id.value : this.id),
      crawlLinkId: (crawlLinkId != null ? crawlLinkId.value : this.crawlLinkId),
      jobId: (jobId != null ? jobId.value : this.jobId),
      crawlLinkRef: (crawlLinkRef != null
          ? crawlLinkRef.value
          : this.crawlLinkRef),
      name: (name != null ? name.value : this.name),
      mediaName: (mediaName != null ? mediaName.value : this.mediaName),
      mediaFolder: (mediaFolder != null ? mediaFolder.value : this.mediaFolder),
      url: (url != null ? url.value : this.url),
      thumbnailUrl: (thumbnailUrl != null
          ? thumbnailUrl.value
          : this.thumbnailUrl),
      downloadLinks: (downloadLinks != null
          ? downloadLinks.value
          : this.downloadLinks),
      extractedLinks: (extractedLinks != null
          ? extractedLinks.value
          : this.extractedLinks),
      failedEpisodes: (failedEpisodes != null
          ? failedEpisodes.value
          : this.failedEpisodes),
      status: (status != null ? status.value : this.status),
      hasError: (hasError != null ? hasError.value : this.hasError),
      createdAt: (createdAt != null ? createdAt.value : this.createdAt),
      extractedItemInfo: (extractedItemInfo != null
          ? extractedItemInfo.value
          : this.extractedItemInfo),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DownloadLink {
  const DownloadLink({
    this.index,
    this.link,
    this.version,
    this.qualityLabel,
    this.quality,
    this.size,
    this.sizeUnit,
    this.fileHost,
  });

  factory DownloadLink.fromJson(Map<String, dynamic> json) =>
      _$DownloadLinkFromJson(json);

  static const toJsonFactory = _$DownloadLinkToJson;
  Map<String, dynamic> toJson() => _$DownloadLinkToJson(this);

  @JsonKey(name: 'index', includeIfNull: false)
  final int? index;
  @JsonKey(name: 'link', includeIfNull: false)
  final String? link;
  @JsonKey(name: 'version', includeIfNull: false)
  final String? version;
  @JsonKey(name: 'quality_label', includeIfNull: false)
  final String? qualityLabel;
  @JsonKey(
    name: 'quality',
    includeIfNull: false,
    toJson: mediaQualityNullableToJson,
    fromJson: mediaQualityNullableFromJson,
  )
  final enums.MediaQuality? quality;
  @JsonKey(name: 'size', includeIfNull: false)
  final double? size;
  @JsonKey(name: 'size_unit', includeIfNull: false)
  final String? sizeUnit;
  @JsonKey(name: 'file_host', includeIfNull: false)
  final String? fileHost;
  static const fromJsonFactory = _$DownloadLinkFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DownloadLink &&
            (identical(other.index, index) ||
                const DeepCollectionEquality().equals(other.index, index)) &&
            (identical(other.link, link) ||
                const DeepCollectionEquality().equals(other.link, link)) &&
            (identical(other.version, version) ||
                const DeepCollectionEquality().equals(
                  other.version,
                  version,
                )) &&
            (identical(other.qualityLabel, qualityLabel) ||
                const DeepCollectionEquality().equals(
                  other.qualityLabel,
                  qualityLabel,
                )) &&
            (identical(other.quality, quality) ||
                const DeepCollectionEquality().equals(
                  other.quality,
                  quality,
                )) &&
            (identical(other.size, size) ||
                const DeepCollectionEquality().equals(other.size, size)) &&
            (identical(other.sizeUnit, sizeUnit) ||
                const DeepCollectionEquality().equals(
                  other.sizeUnit,
                  sizeUnit,
                )) &&
            (identical(other.fileHost, fileHost) ||
                const DeepCollectionEquality().equals(
                  other.fileHost,
                  fileHost,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(index) ^
      const DeepCollectionEquality().hash(link) ^
      const DeepCollectionEquality().hash(version) ^
      const DeepCollectionEquality().hash(qualityLabel) ^
      const DeepCollectionEquality().hash(quality) ^
      const DeepCollectionEquality().hash(size) ^
      const DeepCollectionEquality().hash(sizeUnit) ^
      const DeepCollectionEquality().hash(fileHost) ^
      runtimeType.hashCode;
}

extension $DownloadLinkExtension on DownloadLink {
  DownloadLink copyWith({
    int? index,
    String? link,
    String? version,
    String? qualityLabel,
    enums.MediaQuality? quality,
    double? size,
    String? sizeUnit,
    String? fileHost,
  }) {
    return DownloadLink(
      index: index ?? this.index,
      link: link ?? this.link,
      version: version ?? this.version,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      quality: quality ?? this.quality,
      size: size ?? this.size,
      sizeUnit: sizeUnit ?? this.sizeUnit,
      fileHost: fileHost ?? this.fileHost,
    );
  }

  DownloadLink copyWithWrapped({
    Wrapped<int?>? index,
    Wrapped<String?>? link,
    Wrapped<String?>? version,
    Wrapped<String?>? qualityLabel,
    Wrapped<enums.MediaQuality?>? quality,
    Wrapped<double?>? size,
    Wrapped<String?>? sizeUnit,
    Wrapped<String?>? fileHost,
  }) {
    return DownloadLink(
      index: (index != null ? index.value : this.index),
      link: (link != null ? link.value : this.link),
      version: (version != null ? version.value : this.version),
      qualityLabel: (qualityLabel != null
          ? qualityLabel.value
          : this.qualityLabel),
      quality: (quality != null ? quality.value : this.quality),
      size: (size != null ? size.value : this.size),
      sizeUnit: (sizeUnit != null ? sizeUnit.value : this.sizeUnit),
      fileHost: (fileHost != null ? fileHost.value : this.fileHost),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class IExtractedItemInfo {
  const IExtractedItemInfo({
    this.provider,
    this.title,
    this.originalTitle,
    this.relativeUrl,
    this.version,
    this.providerId,
    this.season,
    this.airedEpisodesCount,
    this.totalEpisodesCount,
    this.seasonCount,
    this.quality,
    this.providerCategory,
    this.productionYear,
    this.category,
    this.downloadLinks,
    this.thumbnailUrl,
  });

  factory IExtractedItemInfo.fromJson(Map<String, dynamic> json) =>
      _$IExtractedItemInfoFromJson(json);

  static const toJsonFactory = _$IExtractedItemInfoToJson;
  Map<String, dynamic> toJson() => _$IExtractedItemInfoToJson(this);

  @JsonKey(name: 'provider', includeIfNull: false)
  final IProvider? provider;
  @JsonKey(name: 'title', includeIfNull: false)
  final String? title;
  @JsonKey(name: 'originalTitle', includeIfNull: false)
  final String? originalTitle;
  @JsonKey(name: 'relativeUrl', includeIfNull: false)
  final String? relativeUrl;
  @JsonKey(name: 'version', includeIfNull: false)
  final String? version;
  @JsonKey(name: 'providerId', includeIfNull: false)
  final String? providerId;
  @JsonKey(name: 'season', includeIfNull: false)
  final int? season;
  @JsonKey(name: 'airedEpisodesCount', includeIfNull: false)
  final int? airedEpisodesCount;
  @JsonKey(name: 'totalEpisodesCount', includeIfNull: false)
  final int? totalEpisodesCount;
  @JsonKey(name: 'seasonCount', includeIfNull: false)
  final int? seasonCount;
  @JsonKey(name: 'quality', includeIfNull: false)
  final String? quality;
  @JsonKey(name: 'providerCategory', includeIfNull: false)
  final String? providerCategory;
  @JsonKey(name: 'productionYear', includeIfNull: false)
  final int? productionYear;
  @JsonKey(
    name: 'category',
    includeIfNull: false,
    toJson: mediaCategoryNullableToJson,
    fromJson: mediaCategoryNullableFromJson,
  )
  final enums.MediaCategory? category;
  @JsonKey(
    name: 'downloadLinks',
    includeIfNull: false,
    defaultValue: <DownloadLink>[],
  )
  final List<DownloadLink>? downloadLinks;
  @JsonKey(name: 'thumbnailUrl', includeIfNull: false)
  final String? thumbnailUrl;
  static const fromJsonFactory = _$IExtractedItemInfoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is IExtractedItemInfo &&
            (identical(other.provider, provider) ||
                const DeepCollectionEquality().equals(
                  other.provider,
                  provider,
                )) &&
            (identical(other.title, title) ||
                const DeepCollectionEquality().equals(other.title, title)) &&
            (identical(other.originalTitle, originalTitle) ||
                const DeepCollectionEquality().equals(
                  other.originalTitle,
                  originalTitle,
                )) &&
            (identical(other.relativeUrl, relativeUrl) ||
                const DeepCollectionEquality().equals(
                  other.relativeUrl,
                  relativeUrl,
                )) &&
            (identical(other.version, version) ||
                const DeepCollectionEquality().equals(
                  other.version,
                  version,
                )) &&
            (identical(other.providerId, providerId) ||
                const DeepCollectionEquality().equals(
                  other.providerId,
                  providerId,
                )) &&
            (identical(other.season, season) ||
                const DeepCollectionEquality().equals(other.season, season)) &&
            (identical(other.airedEpisodesCount, airedEpisodesCount) ||
                const DeepCollectionEquality().equals(
                  other.airedEpisodesCount,
                  airedEpisodesCount,
                )) &&
            (identical(other.totalEpisodesCount, totalEpisodesCount) ||
                const DeepCollectionEquality().equals(
                  other.totalEpisodesCount,
                  totalEpisodesCount,
                )) &&
            (identical(other.seasonCount, seasonCount) ||
                const DeepCollectionEquality().equals(
                  other.seasonCount,
                  seasonCount,
                )) &&
            (identical(other.quality, quality) ||
                const DeepCollectionEquality().equals(
                  other.quality,
                  quality,
                )) &&
            (identical(other.providerCategory, providerCategory) ||
                const DeepCollectionEquality().equals(
                  other.providerCategory,
                  providerCategory,
                )) &&
            (identical(other.productionYear, productionYear) ||
                const DeepCollectionEquality().equals(
                  other.productionYear,
                  productionYear,
                )) &&
            (identical(other.category, category) ||
                const DeepCollectionEquality().equals(
                  other.category,
                  category,
                )) &&
            (identical(other.downloadLinks, downloadLinks) ||
                const DeepCollectionEquality().equals(
                  other.downloadLinks,
                  downloadLinks,
                )) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                const DeepCollectionEquality().equals(
                  other.thumbnailUrl,
                  thumbnailUrl,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(provider) ^
      const DeepCollectionEquality().hash(title) ^
      const DeepCollectionEquality().hash(originalTitle) ^
      const DeepCollectionEquality().hash(relativeUrl) ^
      const DeepCollectionEquality().hash(version) ^
      const DeepCollectionEquality().hash(providerId) ^
      const DeepCollectionEquality().hash(season) ^
      const DeepCollectionEquality().hash(airedEpisodesCount) ^
      const DeepCollectionEquality().hash(totalEpisodesCount) ^
      const DeepCollectionEquality().hash(seasonCount) ^
      const DeepCollectionEquality().hash(quality) ^
      const DeepCollectionEquality().hash(providerCategory) ^
      const DeepCollectionEquality().hash(productionYear) ^
      const DeepCollectionEquality().hash(category) ^
      const DeepCollectionEquality().hash(downloadLinks) ^
      const DeepCollectionEquality().hash(thumbnailUrl) ^
      runtimeType.hashCode;
}

extension $IExtractedItemInfoExtension on IExtractedItemInfo {
  IExtractedItemInfo copyWith({
    IProvider? provider,
    String? title,
    String? originalTitle,
    String? relativeUrl,
    String? version,
    String? providerId,
    int? season,
    int? airedEpisodesCount,
    int? totalEpisodesCount,
    int? seasonCount,
    String? quality,
    String? providerCategory,
    int? productionYear,
    enums.MediaCategory? category,
    List<DownloadLink>? downloadLinks,
    String? thumbnailUrl,
  }) {
    return IExtractedItemInfo(
      provider: provider ?? this.provider,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      relativeUrl: relativeUrl ?? this.relativeUrl,
      version: version ?? this.version,
      providerId: providerId ?? this.providerId,
      season: season ?? this.season,
      airedEpisodesCount: airedEpisodesCount ?? this.airedEpisodesCount,
      totalEpisodesCount: totalEpisodesCount ?? this.totalEpisodesCount,
      seasonCount: seasonCount ?? this.seasonCount,
      quality: quality ?? this.quality,
      providerCategory: providerCategory ?? this.providerCategory,
      productionYear: productionYear ?? this.productionYear,
      category: category ?? this.category,
      downloadLinks: downloadLinks ?? this.downloadLinks,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }

  IExtractedItemInfo copyWithWrapped({
    Wrapped<IProvider?>? provider,
    Wrapped<String?>? title,
    Wrapped<String?>? originalTitle,
    Wrapped<String?>? relativeUrl,
    Wrapped<String?>? version,
    Wrapped<String?>? providerId,
    Wrapped<int?>? season,
    Wrapped<int?>? airedEpisodesCount,
    Wrapped<int?>? totalEpisodesCount,
    Wrapped<int?>? seasonCount,
    Wrapped<String?>? quality,
    Wrapped<String?>? providerCategory,
    Wrapped<int?>? productionYear,
    Wrapped<enums.MediaCategory?>? category,
    Wrapped<List<DownloadLink>?>? downloadLinks,
    Wrapped<String?>? thumbnailUrl,
  }) {
    return IExtractedItemInfo(
      provider: (provider != null ? provider.value : this.provider),
      title: (title != null ? title.value : this.title),
      originalTitle: (originalTitle != null
          ? originalTitle.value
          : this.originalTitle),
      relativeUrl: (relativeUrl != null ? relativeUrl.value : this.relativeUrl),
      version: (version != null ? version.value : this.version),
      providerId: (providerId != null ? providerId.value : this.providerId),
      season: (season != null ? season.value : this.season),
      airedEpisodesCount: (airedEpisodesCount != null
          ? airedEpisodesCount.value
          : this.airedEpisodesCount),
      totalEpisodesCount: (totalEpisodesCount != null
          ? totalEpisodesCount.value
          : this.totalEpisodesCount),
      seasonCount: (seasonCount != null ? seasonCount.value : this.seasonCount),
      quality: (quality != null ? quality.value : this.quality),
      providerCategory: (providerCategory != null
          ? providerCategory.value
          : this.providerCategory),
      productionYear: (productionYear != null
          ? productionYear.value
          : this.productionYear),
      category: (category != null ? category.value : this.category),
      downloadLinks: (downloadLinks != null
          ? downloadLinks.value
          : this.downloadLinks),
      thumbnailUrl: (thumbnailUrl != null
          ? thumbnailUrl.value
          : this.thumbnailUrl),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ISearchFilter {
  const ISearchFilter({
    this.label,
    this.name,
    this.$value,
    this.valueLabel,
    this.options,
  });

  factory ISearchFilter.fromJson(Map<String, dynamic> json) =>
      _$ISearchFilterFromJson(json);

  static const toJsonFactory = _$ISearchFilterToJson;
  Map<String, dynamic> toJson() => _$ISearchFilterToJson(this);

  @JsonKey(name: 'label', includeIfNull: false)
  final String? label;
  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'value', includeIfNull: false)
  final String? $value;
  @JsonKey(name: 'valueLabel', includeIfNull: false)
  final String? valueLabel;
  @JsonKey(
    name: 'options',
    includeIfNull: false,
    defaultValue: <ISearchFilterOption>[],
  )
  final List<ISearchFilterOption>? options;
  static const fromJsonFactory = _$ISearchFilterFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ISearchFilter &&
            (identical(other.label, label) ||
                const DeepCollectionEquality().equals(other.label, label)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.$value, $value) ||
                const DeepCollectionEquality().equals(other.$value, $value)) &&
            (identical(other.valueLabel, valueLabel) ||
                const DeepCollectionEquality().equals(
                  other.valueLabel,
                  valueLabel,
                )) &&
            (identical(other.options, options) ||
                const DeepCollectionEquality().equals(other.options, options)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(label) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash($value) ^
      const DeepCollectionEquality().hash(valueLabel) ^
      const DeepCollectionEquality().hash(options) ^
      runtimeType.hashCode;
}

extension $ISearchFilterExtension on ISearchFilter {
  ISearchFilter copyWith({
    String? label,
    String? name,
    String? $value,
    String? valueLabel,
    List<ISearchFilterOption>? options,
  }) {
    return ISearchFilter(
      label: label ?? this.label,
      name: name ?? this.name,
      $value: $value ?? this.$value,
      valueLabel: valueLabel ?? this.valueLabel,
      options: options ?? this.options,
    );
  }

  ISearchFilter copyWithWrapped({
    Wrapped<String?>? label,
    Wrapped<String?>? name,
    Wrapped<String?>? $value,
    Wrapped<String?>? valueLabel,
    Wrapped<List<ISearchFilterOption>?>? options,
  }) {
    return ISearchFilter(
      label: (label != null ? label.value : this.label),
      name: (name != null ? name.value : this.name),
      $value: ($value != null ? $value.value : this.$value),
      valueLabel: (valueLabel != null ? valueLabel.value : this.valueLabel),
      options: (options != null ? options.value : this.options),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ISearchFilterOption {
  const ISearchFilterOption({this.label, this.$value});

  factory ISearchFilterOption.fromJson(Map<String, dynamic> json) =>
      _$ISearchFilterOptionFromJson(json);

  static const toJsonFactory = _$ISearchFilterOptionToJson;
  Map<String, dynamic> toJson() => _$ISearchFilterOptionToJson(this);

  @JsonKey(name: 'label', includeIfNull: false)
  final String? label;
  @JsonKey(name: 'value', includeIfNull: false)
  final String? $value;
  static const fromJsonFactory = _$ISearchFilterOptionFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ISearchFilterOption &&
            (identical(other.label, label) ||
                const DeepCollectionEquality().equals(other.label, label)) &&
            (identical(other.$value, $value) ||
                const DeepCollectionEquality().equals(other.$value, $value)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(label) ^
      const DeepCollectionEquality().hash($value) ^
      runtimeType.hashCode;
}

extension $ISearchFilterOptionExtension on ISearchFilterOption {
  ISearchFilterOption copyWith({String? label, String? $value}) {
    return ISearchFilterOption(
      label: label ?? this.label,
      $value: $value ?? this.$value,
    );
  }

  ISearchFilterOption copyWithWrapped({
    Wrapped<String?>? label,
    Wrapped<String?>? $value,
  }) {
    return ISearchFilterOption(
      label: (label != null ? label.value : this.label),
      $value: ($value != null ? $value.value : this.$value),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PaginatedResponseOfProviderSearchItemDto {
  const PaginatedResponseOfProviderSearchItemDto({
    this.currentPage,
    this.totalPages,
    this.pageSize,
    this.totalCount,
    this.items,
  });

  factory PaginatedResponseOfProviderSearchItemDto.fromJson(
    Map<String, dynamic> json,
  ) => _$PaginatedResponseOfProviderSearchItemDtoFromJson(json);

  static const toJsonFactory = _$PaginatedResponseOfProviderSearchItemDtoToJson;
  Map<String, dynamic> toJson() =>
      _$PaginatedResponseOfProviderSearchItemDtoToJson(this);

  @JsonKey(name: 'currentPage', includeIfNull: false)
  final int? currentPage;
  @JsonKey(name: 'totalPages', includeIfNull: false)
  final int? totalPages;
  @JsonKey(name: 'pageSize', includeIfNull: false)
  final int? pageSize;
  @JsonKey(name: 'totalCount', includeIfNull: false)
  final int? totalCount;
  @JsonKey(
    name: 'items',
    includeIfNull: false,
    defaultValue: <ProviderSearchItemDto>[],
  )
  final List<ProviderSearchItemDto>? items;
  static const fromJsonFactory =
      _$PaginatedResponseOfProviderSearchItemDtoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PaginatedResponseOfProviderSearchItemDto &&
            (identical(other.currentPage, currentPage) ||
                const DeepCollectionEquality().equals(
                  other.currentPage,
                  currentPage,
                )) &&
            (identical(other.totalPages, totalPages) ||
                const DeepCollectionEquality().equals(
                  other.totalPages,
                  totalPages,
                )) &&
            (identical(other.pageSize, pageSize) ||
                const DeepCollectionEquality().equals(
                  other.pageSize,
                  pageSize,
                )) &&
            (identical(other.totalCount, totalCount) ||
                const DeepCollectionEquality().equals(
                  other.totalCount,
                  totalCount,
                )) &&
            (identical(other.items, items) ||
                const DeepCollectionEquality().equals(other.items, items)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(currentPage) ^
      const DeepCollectionEquality().hash(totalPages) ^
      const DeepCollectionEquality().hash(pageSize) ^
      const DeepCollectionEquality().hash(totalCount) ^
      const DeepCollectionEquality().hash(items) ^
      runtimeType.hashCode;
}

extension $PaginatedResponseOfProviderSearchItemDtoExtension
    on PaginatedResponseOfProviderSearchItemDto {
  PaginatedResponseOfProviderSearchItemDto copyWith({
    int? currentPage,
    int? totalPages,
    int? pageSize,
    int? totalCount,
    List<ProviderSearchItemDto>? items,
  }) {
    return PaginatedResponseOfProviderSearchItemDto(
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      pageSize: pageSize ?? this.pageSize,
      totalCount: totalCount ?? this.totalCount,
      items: items ?? this.items,
    );
  }

  PaginatedResponseOfProviderSearchItemDto copyWithWrapped({
    Wrapped<int?>? currentPage,
    Wrapped<int?>? totalPages,
    Wrapped<int?>? pageSize,
    Wrapped<int?>? totalCount,
    Wrapped<List<ProviderSearchItemDto>?>? items,
  }) {
    return PaginatedResponseOfProviderSearchItemDto(
      currentPage: (currentPage != null ? currentPage.value : this.currentPage),
      totalPages: (totalPages != null ? totalPages.value : this.totalPages),
      pageSize: (pageSize != null ? pageSize.value : this.pageSize),
      totalCount: (totalCount != null ? totalCount.value : this.totalCount),
      items: (items != null ? items.value : this.items),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ProviderSearchItemDto {
  const ProviderSearchItemDto({
    this.title,
    this.description,
    this.url,
    this.thumbnailUrl,
  });

  factory ProviderSearchItemDto.fromJson(Map<String, dynamic> json) =>
      _$ProviderSearchItemDtoFromJson(json);

  static const toJsonFactory = _$ProviderSearchItemDtoToJson;
  Map<String, dynamic> toJson() => _$ProviderSearchItemDtoToJson(this);

  @JsonKey(name: 'title', includeIfNull: false)
  final String? title;
  @JsonKey(name: 'description', includeIfNull: false)
  final String? description;
  @JsonKey(name: 'url', includeIfNull: false)
  final String? url;
  @JsonKey(name: 'thumbnailUrl', includeIfNull: false)
  final String? thumbnailUrl;
  static const fromJsonFactory = _$ProviderSearchItemDtoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ProviderSearchItemDto &&
            (identical(other.title, title) ||
                const DeepCollectionEquality().equals(other.title, title)) &&
            (identical(other.description, description) ||
                const DeepCollectionEquality().equals(
                  other.description,
                  description,
                )) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                const DeepCollectionEquality().equals(
                  other.thumbnailUrl,
                  thumbnailUrl,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(title) ^
      const DeepCollectionEquality().hash(description) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(thumbnailUrl) ^
      runtimeType.hashCode;
}

extension $ProviderSearchItemDtoExtension on ProviderSearchItemDto {
  ProviderSearchItemDto copyWith({
    String? title,
    String? description,
    String? url,
    String? thumbnailUrl,
  }) {
    return ProviderSearchItemDto(
      title: title ?? this.title,
      description: description ?? this.description,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }

  ProviderSearchItemDto copyWithWrapped({
    Wrapped<String?>? title,
    Wrapped<String?>? description,
    Wrapped<String?>? url,
    Wrapped<String?>? thumbnailUrl,
  }) {
    return ProviderSearchItemDto(
      title: (title != null ? title.value : this.title),
      description: (description != null ? description.value : this.description),
      url: (url != null ? url.value : this.url),
      thumbnailUrl: (thumbnailUrl != null
          ? thumbnailUrl.value
          : this.thumbnailUrl),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ApiMediaSearchRequest {
  const ApiMediaSearchRequest({
    this.filters,
    this.page,
    this.pageSize,
    this.query,
    this.category,
    this.exactMatch,
    this.minScore,
  });

  factory ApiMediaSearchRequest.fromJson(Map<String, dynamic> json) =>
      _$ApiMediaSearchRequestFromJson(json);

  static const toJsonFactory = _$ApiMediaSearchRequestToJson;
  Map<String, dynamic> toJson() => _$ApiMediaSearchRequestToJson(this);

  @JsonKey(
    name: 'filters',
    includeIfNull: false,
    defaultValue: <SearchFilter>[],
  )
  final List<SearchFilter>? filters;
  @JsonKey(name: 'page', includeIfNull: false)
  final int? page;
  @JsonKey(name: 'pageSize', includeIfNull: false)
  final int? pageSize;
  @JsonKey(name: 'query', includeIfNull: false)
  final String? query;
  @JsonKey(
    name: 'category',
    includeIfNull: false,
    toJson: mediaCategoryNullableToJson,
    fromJson: mediaCategoryNullableFromJson,
  )
  final enums.MediaCategory? category;
  @JsonKey(name: 'exactMatch', includeIfNull: false)
  final bool? exactMatch;
  @JsonKey(name: 'minScore', includeIfNull: false)
  final double? minScore;
  static const fromJsonFactory = _$ApiMediaSearchRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ApiMediaSearchRequest &&
            (identical(other.filters, filters) ||
                const DeepCollectionEquality().equals(
                  other.filters,
                  filters,
                )) &&
            (identical(other.page, page) ||
                const DeepCollectionEquality().equals(other.page, page)) &&
            (identical(other.pageSize, pageSize) ||
                const DeepCollectionEquality().equals(
                  other.pageSize,
                  pageSize,
                )) &&
            (identical(other.query, query) ||
                const DeepCollectionEquality().equals(other.query, query)) &&
            (identical(other.category, category) ||
                const DeepCollectionEquality().equals(
                  other.category,
                  category,
                )) &&
            (identical(other.exactMatch, exactMatch) ||
                const DeepCollectionEquality().equals(
                  other.exactMatch,
                  exactMatch,
                )) &&
            (identical(other.minScore, minScore) ||
                const DeepCollectionEquality().equals(
                  other.minScore,
                  minScore,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(filters) ^
      const DeepCollectionEquality().hash(page) ^
      const DeepCollectionEquality().hash(pageSize) ^
      const DeepCollectionEquality().hash(query) ^
      const DeepCollectionEquality().hash(category) ^
      const DeepCollectionEquality().hash(exactMatch) ^
      const DeepCollectionEquality().hash(minScore) ^
      runtimeType.hashCode;
}

extension $ApiMediaSearchRequestExtension on ApiMediaSearchRequest {
  ApiMediaSearchRequest copyWith({
    List<SearchFilter>? filters,
    int? page,
    int? pageSize,
    String? query,
    enums.MediaCategory? category,
    bool? exactMatch,
    double? minScore,
  }) {
    return ApiMediaSearchRequest(
      filters: filters ?? this.filters,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      query: query ?? this.query,
      category: category ?? this.category,
      exactMatch: exactMatch ?? this.exactMatch,
      minScore: minScore ?? this.minScore,
    );
  }

  ApiMediaSearchRequest copyWithWrapped({
    Wrapped<List<SearchFilter>?>? filters,
    Wrapped<int?>? page,
    Wrapped<int?>? pageSize,
    Wrapped<String?>? query,
    Wrapped<enums.MediaCategory?>? category,
    Wrapped<bool?>? exactMatch,
    Wrapped<double?>? minScore,
  }) {
    return ApiMediaSearchRequest(
      filters: (filters != null ? filters.value : this.filters),
      page: (page != null ? page.value : this.page),
      pageSize: (pageSize != null ? pageSize.value : this.pageSize),
      query: (query != null ? query.value : this.query),
      category: (category != null ? category.value : this.category),
      exactMatch: (exactMatch != null ? exactMatch.value : this.exactMatch),
      minScore: (minScore != null ? minScore.value : this.minScore),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class SearchFilter {
  const SearchFilter({
    this.label,
    this.name,
    this.$value,
    this.valueLabel,
    this.options,
  });

  factory SearchFilter.fromJson(Map<String, dynamic> json) =>
      _$SearchFilterFromJson(json);

  static const toJsonFactory = _$SearchFilterToJson;
  Map<String, dynamic> toJson() => _$SearchFilterToJson(this);

  @JsonKey(name: 'label', includeIfNull: false)
  final String? label;
  @JsonKey(name: 'name', includeIfNull: false)
  final String? name;
  @JsonKey(name: 'value', includeIfNull: false)
  final String? $value;
  @JsonKey(name: 'valueLabel', includeIfNull: false)
  final String? valueLabel;
  @JsonKey(
    name: 'options',
    includeIfNull: false,
    defaultValue: <ISearchFilterOption>[],
  )
  final List<ISearchFilterOption>? options;
  static const fromJsonFactory = _$SearchFilterFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SearchFilter &&
            (identical(other.label, label) ||
                const DeepCollectionEquality().equals(other.label, label)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.$value, $value) ||
                const DeepCollectionEquality().equals(other.$value, $value)) &&
            (identical(other.valueLabel, valueLabel) ||
                const DeepCollectionEquality().equals(
                  other.valueLabel,
                  valueLabel,
                )) &&
            (identical(other.options, options) ||
                const DeepCollectionEquality().equals(other.options, options)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(label) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash($value) ^
      const DeepCollectionEquality().hash(valueLabel) ^
      const DeepCollectionEquality().hash(options) ^
      runtimeType.hashCode;
}

extension $SearchFilterExtension on SearchFilter {
  SearchFilter copyWith({
    String? label,
    String? name,
    String? $value,
    String? valueLabel,
    List<ISearchFilterOption>? options,
  }) {
    return SearchFilter(
      label: label ?? this.label,
      name: name ?? this.name,
      $value: $value ?? this.$value,
      valueLabel: valueLabel ?? this.valueLabel,
      options: options ?? this.options,
    );
  }

  SearchFilter copyWithWrapped({
    Wrapped<String?>? label,
    Wrapped<String?>? name,
    Wrapped<String?>? $value,
    Wrapped<String?>? valueLabel,
    Wrapped<List<ISearchFilterOption>?>? options,
  }) {
    return SearchFilter(
      label: (label != null ? label.value : this.label),
      name: (name != null ? name.value : this.name),
      $value: ($value != null ? $value.value : this.$value),
      valueLabel: (valueLabel != null ? valueLabel.value : this.valueLabel),
      options: (options != null ? options.value : this.options),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class MediaSearchRequest {
  const MediaSearchRequest({
    this.query,
    this.category,
    this.exactMatch,
    this.minScore,
  });

  factory MediaSearchRequest.fromJson(Map<String, dynamic> json) =>
      _$MediaSearchRequestFromJson(json);

  static const toJsonFactory = _$MediaSearchRequestToJson;
  Map<String, dynamic> toJson() => _$MediaSearchRequestToJson(this);

  @JsonKey(name: 'query', includeIfNull: false)
  final String? query;
  @JsonKey(
    name: 'category',
    includeIfNull: false,
    toJson: mediaCategoryNullableToJson,
    fromJson: mediaCategoryNullableFromJson,
  )
  final enums.MediaCategory? category;
  @JsonKey(name: 'exactMatch', includeIfNull: false)
  final bool? exactMatch;
  @JsonKey(name: 'minScore', includeIfNull: false)
  final double? minScore;
  static const fromJsonFactory = _$MediaSearchRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MediaSearchRequest &&
            (identical(other.query, query) ||
                const DeepCollectionEquality().equals(other.query, query)) &&
            (identical(other.category, category) ||
                const DeepCollectionEquality().equals(
                  other.category,
                  category,
                )) &&
            (identical(other.exactMatch, exactMatch) ||
                const DeepCollectionEquality().equals(
                  other.exactMatch,
                  exactMatch,
                )) &&
            (identical(other.minScore, minScore) ||
                const DeepCollectionEquality().equals(
                  other.minScore,
                  minScore,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(query) ^
      const DeepCollectionEquality().hash(category) ^
      const DeepCollectionEquality().hash(exactMatch) ^
      const DeepCollectionEquality().hash(minScore) ^
      runtimeType.hashCode;
}

extension $MediaSearchRequestExtension on MediaSearchRequest {
  MediaSearchRequest copyWith({
    String? query,
    enums.MediaCategory? category,
    bool? exactMatch,
    double? minScore,
  }) {
    return MediaSearchRequest(
      query: query ?? this.query,
      category: category ?? this.category,
      exactMatch: exactMatch ?? this.exactMatch,
      minScore: minScore ?? this.minScore,
    );
  }

  MediaSearchRequest copyWithWrapped({
    Wrapped<String?>? query,
    Wrapped<enums.MediaCategory?>? category,
    Wrapped<bool?>? exactMatch,
    Wrapped<double?>? minScore,
  }) {
    return MediaSearchRequest(
      query: (query != null ? query.value : this.query),
      category: (category != null ? category.value : this.category),
      exactMatch: (exactMatch != null ? exactMatch.value : this.exactMatch),
      minScore: (minScore != null ? minScore.value : this.minScore),
    );
  }
}

int? mediaCategoryNullableToJson(enums.MediaCategory? mediaCategory) {
  return mediaCategory?.value;
}

int? mediaCategoryToJson(enums.MediaCategory mediaCategory) {
  return mediaCategory.value;
}

enums.MediaCategory mediaCategoryFromJson(
  Object? mediaCategory, [
  enums.MediaCategory? defaultValue,
]) {
  return enums.MediaCategory.values.firstWhereOrNull(
        (e) => e.value == mediaCategory,
      ) ??
      defaultValue ??
      enums.MediaCategory.swaggerGeneratedUnknown;
}

enums.MediaCategory? mediaCategoryNullableFromJson(
  Object? mediaCategory, [
  enums.MediaCategory? defaultValue,
]) {
  if (mediaCategory == null) {
    return null;
  }
  return enums.MediaCategory.values.firstWhereOrNull(
        (e) => e.value == mediaCategory,
      ) ??
      defaultValue;
}

String mediaCategoryExplodedListToJson(
  List<enums.MediaCategory>? mediaCategory,
) {
  return mediaCategory?.map((e) => e.value!).join(',') ?? '';
}

List<int> mediaCategoryListToJson(List<enums.MediaCategory>? mediaCategory) {
  if (mediaCategory == null) {
    return [];
  }

  return mediaCategory.map((e) => e.value!).toList();
}

List<enums.MediaCategory> mediaCategoryListFromJson(
  List? mediaCategory, [
  List<enums.MediaCategory>? defaultValue,
]) {
  if (mediaCategory == null) {
    return defaultValue ?? [];
  }

  return mediaCategory.map((e) => mediaCategoryFromJson(e.toString())).toList();
}

List<enums.MediaCategory>? mediaCategoryNullableListFromJson(
  List? mediaCategory, [
  List<enums.MediaCategory>? defaultValue,
]) {
  if (mediaCategory == null) {
    return defaultValue;
  }

  return mediaCategory.map((e) => mediaCategoryFromJson(e.toString())).toList();
}

int? creationOriginNullableToJson(enums.CreationOrigin? creationOrigin) {
  return creationOrigin?.value;
}

int? creationOriginToJson(enums.CreationOrigin creationOrigin) {
  return creationOrigin.value;
}

enums.CreationOrigin creationOriginFromJson(
  Object? creationOrigin, [
  enums.CreationOrigin? defaultValue,
]) {
  return enums.CreationOrigin.values.firstWhereOrNull(
        (e) => e.value == creationOrigin,
      ) ??
      defaultValue ??
      enums.CreationOrigin.swaggerGeneratedUnknown;
}

enums.CreationOrigin? creationOriginNullableFromJson(
  Object? creationOrigin, [
  enums.CreationOrigin? defaultValue,
]) {
  if (creationOrigin == null) {
    return null;
  }
  return enums.CreationOrigin.values.firstWhereOrNull(
        (e) => e.value == creationOrigin,
      ) ??
      defaultValue;
}

String creationOriginExplodedListToJson(
  List<enums.CreationOrigin>? creationOrigin,
) {
  return creationOrigin?.map((e) => e.value!).join(',') ?? '';
}

List<int> creationOriginListToJson(List<enums.CreationOrigin>? creationOrigin) {
  if (creationOrigin == null) {
    return [];
  }

  return creationOrigin.map((e) => e.value!).toList();
}

List<enums.CreationOrigin> creationOriginListFromJson(
  List? creationOrigin, [
  List<enums.CreationOrigin>? defaultValue,
]) {
  if (creationOrigin == null) {
    return defaultValue ?? [];
  }

  return creationOrigin
      .map((e) => creationOriginFromJson(e.toString()))
      .toList();
}

List<enums.CreationOrigin>? creationOriginNullableListFromJson(
  List? creationOrigin, [
  List<enums.CreationOrigin>? defaultValue,
]) {
  if (creationOrigin == null) {
    return defaultValue;
  }

  return creationOrigin
      .map((e) => creationOriginFromJson(e.toString()))
      .toList();
}

int? mediaServerTypeNullableToJson(enums.MediaServerType? mediaServerType) {
  return mediaServerType?.value;
}

int? mediaServerTypeToJson(enums.MediaServerType mediaServerType) {
  return mediaServerType.value;
}

enums.MediaServerType mediaServerTypeFromJson(
  Object? mediaServerType, [
  enums.MediaServerType? defaultValue,
]) {
  return enums.MediaServerType.values.firstWhereOrNull(
        (e) => e.value == mediaServerType,
      ) ??
      defaultValue ??
      enums.MediaServerType.swaggerGeneratedUnknown;
}

enums.MediaServerType? mediaServerTypeNullableFromJson(
  Object? mediaServerType, [
  enums.MediaServerType? defaultValue,
]) {
  if (mediaServerType == null) {
    return null;
  }
  return enums.MediaServerType.values.firstWhereOrNull(
        (e) => e.value == mediaServerType,
      ) ??
      defaultValue;
}

String mediaServerTypeExplodedListToJson(
  List<enums.MediaServerType>? mediaServerType,
) {
  return mediaServerType?.map((e) => e.value!).join(',') ?? '';
}

List<int> mediaServerTypeListToJson(
  List<enums.MediaServerType>? mediaServerType,
) {
  if (mediaServerType == null) {
    return [];
  }

  return mediaServerType.map((e) => e.value!).toList();
}

List<enums.MediaServerType> mediaServerTypeListFromJson(
  List? mediaServerType, [
  List<enums.MediaServerType>? defaultValue,
]) {
  if (mediaServerType == null) {
    return defaultValue ?? [];
  }

  return mediaServerType
      .map((e) => mediaServerTypeFromJson(e.toString()))
      .toList();
}

List<enums.MediaServerType>? mediaServerTypeNullableListFromJson(
  List? mediaServerType, [
  List<enums.MediaServerType>? defaultValue,
]) {
  if (mediaServerType == null) {
    return defaultValue;
  }

  return mediaServerType
      .map((e) => mediaServerTypeFromJson(e.toString()))
      .toList();
}

int? mediaQualityNullableToJson(enums.MediaQuality? mediaQuality) {
  return mediaQuality?.value;
}

int? mediaQualityToJson(enums.MediaQuality mediaQuality) {
  return mediaQuality.value;
}

enums.MediaQuality mediaQualityFromJson(
  Object? mediaQuality, [
  enums.MediaQuality? defaultValue,
]) {
  return enums.MediaQuality.values.firstWhereOrNull(
        (e) => e.value == mediaQuality,
      ) ??
      defaultValue ??
      enums.MediaQuality.swaggerGeneratedUnknown;
}

enums.MediaQuality? mediaQualityNullableFromJson(
  Object? mediaQuality, [
  enums.MediaQuality? defaultValue,
]) {
  if (mediaQuality == null) {
    return null;
  }
  return enums.MediaQuality.values.firstWhereOrNull(
        (e) => e.value == mediaQuality,
      ) ??
      defaultValue;
}

String mediaQualityExplodedListToJson(List<enums.MediaQuality>? mediaQuality) {
  return mediaQuality?.map((e) => e.value!).join(',') ?? '';
}

List<int> mediaQualityListToJson(List<enums.MediaQuality>? mediaQuality) {
  if (mediaQuality == null) {
    return [];
  }

  return mediaQuality.map((e) => e.value!).toList();
}

List<enums.MediaQuality> mediaQualityListFromJson(
  List? mediaQuality, [
  List<enums.MediaQuality>? defaultValue,
]) {
  if (mediaQuality == null) {
    return defaultValue ?? [];
  }

  return mediaQuality.map((e) => mediaQualityFromJson(e.toString())).toList();
}

List<enums.MediaQuality>? mediaQualityNullableListFromJson(
  List? mediaQuality, [
  List<enums.MediaQuality>? defaultValue,
]) {
  if (mediaQuality == null) {
    return defaultValue;
  }

  return mediaQuality.map((e) => mediaQualityFromJson(e.toString())).toList();
}

int? crawlStatusNullableToJson(enums.CrawlStatus? crawlStatus) {
  return crawlStatus?.value;
}

int? crawlStatusToJson(enums.CrawlStatus crawlStatus) {
  return crawlStatus.value;
}

enums.CrawlStatus crawlStatusFromJson(
  Object? crawlStatus, [
  enums.CrawlStatus? defaultValue,
]) {
  return enums.CrawlStatus.values.firstWhereOrNull(
        (e) => e.value == crawlStatus,
      ) ??
      defaultValue ??
      enums.CrawlStatus.swaggerGeneratedUnknown;
}

enums.CrawlStatus? crawlStatusNullableFromJson(
  Object? crawlStatus, [
  enums.CrawlStatus? defaultValue,
]) {
  if (crawlStatus == null) {
    return null;
  }
  return enums.CrawlStatus.values.firstWhereOrNull(
        (e) => e.value == crawlStatus,
      ) ??
      defaultValue;
}

String crawlStatusExplodedListToJson(List<enums.CrawlStatus>? crawlStatus) {
  return crawlStatus?.map((e) => e.value!).join(',') ?? '';
}

List<int> crawlStatusListToJson(List<enums.CrawlStatus>? crawlStatus) {
  if (crawlStatus == null) {
    return [];
  }

  return crawlStatus.map((e) => e.value!).toList();
}

List<enums.CrawlStatus> crawlStatusListFromJson(
  List? crawlStatus, [
  List<enums.CrawlStatus>? defaultValue,
]) {
  if (crawlStatus == null) {
    return defaultValue ?? [];
  }

  return crawlStatus.map((e) => crawlStatusFromJson(e.toString())).toList();
}

List<enums.CrawlStatus>? crawlStatusNullableListFromJson(
  List? crawlStatus, [
  List<enums.CrawlStatus>? defaultValue,
]) {
  if (crawlStatus == null) {
    return defaultValue;
  }

  return crawlStatus.map((e) => crawlStatusFromJson(e.toString())).toList();
}

typedef $JsonFactory<T> = T Function(Map<String, dynamic> json);

class $CustomJsonDecoder {
  $CustomJsonDecoder(this.factories);

  final Map<Type, $JsonFactory> factories;

  dynamic decode<T>(dynamic entity) {
    if (entity is Iterable) {
      return _decodeList<T>(entity);
    }

    if (entity is T) {
      return entity;
    }

    if (isTypeOf<T, Map>()) {
      return entity;
    }

    if (isTypeOf<T, Iterable>()) {
      return entity;
    }

    if (entity is Map<String, dynamic>) {
      return _decodeMap<T>(entity);
    }

    return entity;
  }

  T _decodeMap<T>(Map<String, dynamic> values) {
    final jsonFactory = factories[T];
    if (jsonFactory == null || jsonFactory is! $JsonFactory<T>) {
      return throw "Could not find factory for type $T. Is '$T: $T.fromJsonFactory' included in the CustomJsonDecoder instance creation in bootstrapper.dart?";
    }

    return jsonFactory(values);
  }

  List<T> _decodeList<T>(Iterable values) =>
      values.where((v) => v != null).map<T>((v) => decode<T>(v) as T).toList();
}

class $JsonSerializableConverter extends chopper.JsonConverter {
  @override
  FutureOr<chopper.Response<ResultType>> convertResponse<ResultType, Item>(
    chopper.Response response,
  ) async {
    if (response.bodyString.isEmpty) {
      // In rare cases, when let's say 204 (no content) is returned -
      // we cannot decode the missing json with the result type specified
      return chopper.Response(response.base, null, error: response.error);
    }

    if (ResultType == String) {
      return response.copyWith();
    }

    if (ResultType == DateTime) {
      return response.copyWith(
        body:
            DateTime.parse((response.body as String).replaceAll('"', ''))
                as ResultType,
      );
    }

    final jsonRes = await super.convertResponse(response);
    return jsonRes.copyWith<ResultType>(
      body: $jsonDecoder.decode<Item>(jsonRes.body) as ResultType,
    );
  }
}

final $jsonDecoder = $CustomJsonDecoder(generatedMapping);

// ignore: unused_element
String? _dateToJson(DateTime? date) {
  if (date == null) {
    return null;
  }

  final year = date.year.toString();
  final month = date.month < 10 ? '0${date.month}' : date.month.toString();
  final day = date.day < 10 ? '0${date.day}' : date.day.toString();

  return '$year-$month-$day';
}

class Wrapped<T> {
  final T value;
  const Wrapped.value(this.value);
}
