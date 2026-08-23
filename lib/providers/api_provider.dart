import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:punycoder/punycoder.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/local_network_permission.dart';
import 'package:fladder/util/recyclable_http_client.dart';
part 'api_provider.g.dart';

final serverUrlProvider = StateProvider<String?>((ref) {
  final localUrlAvailable = ref.watch(localConnectionAvailableProvider);
  final userCredentials = ref.watch(userProvider.select((value) => value?.credentials));
  final tempUrl = ref.watch(authProvider.select((value) => value.serverLoginModel?.tempCredentials.url));
  String? newUrl;

  if (localUrlAvailable && userCredentials?.localUrl?.isNotEmpty == true) {
    newUrl = userCredentials?.localUrl;
  } else if (userCredentials?.url.isNotEmpty == true) {
    newUrl = userCredentials?.url;
  } else if (tempUrl?.isNotEmpty == true) {
    newUrl = tempUrl;
  } else {
    newUrl = null;
  }

  return normalizeUrl(newUrl ?? "");
});

@riverpod
class JellyApi extends _$JellyApi {
  @override
  JellyService build() => JellyService(
        ref,
        JellyfinOpenApi.create(
          httpClient: recyclableHttpClient,
          interceptors: [
            JellyRequest(ref),
            JellyResponse(ref),
            HttpLoggingInterceptor(level: Level.basic),
          ],
        ),
      );
}

JellyfinOpenApi createJellyfinApiForAccount(Ref ref, String baseUrl, Map<String, String> headers) {
  return JellyfinOpenApi.create(
    httpClient: recyclableHttpClient,
    interceptors: [
      _TempJellyRequest(baseUrl: baseUrl, headers: headers),
      JellyResponse(ref),
      HttpLoggingInterceptor(level: Level.basic),
    ],
  );
}

class _TempJellyRequest implements Interceptor {
  _TempJellyRequest({required this.baseUrl, required this.headers});

  final String baseUrl;
  final Map<String, String> headers;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    if (baseUrl.isEmpty) throw const HttpException('No server URL provided for temp request');

    final request = applyHeaders(chain.request.copyWith(baseUri: Uri.parse(baseUrl)), headers);
    return chain.proceed(request);
  }
}

final int _maxRetries = 3;

bool _isConnectionError(Object e) {
  return e is IOException || e is TimeoutException;
}

class JellyRequest implements Interceptor {
  JellyRequest(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final connectivityNotifier = ref.read(connectivityStatusProvider.notifier);
    // final serverUrl = "https://example.com"; // ref.read(serverUrlProvider); --- IGNORE ---
    final serverUrl = ref.read(serverUrlProvider);

    if (serverUrl == null || serverUrl.isEmpty) {
      throw const HttpException('No server URL provided');
    }

    // Use current logged in user otherwise use the authProvider
    final loginModel = ref.read(userProvider)?.credentials ?? ref.read(authProvider).serverLoginModel?.tempCredentials;
    if (loginModel == null) {
      throw UnimplementedError();
    }

    final headers = loginModel.header(ref);

    // Android 17 drops every LAN socket until the permission is granted, so a
    // server at home answers nothing at all — ask before the first request
    // instead of letting the whole library fail as a connection error. A
    // refusal is final for this address, so say why rather than retrying into
    // three timeouts.
    if (!await LocalNetworkPermission.ensureForUrl(serverUrl)) {
      connectivityNotifier.onStateChange([ConnectivityResult.none]);
      throw const HttpException(
        'Fladder needs local network access to reach a server on this network. '
        'Grant it under Settings → Apps → Fladder → Permissions.',
      );
    }

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final response = await chain.proceed(
          applyHeaders(
            chain.request.copyWith(baseUri: Uri.parse(serverUrl)),
            headers,
          ),
        );

        // Responses do NOT feed the connectivity state. A proxy 502 for a
        // dead backend, an AdGuard block page on mobile DNS, a captive
        // portal - all of them "answer", and every heuristic that tried to
        // tell them apart from Jellyfin here got fooled (seen live: an
        // offline phone flipped back online 116ms after a probe failed,
        // because a DNS block page returned HTTP). Only the strict probe
        // (200 + PublicSystemInfo payload) moves the state.
        return response;
      } catch (e) {
        final isConnectionError = _isConnectionError(e);
        if (!isConnectionError || attempt == _maxRetries) {
          // Only a connection failure is evidence of being offline. Anything
          // else - a parse error, a server error - says nothing about the
          // network, and claiming offline for those left the app stuck there.
          if (isConnectionError) {
            connectivityNotifier.onStateChange([ConnectivityResult.none]);
          }
          rethrow;
        }

        final delay = Duration(milliseconds: 200 * (attempt + 1));
        log('Connection failed (attempt ${attempt + 1}/$_maxRetries), retrying in ${delay.inMilliseconds}ms: $e');
        await Future.delayed(delay);
      }
    }
    throw StateError('Unexpected state in JellyRequest.intercept');
  }
}

