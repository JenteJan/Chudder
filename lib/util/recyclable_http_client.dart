import 'package:http/http.dart' as http;

/// An [http.Client] whose connection pool can be thrown away.
///
/// After a network drop the pooled keep-alive sockets are dead, but the pool
/// doesn't know: the next request grabs one, writes into the void, and waits
/// out a ~20s OS timeout before anything works again — which is why the app
/// stayed unusable long after the offline banner cleared. Recycling swaps in
/// a fresh inner client (fresh pool) while every ChopperClient holding this
/// wrapper keeps working untouched.
class RecyclableHttpClient extends http.BaseClient {
  http.Client _inner = http.Client();

  /// Replace the inner client, dropping every pooled connection.
  void recycle() {
    final old = _inner;
    _inner = http.Client();
    old.close();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);
}

/// The one instance the Jellyfin (and Seerr) API stacks are built on, so the
/// connectivity layer can recycle it on reconnect.
final recyclableHttpClient = RecyclableHttpClient();
