import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';

part 'jellybot_search_state.freezed.dart';

@Freezed(copyWith: true)
abstract class JellybotSearchState with _$JellybotSearchState {
  const JellybotSearchState._();

  const factory JellybotSearchState({
    @Default('') String query,
    @Default(MediaCategory.movie) MediaCategory category,
    IProvider? provider,
    @Default(<String, String>{}) Map<String, String> selectedFilters,
    @Default(false) bool exactMatch,
    double? minScore,
    @Default(0) int page,
    @Default(20) int pageSize,
  }) = _JellybotSearchState;

  int get activeFilterCount =>
      selectedFilters.length + (exactMatch ? 1 : 0) + (minScore != null ? 1 : 0);

  ApiMediaSearchRequest toRequest() {
    return ApiMediaSearchRequest(
      query: query,
      category: category,
      exactMatch: exactMatch,
      minScore: minScore,
      page: page,
      pageSize: pageSize,
      filters: selectedFilters.entries
          .map((e) => SearchFilter(name: e.key, $value: e.value))
          .toList(),
    );
  }
}
