import 'package:http/http.dart' as http;

import 'package:chudder/util/pooled_http_client_stub.dart'
    if (dart.library.io) 'package:chudder/util/pooled_http_client_io.dart';

/// An [http.Client] whose connection pool can be thrown away.
///
/// After a network drop the pooled keep-alive sockets are dead, but the pool
/// doesn't know: the next request grabs one, writes into the void, and waits
/// out a ~20s OS timeout before anything works again — which is why the app
/// stayed unusable long after the offline banner cleared. Recycling swaps in
/// a fresh inner client (fresh pool) while every ChopperClient holding this
/// wrapper keeps working untouched.
class RecyclableHttpClient extends http.BaseClient {
  RecyclableHttpClient([http.Client Function() create = createPooledHttpClient]) : _create = create {
    _inner = _create();
  }

  final http.Client Function() _create;
  late http.Client _inner;

  /// Replace the inner client, dropping every pooled connection.
  ///
  /// With [abortInFlight] off the requests already under way are left to
  /// finish on the old client, and only its idle connections go. That is the
  /// one to use when the network is probably still the same - coming back to
  /// the app - where cutting them off failed the very requests the screen
  /// being returned to had just sent.
  void recycle({bool abortInFlight = true}) {
    final Object old = _inner;
    _inner = _create();
    if (!abortInFlight && old is RetirableClient) {
      old.retire();
    } else {
      (old as http.Client).close();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);
}

/// A client that can stop taking part without failing what it has in hand.
abstract interface class RetirableClient {
  /// Closes the idle connections now and each busy one as it finishes.
  void retire();
}

/// The one instance the Jellyfin (and Seerr) API stacks are built on, so the
/// connectivity layer can recycle it on reconnect.
final recyclableHttpClient = RecyclableHttpClient();
