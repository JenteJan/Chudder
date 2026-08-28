import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/wallpaper_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/uk/jentejan/chudder/wallpaper/WallpaperApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'uk.jentejan.chudder.wallpaper',
      includeErrorClass: false,
    ),
    dartPackageName: 'uk_jentejan_chudder.wallpaper',
  ),
)
@HostApi()
abstract class WallpaperApi {
  @async
  bool openWallpaperPopup(String filePath);
}
