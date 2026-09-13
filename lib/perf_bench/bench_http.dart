import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

/// One request as the output reports it. Times are microseconds on the
/// monotonic clock ([Timeline.now]).
class BenchRequest {
  BenchRequest(this.method, this.path, this.startUs, {this.rewrittenFrom});

  final String method;
  final String path;
  final int startUs;
  final String? rewrittenFrom;
  int? headersUs;
  int? endUs;
  int? status;
  int bytes = 0;
  String? error;
  bool websocket = false;

  bool get inFlight => endUs == null;
}

/// Counts every request that goes through `dart:io`'s [HttpClient] - which is
/// what `package:http`'s IOClient, chopper, flutter_cache_manager,
/// extended_image and `WebSocket.connect` all use on Windows. The players
/// fetch their streams natively and are not seen here.
class BenchHttpTracker {
  final List<BenchRequest> requests = [];
  int lastEventUs = 0;

  int get inFlight {
    var count = 0;
    for (final r in requests) {
      if (r.inFlight) count++;
    }
    return count;
  }

  BenchRequest start(String method, Uri url, {String? rewrittenFrom}) {
    final now = Timeline.now;
    lastEventUs = now;
    final request = BenchRequest(method, sanitizePath(url), now, rewrittenFrom: rewrittenFrom);
    requests.add(request);
    return request;
  }

  void finish(BenchRequest request, {String? error}) {
    if (request.endUs != null) return;
    final now = Timeline.now;
    request.endUs = now;
    request.error ??= error;
    lastEventUs = now;
  }

  static const _secretParams = {'apikey', 'api_key', 'x-emby-token', 'token', 'accesstoken', 'x-mediabrowser-token'};

  /// The path and query, without the host and without anything that
  /// authenticates.
  static String sanitizePath(Uri url) {
    final query = url.queryParametersAll.entries
        .where((e) => !_secretParams.contains(e.key.toLowerCase()))
        .expand((e) => e.value.map((v) => '${e.key}=$v'))
        .join('&');
    final text = query.isEmpty ? url.path : '${url.path}?$query';
    return text.length > 300 ? '${text.substring(0, 300)}...' : text;
  }
}

class BenchHttpOverrides extends HttpOverrides {
  BenchHttpOverrides(this.tracker, List<Map<String, dynamic>> rewrites, {this.proxy})
      : _rewrites = [
          for (final r in rewrites)
            (
              method: (r['method'] as String?)?.toUpperCase(),
              pattern: RegExp(r['path_regex'] as String),
              to: r['to'] as String,
            ),
        ];

  final BenchHttpTracker tracker;
  final List<({String? method, RegExp pattern, String to})> _rewrites;

  /// `host:port` of the latency proxy, or null for direct connections.
  final String? proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = super.createHttpClient(context);
    if (proxy != null) inner.connectionFactory = (url, proxyHost, proxyPort) => _throughLatencyProxy(url, context);
    return _BenchHttpClient(inner, this);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      proxy == null ? super.findProxyFromEnvironment(url, environment) : 'DIRECT';

  /// A connection to [url] through the latency proxy (tool/perf/latency_proxy.py).
  ///
  /// Not an HTTP proxy as far as HttpClient knows: dart:io files a tunnel it
  /// made through a proxy under the server's address but looks for idle ones
  /// under the proxy's, so it would never reuse a connection and every request
  /// would pay a new TCP and TLS handshake. Here the client dials the proxy
  /// itself, names the destination in a one-line preamble the proxy answers
  /// with nothing, and does TLS with the server over it - and HttpClient pools
  /// the connection under the server's address as it would a direct one.
  Future<ConnectionTask<Socket>> _throughLatencyProxy(Uri url, SecurityContext? context) async {
    final separator = proxy!.lastIndexOf(':');
    final task = await Socket.startConnect(proxy!.substring(0, separator), int.parse(proxy!.substring(separator + 1)));
    final socket = task.socket.then((socket) async {
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(utf8.encode('TUNNEL ${url.host}:${url.port}\r\n\r\n'));
      await socket.flush();
      if (!url.isScheme('https') && !url.isScheme('wss')) return socket;
      return SecureSocket.secure(socket, host: url.host, context: context);
    });
    return ConnectionTask.fromSocket(socket, task.cancel);
  }

  (Uri, String?) rewrite(String method, Uri url) {
    for (final r in _rewrites) {
      if ((r.method == null || r.method == method.toUpperCase()) && r.pattern.hasMatch(url.path)) {
        return (url.replace(path: r.to, query: ''), BenchHttpTracker.sanitizePath(url));
      }
    }
    return (url, null);
  }
}

class _BenchHttpClient implements HttpClient {
  _BenchHttpClient(this._inner, this._overrides);

  final HttpClient _inner;
  final BenchHttpOverrides _overrides;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final (target, rewrittenFrom) = _overrides.rewrite(method, url);
    final record = _overrides.tracker.start(method, target, rewrittenFrom: rewrittenFrom);
    try {
      final request = await _inner.openUrl(method, target);
      return _BenchHttpClientRequest(request, record, _overrides.tracker);
    } catch (e) {
      _overrides.tracker.finish(record, error: e.runtimeType.toString());
      rethrow;
    }
  }

  Uri _uri(String host, int port, String path) {
    final query = path.indexOf('?');
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: query < 0 ? path : path.substring(0, query),
      query: query < 0 ? null : path.substring(query + 1),
    );
  }

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      openUrl(method, _uri(host, port, path));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => open('GET', host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) => open('POST', host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) => open('HEAD', host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) => _inner.authenticate = f;
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);
  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) {
    // The latency proxy is the only way out while it is on.
    if (_overrides.proxy == null) _inner.connectionFactory = f;
  }
  @override
  set findProxy(String Function(Uri url)? f) {
    // The latency proxy is the only way out while it is on.
    if (_overrides.proxy == null) _inner.findProxy = f;
  }
  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) =>
      _inner.authenticateProxy = f;
  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) =>
      _inner.badCertificateCallback = callback;
  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}

