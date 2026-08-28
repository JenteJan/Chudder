import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/application_menu.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'macos/Runner/ApplicationMenu.g.swift',
    swiftOptions: SwiftOptions(
      includeErrorClass: false,
    ),
    dartPackageName: 'uk_jentejan_chudder.application_menu',
  ),
)
@FlutterApi()
abstract class ApplicationMenu {
  void openNewWindow();
  void newInstance();
}
