import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/perf_bench/bench_http.dart';
import 'package:chudder/perf_bench/loading_indicators.dart';

class Placeholder2 extends StatelessWidget {
  const Placeholder2({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 40, height: 40);
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('visibleLoadingIndicators', () {
    testWidgets('sees a spinner on screen', (tester) async {
      await tester.pumpWidget(_app(const Center(child: CircularProgressIndicator())));
      expect(visibleLoadingIndicators(const {}), ['CircularProgressIndicator']);
    });

    testWidgets('ignores a determinate progress bar', (tester) async {
      await tester.pumpWidget(_app(const Center(child: LinearProgressIndicator(value: 0.4))));
      expect(visibleLoadingIndicators(const {}), isEmpty);
    });

    testWidgets('ignores spinners that are offstage, transparent, or on a hidden tab', (tester) async {
      await tester.pumpWidget(_app(const Column(
        children: [
          Offstage(child: CircularProgressIndicator()),
          Opacity(opacity: 0, child: CircularProgressIndicator()),
          SizedBox(
            height: 50,
            child: IndexedStack(index: 0, children: [SizedBox(), CircularProgressIndicator()]),
          ),
        ],
      )));
      expect(visibleLoadingIndicators(const {}), isEmpty);
    });

    testWidgets('ignores a spinner scrolled out of view', (tester) async {
      await tester.pumpWidget(_app(ListView(
        children: const [SizedBox(height: 5000), CircularProgressIndicator()],
      )));
      expect(visibleLoadingIndicators(const {}), isEmpty);
    });

    testWidgets('sees placeholders named in the config', (tester) async {
      await tester.pumpWidget(_app(const Center(child: Placeholder2())));
      expect(visibleLoadingIndicators(const {'Placeholder2'}), ['Placeholder2']);
      expect(visibleLoadingIndicators(const {}), isEmpty);
    });
  });

  test('request paths lose the host and anything that authenticates', () {
    final url = Uri.parse('https://example.invalid/Items/1/Images/Primary?tag=abc&ApiKey=secret&api_key=x&fillWidth=500');
    expect(BenchHttpTracker.sanitizePath(url), '/Items/1/Images/Primary?tag=abc&fillWidth=500');
  });
}
