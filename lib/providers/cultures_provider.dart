import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/api_provider.dart';

part 'cultures_provider.g.dart';

@riverpod
class Cultures extends _$Cultures {
  @override
  List<CultureDto> build() {
    _fetch();
    return const [];
  }

  Future<void> _fetch() async {
    // Offline the language lists stay empty until the page is opened again;
    // the failure used to surface as an unhandled error from the settings
    // page instead.
    try {
      final api = ref.read(jellyApiProvider);
      final response = await api.localizationCulturesGet();
      final cultures = response.body;
      if (cultures != null) {
        state = cultures;
      }
    } catch (_) {}
  }
}