/// Whether [url] already carries an http or https scheme.
/// Uses toLowerCase() because users may type mixed-case schemes (e.g. Https://, HTTP://).
bool hasHttpScheme(String url) {
  final lower = url.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

String normalizeUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';

  final withScheme = hasHttpScheme(trimmed) ? trimmed : 'http://$trimmed';
  final parsed = Uri.parse(withScheme);

  // Only punycode non-ASCII hostnames. IP addresses are always ASCII, so no special handling needed.
  final host = parsed.host;
  final hasNonAscii = host.runes.any((c) => c > 0x7F);

  if (!hasNonAscii) return parsed.toString();

  try {
    final encodedHost = const PunycodeCodec().encode(host);
    return parsed.replace(host: encodedHost).toString();
  } catch (_) {
    return parsed.toString();
  }
}

Future<String?> _probeUrl(String baseUrl, String endpoint) async {
  try {
    await LocalNetworkPermission.ensureForUrl(baseUrl);
    await http.head(Uri.parse('$baseUrl$endpoint')).timeout(const Duration(seconds: 5));
    // Any HTTP response (including 4xx/5xx) means the server is reachable at this URL.
    // This only acts as scheme detection, not as health check.
    return baseUrl;
  } catch (e) {
    log('Probe failed for $baseUrl$endpoint: $e');
  }
  return null;
}

/// Probes a Seerr server URL by hitting /api/v1/status.
Future<String?> probeSeerrUrl(String baseUrl) => _probeUrl(baseUrl, '/api/v1/status');

/// Probes a Jellyfin server URL by hitting /System/Info/Public.
Future<String?> probeJellyfinUrl(String baseUrl) => _probeUrl(baseUrl, '/System/Info/Public');

/// Whether JELLYFIN itself answers at [baseUrl] — not merely something at
/// that address. [probeJellyfinUrl] treats any HTTP response as success
/// (it's scheme detection), which meant a reverse proxy's 502 while the
/// server was down read as "online". Offline detection needs the real thing:
/// a 200 from the anonymous /System/Info/Public endpoint.
Future<bool> probeJellyfinReachable(String baseUrl) async {
  try {
    await LocalNetworkPermission.ensureForUrl(baseUrl);
    final response =
        await http.get(Uri.parse('$baseUrl/System/Info/Public')).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return false;
    // A captive portal or DNS block page happily returns 200 HTML for any
    // URL. Only Jellyfin's actual PublicSystemInfo counts.
    final body = jsonDecode(response.body);
    return body is Map && (body.containsKey('Id') || body.containsKey('Version'));
  } catch (e) {
    log('Reachability probe failed for $baseUrl: $e');
    return false;
  }
}

/// Result of [probeAndNormalizeUrl]: the resolved URL and whether a probe succeeded.
typedef ProbeResult = ({String url, bool probed});

/// Tries https and http in parallel using [probeFn] if no scheme is provided.
/// Always returns a usable URL (falls back to https when both probes fail).
/// If a scheme is already present, returns the normalized URL without probing.
Future<ProbeResult> probeAndNormalizeUrl(String url, Future<String?> Function(String) probeFn) async {
  if (!hasHttpScheme(url)) {
    final httpsUrl = normalizeUrl('https://$url');
    final httpUrl = normalizeUrl('http://$url');
    final httpFuture = probeFn(httpUrl);
    final httpsResult = await probeFn(httpsUrl);
    if (httpsResult != null) return (url: httpsResult, probed: true);
    final httpResult = await httpFuture;
    return (url: httpResult ?? httpsUrl, probed: httpResult != null);
  }
  return (url: normalizeUrl(url), probed: true);
}

