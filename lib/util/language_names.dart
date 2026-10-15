import 'package:collection/collection.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/util/subtitle_track_selection.dart';

/// A language's everyday name for a code as the preferences keep it (see
/// [normalizeLanguage]), from the server's list of cultures; the code itself,
/// in capitals, while that list is still on its way.
String languageName(String code, List<CultureDto> cultures) {
  if (code.isEmpty) return '';
  final culture = cultures.firstWhereOrNull(
        (c) => c.twoLetterISOLanguageName?.toLowerCase() == code,
      ) ??
      cultures.firstWhereOrNull(
        (c) => normalizeLanguage(c.threeLetterISOLanguageName ?? '') == code,
      );
  return culture == null ? code.toUpperCase() : cultureLabel(culture);
}
