import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// How long a finished connection waits in the pool for the next request.
///
/// dart:io's default is 15 seconds, so a poster looked at for a quarter of a
/// minute before it was opened paid for every connection again: a TCP and a
/// TLS handshake per parallel request (the page, its extras and each picture),
/// two round trips apiece away from home. Browsers and OkHttp keep idle
/// connections for minutes; a minute stays under the idle timeouts of the
/// usual reverse proxies (nginx 75s, Kestrel 130s), so the server is not the
/// one closing them mid-request. Dead routes after a network change are still
/// handled by [RecyclableHttpClient.recycle].
const pooledConnectionIdleTimeout = Duration(seconds: 60);

HttpClient createPooledIoHttpClient() => HttpClient()..idleTimeout = pooledConnectionIdleTimeout;

http.Client createPooledHttpClient() => IOClient(createPooledIoHttpClient());
