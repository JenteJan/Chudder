import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/display_refresh_rate.dart';

void main() {
  /// A phone with a 60 and a 120 mode, as a Pixel reports them.
  List<DisplayRate> phone({required int at}) => [
        DisplayRate(id: 1, refreshRate: 60, current: at == 60),
        DisplayRate(id: 2, refreshRate: 120.00001, current: at == 120),
      ];

  test('a film on a screen at 60 asks for 120', () {
    expect(rateForVideo(24, phone(at: 60)), 2);
    expect(rateForVideo(23.976, phone(at: 60)), 2);
  });

  test('a video the screen already divides evenly leaves it alone', () {
    expect(rateForVideo(30, phone(at: 60)), isNull);
    expect(rateForVideo(29.97, phone(at: 60)), isNull);
    expect(rateForVideo(60, phone(at: 60)), isNull);
    expect(rateForVideo(59.94, phone(at: 60)), isNull);
    expect(rateForVideo(24, phone(at: 120)), isNull);
    expect(rateForVideo(23.976, phone(at: 120)), isNull);
  });

  test('a rate that goes into nothing gets the fastest, where the uneven step is shortest', () {
    expect(rateForVideo(25, phone(at: 60)), 2);
    expect(rateForVideo(50, phone(at: 60)), 2);
    expect(rateForVideo(25, phone(at: 120)), isNull);
  });

  test('the lowest even rate that is not slower than now', () {
    const rates = [
      DisplayRate(id: 1, refreshRate: 48),
      DisplayRate(id: 2, refreshRate: 60, current: true),
      DisplayRate(id: 3, refreshRate: 72),
      DisplayRate(id: 4, refreshRate: 120),
    ];
    expect(rateForVideo(24, rates), 3);
  });

  test('a slower even rate when there is no faster one', () {
    const rates = [
      DisplayRate(id: 1, refreshRate: 50),
      DisplayRate(id: 2, refreshRate: 60, current: true),
    ];
    expect(rateForVideo(25, rates), 1);
  });

  test('a screen with one rate, or a video with none, is left alone', () {
    expect(rateForVideo(24, const [DisplayRate(id: 1, refreshRate: 60, current: true)]), isNull);
    expect(rateForVideo(24, const []), isNull);
    expect(rateForVideo(0, phone(at: 60)), isNull);
    expect(rateForVideo(double.nan, phone(at: 60)), isNull);
    expect(rateForVideo(24, const [DisplayRate(id: 1, refreshRate: 60), DisplayRate(id: 2, refreshRate: 120)]), isNull);
  });

  test('a still picture - a cover in a music file - changes nothing', () {
    expect(rateForVideo(1, phone(at: 60)), isNull);
  });
}
