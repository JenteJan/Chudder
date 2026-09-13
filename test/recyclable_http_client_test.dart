import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chudder/util/pooled_http_client_io.dart';
import 'package:chudder/util/recyclable_http_client.dart';

void main() {
  late HttpServer server;
  late Set<int> clientPorts;

  setUp(() async {
    clientPorts = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      clientPorts.add(request.connectionInfo!.remotePort);
      request.response
        ..write('ok')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri url() => Uri.parse('http://127.0.0.1:${server.port}/System/Info/Public');

  test('idle connections outlive dart:io\'s 15 second default', () {
    final client = createPooledIoHttpClient();
    addTearDown(() => client.close(force: true));
    expect(client.idleTimeout, const Duration(minutes: 1));
  });

  test('requests one after another share one connection', () async {
    final client = RecyclableHttpClient();
    addTearDown(client.recycle);

    for (var i = 0; i < 3; i++) {
      final response = await client.get(url());
      expect(response.body, 'ok');
    }
    expect(clientPorts, hasLength(1));
  });

  test('recycling drops the pooled connection and the wrapper keeps working', () async {
    final client = RecyclableHttpClient();
    addTearDown(client.recycle);

    await client.get(url());
    client.recycle();
    final response = await client.get(url());

    expect(response.statusCode, 200);
    expect(clientPorts, hasLength(2));
  });

  test('a custom factory is used for the first client and every recycle', () async {
    var created = 0;
    final client = RecyclableHttpClient(() {
      created++;
      return http.Client();
    });
    expect(created, 1);
    client.recycle();
    expect(created, 2);
    client.recycle();
  });
}
