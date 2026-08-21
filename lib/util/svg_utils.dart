import 'package:flutter_svg/flutter_svg.dart';

class SvgUtils {
  static List<String> allSvgs = [
    'icons/chudder_icon.svg',
    'icons/chudder_icon_outline.svg',
    'icons/tomato.svg',
    'icons/popcorn_bucket.svg'
  ];

  static Future<void> preCacheSVGs() async {
    try {
      for (final path in allSvgs) {
        final loadSvg = SvgAssetLoader(path);
        await svg.cache.putIfAbsent(
          loadSvg.cacheKey(null),
          () => loadSvg.loadBytes(null),
        );
      }
    } catch (e) {
      print(e);
    }
  }
}