class _BenchHttpClientRequest implements HttpClientRequest {
  _BenchHttpClientRequest(this._inner, this._record, this._tracker);

  final HttpClientRequest _inner;
  final BenchRequest _record;
  final BenchHttpTracker _tracker;
  Future<HttpClientResponse>? _wrapped;

  Future<HttpClientResponse> _wrap(Future<HttpClientResponse> response) => _wrapped ??= response.then(
        (value) => _BenchHttpClientResponse.wrap(value, _record, _tracker),
        onError: (Object e, StackTrace s) {
          _tracker.finish(_record, error: e.runtimeType.toString());
          return Future<HttpClientResponse>.error(e, s);
        },
      );

  @override
  Future<HttpClientResponse> close() {
    if (_inner.headers.value(HttpHeaders.upgradeHeader)?.toLowerCase() == 'websocket') _record.websocket = true;
    return _wrap(_inner.close());
  }

  @override
  Future<HttpClientResponse> get done => _wrap(_inner.done);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _tracker.finish(_record, error: 'aborted');
    _inner.abort(exception, stackTrace);
  }

  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;
  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool value) => _inner.followRedirects = value;
  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;
  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int value) => _inner.contentLength = value;
  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;
  @override
  String get method => _inner.method;
  @override
  Uri get uri => _inner.uri;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;
  @override
  void add(List<int> data) => _inner.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _inner.addError(error, stackTrace);
  @override
  Future addStream(Stream<List<int>> stream) => _inner.addStream(stream);
  @override
  Future flush() => _inner.flush();
  @override
  void write(Object? object) => _inner.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) => _inner.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _inner.writeln(object);
}

class _BenchHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  _BenchHttpClientResponse._(this._inner, this._record, this._tracker);

  static HttpClientResponse wrap(HttpClientResponse inner, BenchRequest record, BenchHttpTracker tracker) {
    record.headersUs ??= Timeline.now;
    record.status = inner.statusCode;
    final wrapped = _BenchHttpClientResponse._(inner, record, tracker);
    // Nothing will come after the headers: no body to wait for.
    if (inner.contentLength == 0 || record.method == 'HEAD' || inner.statusCode == 204 || inner.statusCode == 304) {
      tracker.finish(record);
    } else {
      // A body nobody reads is not something anyone is waiting for: the image
      // cache, for one, gives up on a 404 without draining it. Consumers that
      // do read start within a few microtasks.
      Timer(const Duration(milliseconds: 300), () {
        if (!wrapped._listened) tracker.finish(record, error: 'body not read');
      });
    }
    return wrapped;
  }

  final HttpClientResponse _inner;
  final BenchRequest _record;
  final BenchHttpTracker _tracker;
  bool _listened = false;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    _listened = true;
    final subscription = _TrackedSubscription(_inner.listen(null, cancelOnError: cancelOnError), _record, _tracker,
        cancelOnError: cancelOnError == true);
    subscription.onData(onData);
    subscription.onError(onError);
    subscription.onDone(onDone);
    return subscription;
  }

  @override
  Future<Socket> detachSocket() {
    _record.websocket = true;
    _tracker.finish(_record);
    return _inner.detachSocket();
  }

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) async {
    final next = await _inner.redirect(method, url, followLoops);
    return next;
  }

  @override
  int get statusCode => _inner.statusCode;
  @override
  String get reasonPhrase => _inner.reasonPhrase;
  @override
  int get contentLength => _inner.contentLength;
  @override
  HttpClientResponseCompressionState get compressionState => _inner.compressionState;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  bool get isRedirect => _inner.isRedirect;
  @override
  List<RedirectInfo> get redirects => _inner.redirects;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  X509Certificate? get certificate => _inner.certificate;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
}

/// Keeps counting bytes and noticing the end however the consumer installs
/// its handlers - `asFuture`, `drain` and `http`'s own stream plumbing replace
/// them after `listen`.
class _TrackedSubscription implements StreamSubscription<List<int>> {
  _TrackedSubscription(this._inner, this._record, this._tracker, {required this.cancelOnError});

  final StreamSubscription<List<int>> _inner;
  final BenchRequest _record;
  final BenchHttpTracker _tracker;
  final bool cancelOnError;

  @override
  Future<void> cancel() {
    _tracker.finish(_record, error: 'cancelled');
    return _inner.cancel();
  }

  @override
  void onData(void Function(List<int> data)? handleData) => _inner.onData((data) {
        _record.bytes += data.length;
        handleData?.call(data);
      });

  @override
  void onError(Function? handleError) => _inner.onError((Object error, StackTrace stack) {
        if (cancelOnError) _tracker.finish(_record, error: error.runtimeType.toString());
        if (handleError is void Function(Object, StackTrace)) {
          handleError(error, stack);
        } else if (handleError is void Function(Object)) {
          handleError(error);
        } else {
          Zone.current.handleUncaughtError(error, stack);
        }
      });

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(() {
        _tracker.finish(_record);
        handleDone?.call();
      });

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);
  @override
  void resume() => _inner.resume();
  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    final completer = Completer<E>();
    onDone(() => completer.complete(futureValue as E));
    onError((Object error, StackTrace stack) {
      cancel();
      completer.completeError(error, stack);
    });
    return completer.future;
  }
}
