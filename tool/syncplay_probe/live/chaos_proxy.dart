// A bad network in a box: a local reverse proxy between one member and a real
// server, for both HTTP and the websocket. Each direction is delayed with
// jitter, requests can pass each other, and the socket can be cut.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class ChaosProxy {
  ChaosProxy(this.upstream, {this.baseMs = 0, this.jitterMs = 0, int seed = 1}) : _random = Random(seed);

  final String upstream;
  int baseMs;
  int jitterMs;
  final Random _random;
  late HttpServer _server;
  final _client = HttpClient();
  final _sockets = <WebSocket>[];
  bool down = false;
  int requests = 0;
  int framesDropped = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  Duration get _delay => Duration(milliseconds: baseMs + (jitterMs == 0 ? 0 : _random.nextInt(jitterMs)));

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        unawaited(_socket(request));
      } else {
        unawaited(_forward(request));
      }
    });
  }

  Future<void> _forward(HttpRequest request) async {
    requests++;
    final body = await request.fold<List<int>>([], (all, part) => all..addAll(part));
    await Future<void>.delayed(_delay);
    if (down) {
      request.response.statusCode = 503;
      await request.response.close();
      return;
    }
    try {
      final out = await _client.openUrl(request.method, Uri.parse('$upstream${request.uri}'));
      request.headers.forEach((name, values) {
        if (name != 'host' && name != 'content-length') {
          for (final v in values) {
            out.headers.add(name, v);
          }
        }
      });
      out.contentLength = body.length;
      out.add(body);
      final answer = await out.close();
      final bytes = await answer.fold<List<int>>([], (all, part) => all..addAll(part));
      await Future<void>.delayed(_delay);
      request.response.statusCode = answer.statusCode;
      answer.headers.contentType?.let((t) => request.response.headers.contentType = t);
      request.response.add(bytes);
      await request.response.close();
    } catch (_) {
      request.response.statusCode = 502;
      await request.response.close();
    }
  }

  Future<void> _socket(HttpRequest request) async {
    if (down) {
      request.response.statusCode = 503;
      await request.response.close();
      return;
    }
    final client = await WebSocketTransformer.upgrade(request);
    final target = upstream.replaceFirst('https://', 'wss://');
    final server = await WebSocket.connect('$target${request.uri}');
    _sockets.addAll([client, server]);

    // Each direction stays in order, as on one TCP connection.
    void pipe(WebSocket from, WebSocket to) {
      var last = DateTime.now();
      from.listen((data) {
        var at = DateTime.now().add(_delay);
        if (at.isBefore(last)) at = last;
        last = at;
        Timer(at.difference(DateTime.now()), () {
          if (to.readyState == WebSocket.open) {
            to.add(data);
          } else {
            framesDropped++;
          }
        });
      }, onDone: () {
        if (to.readyState == WebSocket.open) to.close();
      }, onError: (_) {}, cancelOnError: true);
    }

    pipe(client, server);
    pipe(server, client);
  }

  /// Cut every socket and refuse new ones for [length].
  Future<void> cut(Duration length) async {
    down = true;
    for (final s in _sockets) {
      unawaited(s.close(WebSocketStatus.goingAway));
    }
    _sockets.clear();
    Timer(length, () => down = false);
  }

  Future<void> stop() async {
    await _server.close(force: true);
    _client.close(force: true);
  }

  // ignore: unused_element
  static String describe(Object o) => json.encode(o);
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
