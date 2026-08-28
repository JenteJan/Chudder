import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/battery_optimization_pigeon.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/app/src/main/kotlin/uk/jentejan/chudder/api/BatteryOptimizationPigeon.g.kt',
    kotlinOptions: KotlinOptions(
      includeErrorClass: false,
    ),
    dartPackageName: 'uk_jentejan_chudder.settings',
  ),
)
@HostApi()
abstract class BatteryOptimizationPigeon {
  bool isIgnoringBatteryOptimizations();

  void openBatteryOptimizationSettings();
}
