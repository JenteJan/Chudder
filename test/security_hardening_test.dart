import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/screens/shared/media/external_urls.dart';
import 'package:chudder/util/redact_secrets.dart';
import 'package:chudder/widgets/shared/safe_html.dart';

void main() {
  group('redactSecrets', () {
    const token = '0123456789abcdef0123456789abcdef';

    test('masks both Jellyfin auth parameters in a WebSocket failure', () {
      final line = "WebSocket connection failed: WebSocketException: Connection to "
          "'https://jf.example.com:0/socket?api_key=$token&ApiKey=$token&deviceId=abc#' "
          'was not upgraded to websocket';
      final redacted = redactSecrets(line);
      expect(redacted, isNot(contains(token)));
      expect(redacted, contains('api_key=***'));
      expect(redacted, contains('ApiKey=***'));
      // What isn't a secret stays readable.
      expect(redacted, contains('deviceId=abc'));
      expect(redacted, contains('jf.example.com'));
    });

    test('masks the MediaBrowser authorization header', () {
      final redacted = redactSecrets('MediaBrowser Token="$token", Client="Chudder", DeviceId="d1"');
      expect(redacted, isNot(contains(token)));
      expect(redacted, contains('Client="Chudder"'));
    });

    test('masks API key headers, other token parameters and URL passwords', () {
      expect(redactSecrets('X-Api-Key: $token'), isNot(contains(token)));
      expect(redactSecrets('Authorization: Bearer $token'), isNot(contains(token)));
      expect(redactSecrets('/Videos/1/stream?X-Emby-Token=$token'), isNot(contains(token)));
      expect(redactSecrets('http://user:hunter2@nas.local/x'), isNot(contains('hunter2')));
    });

    test('leaves ordinary log lines alone', () {
      const line = 'SyncPlay: group joined, 3 members, position 00:12:34';
      expect(redactSecrets(line), line);
    });
  });

  group('isSafeExternalLink', () {
    test('opens web links', () {
      expect(isSafeExternalLink('https://www.imdb.com/title/tt0111161'), isTrue);
      expect(isSafeExternalLink('http://example.com'), isTrue);
    });

    test('refuses every other scheme', () {
      for (final link in [
        'file:///C:/Windows/System32/calc.exe',
        r'file://attacker/share/x',
        'search-ms:query=x&crumb=location:\\\\attacker\\share',
        'javascript:alert(1)',
        'intent://x#Intent;scheme=x;end',
        'smb://attacker/share',
        'ms-settings:',
        'not a link',
      ]) {
        expect(isSafeExternalLink(link), isFalse, reason: link);
      }
    });
  });

  group('probeAndNormalizeUrl', () {
    Future<String?> Function(String) answers(Set<String> schemes) =>
        (url) async => schemes.contains(Uri.parse(url).scheme) ? url : null;

    test('prefers https', () async {
      final result = await probeAndNormalizeUrl('jf.example.com', answers({'https', 'http'}),
          isHomeNetwork: (_) async => false);
      expect(result.url, startsWith('https://'));
      expect(result.httpOnly, isFalse);
    });

    test('does not silently drop to http for an internet address', () async {
      final result =
          await probeAndNormalizeUrl('jf.example.com', answers({'http'}), isHomeNetwork: (_) async => false);
      expect(result.url, startsWith('https://'));
      expect(result.httpOnly, isTrue);
      expect(result.probed, isFalse);
    });

    test('still uses http on the home network', () async {
      final result =
          await probeAndNormalizeUrl('192.168.1.10:8096', answers({'http'}), isHomeNetwork: (_) async => true);
      expect(result.url, 'http://192.168.1.10:8096');
      expect(result.httpOnly, isFalse);
    });

    test('a typed http:// is respected', () async {
      final result = await probeAndNormalizeUrl('http://jf.example.com', answers({}),
          isHomeNetwork: (_) async => false);
      expect(result.url, 'http://jf.example.com');
      expect(result.httpOnly, isFalse);
    });
  });

  group('isHomeNetworkUrl', () {
    test('Tailscale addresses count as home network', () async {
      expect(await isHomeNetworkUrl('http://100.101.102.103:8096'), isTrue);
      expect(await isHomeNetworkUrl('100.64.0.1'), isTrue);
    });

    test('private and public literals', () async {
      expect(await isHomeNetworkUrl('http://192.168.1.10:8096'), isTrue);
      expect(await isHomeNetworkUrl('http://10.0.0.5'), isTrue);
      expect(await isHomeNetworkUrl('http://8.8.8.8'), isFalse);
      expect(await isHomeNetworkUrl('http://100.200.1.1'), isFalse);
      // Decided from the address alone, which is all a browser has.
      expect(await isHomeNetworkUrl('172.20.0.2:8096'), isTrue);
      expect(await isHomeNetworkUrl('169.254.10.1'), isTrue);
      expect(await isHomeNetworkUrl('172.32.0.1'), isFalse);
    });
  });

  group('SafeHtml', () {
    Future<void> pump(WidgetTester tester, String html) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SafeHtml(html))),
        );

    testWidgets('renders formatting', (tester) async {
      await pump(tester, '<p>A <b>bold</b> overview</p>');
      await tester.pumpAndSettle();
      expect(find.textContaining('bold', findRichText: true), findsOneWidget);
    });

    testWidgets('drops frames, scripts and forms', (tester) async {
      await pump(
        tester,
        'Before<iframe src="javascript:alert(1)">frame text</iframe>'
        '<script>steal()</script><form><input value="pw"></form>'
        '<object data="x.swf">object text</object>After',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Before', findRichText: true), findsOneWidget);
      expect(find.textContaining('After', findRichText: true), findsOneWidget);
      for (final hidden in ['frame text', 'steal', 'object text', 'javascript']) {
        expect(find.textContaining(hidden, findRichText: true), findsNothing, reason: hidden);
      }
    });
  });
}
