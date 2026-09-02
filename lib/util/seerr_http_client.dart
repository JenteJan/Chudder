import 'package:http/http.dart' as http;

import 'package:fladder/util/recyclable_http_client.dart';

/// The same pool the Jellyfin stack uses. This provider is rebuilt whenever
/// the Seerr credentials change, and each rebuild used to open a fresh pool
/// without closing the old one - sockets kept alive for nobody.
http.Client createSeerrHttpClient() => recyclableHttpClient;
