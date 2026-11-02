// Random group histories on a virtual clock, judged by what must hold once
// things go quiet. A short run is part of the suite; for a long one:
//   flutter test test/syncplay_sim/syncplay_fuzz_test.dart --dart-define=FUZZ_RUNS=20000 --dart-define=FUZZ_FROM=1
// and --dart-define=FUZZ_PAIRS=true for every pair of steps in turn (FUZZ_FROM up to pairCount),
// --dart-define=FUZZ_STOPS=true for every pair with a group Stop in it (up to stopCount).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/wrappers/media_control_wrapper.dart';

import 'sim_scenarios.dart';

const runs = int.fromEnvironment('FUZZ_RUNS', defaultValue: 40);
const pairs = bool.fromEnvironment('FUZZ_PAIRS');
const stops = bool.fromEnvironment('FUZZ_STOPS');
const from = int.fromEnvironment('FUZZ_FROM', defaultValue: 1);
const report = String.fromEnvironment('FUZZ_REPORT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  MediaControlsWrapper.useSystemMediaSession = false;

  test('group histories settle', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );

    final kinds = <String, int>{};
    final examples = <String, Outcome>{};
    final clockTimer = Stopwatch()..start();
    var virtual = 0;
    for (var seed = from; seed < from + runs; seed++) {
      final scenario = stops ? stopScenario(seed) : (pairs ? pairScenario(seed) : Scenario.random(seed));
      final outcome = runScenario(scenario, prefs);
      virtual += outcome.virtualMs;
      for (final problem in outcome.problems) {
        final kind = problem.split(':').first;
        kinds[kind] = (kinds[kind] ?? 0) + 1;
      }
      if (outcome.failed) examples.putIfAbsent(outcome.problems.first.split(':').first, () => outcome);
    }
    final out = StringBuffer()
      ..writeln('$runs runs in ${clockTimer.elapsed}, ${virtual ~/ 60000} virtual minutes')
      ..writeln('problems: $kinds');
    for (final example in examples.entries) {
      final small = shrink(example.value, prefs);
      out
        ..writeln('--- ${example.key}: ${small.problems}')
        ..writeln(small.scenario)
        ..writeln(small.trace.join('\n'));
    }
    // ignore: avoid_print
    print(out.toString().split('\n').take(4).join('\n'));
    if (report.isNotEmpty) File(report).writeAsStringSync(out.toString());
    expect(kinds, isEmpty, reason: out.toString());
  }, timeout: const Timeout(Duration(hours: 6)));
}
