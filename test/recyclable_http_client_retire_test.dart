import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/recyclable_http_client.dart';

void main() {
  late HttpServer server;
  late Completer<void> release;

  setUp(() async {
    release = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      // Holds the answer back until the test lets go, so the request is
      // still under way when the pool is recycled.
      if (request.uri.path == '/slow') await release.future;
      request.response
        ..write('ok')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('retiring the pool lets a request under way finish', () async {
    final client = RecyclableHttpClient();
    addTearDown(client.recycle);

    final slow = client.get(url('/slow'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    client.recycle(abortInFlight: false);
    release.complete();

    expect((await slow).body, 'ok');
    expect((await client.get(url('/fast'))).body, 'ok');
  });

  test('recycling the pool cuts a request under way off', () async {
    final client = RecyclableHttpClient();
    addTearDown(client.recycle);

    final slow = client.get(url('/slow'));
    // Listened to before the cut, so the failure is not an unhandled one.
    final outcome = expectLater(slow, throwsA(anything));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    client.recycle();

    await outcome;
    release.complete();
  });
}