Uri? tryParseServerBaseUri(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || parsed.scheme.isEmpty || parsed.host.isEmpty) return null;
  return parsed;
}

Uri? serverBaseUri(Ref ref) => tryParseServerBaseUri(ref.read(serverUrlProvider));

Uri? buildServerUriFromBase(
  String baseUrl, {
  List<String> pathSegments = const [],
  String? relativeUrl,
  Map<String, String?>? queryParameters,
}) {
  final base = tryParseServerBaseUri(baseUrl);
  if (base == null) return null;

  Uri? relative;
  if (relativeUrl != null && relativeUrl.trim().isNotEmpty) {
    relative = Uri.tryParse(relativeUrl.trim());
  }

  if (relative?.hasScheme == true && relative?.host.isNotEmpty == true) {
    return relative;
  }

  final baseSegments = base.pathSegments.where((s) => s.isNotEmpty).toList(growable: false);
  final relSegments = (relative?.pathSegments ?? const <String>[]).where((s) => s.isNotEmpty).toList(growable: false);
  final extraSegments = pathSegments.where((s) => s.isNotEmpty).toList(growable: false);

  final mergedSegments = <String>[...baseSegments, ...relSegments, ...extraSegments];

  final mergedQuery = <String, String>{...?(relative?.queryParameters)};
  if (queryParameters != null) {
    for (final entry in queryParameters.entries) {
      final value = entry.value;
      if (value == null) continue;
      mergedQuery[entry.key] = value;
    }
  }

  return Uri(
    scheme: base.scheme,
    userInfo: base.userInfo,
    host: base.host,
    port: base.hasPort ? base.port : null,
    pathSegments: mergedSegments,
    queryParameters: mergedQuery.isNotEmpty ? mergedQuery : null,
    fragment: relative?.hasFragment == true ? relative!.fragment : null,
  );
}

Uri? buildServerUri(
  Ref ref, {
  List<String> pathSegments = const [],
  String? relativeUrl,
  Map<String, String?>? queryParameters,
}) {
  final baseUrl = ref.read(serverUrlProvider);
  if (baseUrl == null || baseUrl.isEmpty) return null;
  return buildServerUriFromBase(
    baseUrl,
    pathSegments: pathSegments,
    relativeUrl: relativeUrl,
    queryParameters: queryParameters,
  );
}

String buildServerUrl(
  Ref ref, {
  List<String> pathSegments = const [],
  String? relativeUrl,
  Map<String, String?>? queryParameters,
}) {
  return buildServerUri(
        ref,
        pathSegments: pathSegments,
        relativeUrl: relativeUrl,
        queryParameters: queryParameters,
      )?.toString() ??
      '';
}

/// Query parameters that authenticate a media URL against any supported
/// server version.
///
/// Jellyfin 12 defaults `EnableLegacyAuthorization` to false, retiring the
/// Emby-inherited `api_key` parameter in favour of `ApiKey`. The two names
/// differ by more than case, so neither binds the other — emit both and a
/// single build authenticates against pre-12 and 12+ servers alike. The
/// server ignores whichever name it does not recognise.
///
/// Only for URLs handed to an external consumer that cannot set headers:
/// the video player, a download manager, the OS. Anything going through the
/// API client authenticates with the `Authorization` header instead.
Map<String, String?> authQueryParameters(String? token) => {
      'api_key': token,
      'ApiKey': token,
    };

class JellyResponse implements Interceptor {
  JellyResponse(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final Response<BodyType> response = await chain.proceed(chain.request);

    if (!response.isSuccessful) {
      log('x- ${response.base.statusCode} - ${response.base.reasonPhrase} - ${response.error} - ${response.base.request?.method} ${response.base.request?.url.toString()}');
    }
    if (response.statusCode == 404) {
      chopperLogger.severe('404 NOT FOUND');
    }

    return response;
  }
}
