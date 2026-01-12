// dart format width=80
//Generated jellyfin api code

part of 'jellybot.swagger.dart';

// **************************************************************************
// ChopperGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
final class _$Jellybot extends Jellybot {
  _$Jellybot([ChopperClient? client]) {
    if (client == null) return;
    this.client = client;
  }

  @override
  final Type definitionType = Jellybot;

  @override
  Future<Response<dynamic>> _apiHealthGet() {
    final Uri $url = Uri.parse('/api/health');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<String>> _apiLogsGet({DateTime? date}) {
    final Uri $url = Uri.parse('/api/logs');
    final Map<String, dynamic> $params = <String, dynamic>{'date': date};
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<String, String>($request);
  }

  @override
  Future<Response<PaginatedResponseOfCrawlLinkDto>> _apiCrawlLinksGet({
    int? page,
    int? limit,
  }) {
    final Uri $url = Uri.parse('/api/crawl-links');
    final Map<String, dynamic> $params = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<PaginatedResponseOfCrawlLinkDto,
        PaginatedResponseOfCrawlLinkDto>($request);
  }

  @override
  Future<Response<ExtractMediaResponse>> _apiCrawlLinksPost(
      {required ExtractMediaRequest? body}) {
    final Uri $url = Uri.parse('/api/crawl-links');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<ExtractMediaResponse, ExtractMediaResponse>($request);
  }

  @override
  Future<Response<dynamic>> _apiCrawlLinksDelete({String? id}) {
    final Uri $url = Uri.parse('/api/crawl-links');
    final Map<String, dynamic> $params = <String, dynamic>{'id': id};
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<ExtractMediaResponse>> _apiCrawlLinksSelectSeasonPost(
      {required SelectSeasonRequest? body}) {
    final Uri $url = Uri.parse('/api/crawl-links/select-season');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<ExtractMediaResponse, ExtractMediaResponse>($request);
  }

  @override
  Future<Response<CrawlLinkDto>> _apiCrawlLinksConfirmAddPost(
      {required ExtractMediaConfirmationRequest? body}) {
    final Uri $url = Uri.parse('/api/crawl-links/confirm-add');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<CrawlLinkDto, CrawlLinkDto>($request);
  }

  @override
  Future<Response<RenameLinkResult>> _apiCrawlLinksCrawlLinkIdRenamePut({
    required String? crawlLinkId,
    required RenameCrawlLinkRequest? body,
  }) {
    final Uri $url = Uri.parse('/api/crawl-links/${crawlLinkId}/rename');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<RenameLinkResult, RenameLinkResult>($request);
  }

  @override
  Future<Response<String>> _apiDebridFileHostGet({
    required String? fileHost,
    String? url,
  }) {
    final Uri $url = Uri.parse('/api/debrid/${fileHost}');
    final Map<String, dynamic> $params = <String, dynamic>{'url': url};
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<String, String>($request);
  }

  @override
  Future<Response<List<DownloadDto>>> _apiDownloadsGet() {
    final Uri $url = Uri.parse('/api/downloads');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<List<DownloadDto>, DownloadDto>($request);
  }

  @override
  Future<Response<dynamic>> _apiDownloadsDelete({String? url}) {
    final Uri $url = Uri.parse('/api/downloads');
    final Map<String, dynamic> $params = <String, dynamic>{'url': url};
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<String>> _apiIptvAtlasProGet() {
    final Uri $url = Uri.parse('/api/iptv/atlas-pro');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<String, String>($request);
  }

  @override
  Future<Response<List<ScheduledJob>>> _apiJobsGet() {
    final Uri $url = Uri.parse('/api/jobs');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<List<ScheduledJob>, ScheduledJob>($request);
  }

  @override
  Future<Response<dynamic>> _apiJobsPost({required TriggerJobRequest? body}) {
    final Uri $url = Uri.parse('/api/jobs');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _apiJobsDelete({required ScheduledJob? body}) {
    final Uri $url = Uri.parse('/api/jobs');
    final $body = body;
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<List<LiveTvChannelDto>>> _apiLiveTvChannelsGet(
      {String? providerId}) {
    final Uri $url = Uri.parse('/api/live-tv/channels');
    final Map<String, dynamic> $params = <String, dynamic>{
      'providerId': providerId
    };
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<List<LiveTvChannelDto>, LiveTvChannelDto>($request);
  }

  @override
  Future<Response<String>> _apiMegaDebridCallbackPost() {
    final Uri $url = Uri.parse('/api/mega-debrid/callback');
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
    );
    return client.send<String, String>($request);
  }

  @override
  Future<Response<List<IProvider>>> _apiProvidersGet({bool? searchEnabled}) {
    final Uri $url = Uri.parse('/api/providers');
    final Map<String, dynamic> $params = <String, dynamic>{
      'searchEnabled': searchEnabled
    };
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<List<IProvider>, IProvider>($request);
  }

  @override
  Future<Response<List<ISearchFilter>>>
      _apiProvidersProviderIdSearchFiltersGet({
    required String? providerId,
    String? mediaCategory,
  }) {
    final Uri $url = Uri.parse('/api/providers/${providerId}/search-filters');
    final Map<String, dynamic> $params = <String, dynamic>{
      'mediaCategory': mediaCategory
    };
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<List<ISearchFilter>, ISearchFilter>($request);
  }

  @override
  Future<Response<PaginatedResponseOfProviderSearchItemDto>>
      _apiProvidersProviderIdSearchPost({
    required String? providerId,
    required ApiMediaSearchRequest? body,
  }) {
    final Uri $url = Uri.parse('/api/providers/${providerId}/search');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<PaginatedResponseOfProviderSearchItemDto,
        PaginatedResponseOfProviderSearchItemDto>($request);
  }
}
