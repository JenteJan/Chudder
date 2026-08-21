import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/util/list_extensions.dart';

void main() {
  test('mapConcurrent keeps results in order', () async {
    final result = await [1, 2, 3, 4, 5, 6, 7].mapConcurrent(3, (value) async {
      await Future.delayed(Duration(milliseconds: (8 - value) * 5));
      return value * 2;
    });
    expect(result, [2, 4, 6, 8, 10, 12, 14]);
  });

  test('mapConcurrent never runs more than the limit at once', () async {
    var running = 0;
    var peak = 0;
    final completers = <Completer<void>>[];

    final work = List.generate(20, (index) => index).mapConcurrent(4, (value) async {
      running++;
      peak = peak > running ? peak : running;
      final completer = Completer<void>();
      completers.add(completer);
      await completer.future;
      running--;
      return value;
    });

    // Let the first batch start, then release everything a step at a time.
    for (var released = 0; released < 20; released++) {
      await Future.delayed(Duration.zero);
      completers[released].complete();
    }

    expect(await work, List.generate(20, (index) => index));
    expect(peak, 4);
  });

  test('mapConcurrent handles an empty list', () async {
    expect(await <int>[].mapConcurrent(4, (value) async => value), isEmpty);
  });
}
