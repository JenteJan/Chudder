import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/api_result.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';

/// State of one remote subtitle search: the server asks whichever subtitle
/// provider plugins it has installed (OpenSubtitles, Subdl, ...) and lists
/// what they return for [language].
class SubtitleSearchModel {
  /// Three-letter ISO 639-2 code, the form the server's providers expect.
  final String language;
  final bool perfectMatch;
  final List<RemoteSubtitleInfo> results;
  final bool searched;
  final bool processing;

  /// Id of the result being downloaded right now, if any.
  final String? downloadingId;
  final String? error;

  const SubtitleSearchModel({
    this.language = 'eng',
    this.perfectMatch = false,
    this.results = const [],
    this.searched = false,
    this.processing = false,
    this.downloadingId,
    this.error,
  });

  SubtitleSearchModel copyWith({
    String? language,
    bool? perfectMatch,
    List<RemoteSubtitleInfo>? results,
    bool? searched,
    bool? processing,
    ValueGetter<String?>? downloadingId,
    ValueGetter<String?>? error,
  }) {
    return SubtitleSearchModel(
      language: language ?? this.language,
      perfectMatch: perfectMatch ?? this.perfectMatch,
      results: results ?? this.results,
      searched: searched ?? this.searched,
      processing: processing ?? this.processing,
      downloadingId: downloadingId != null ? downloadingId() : this.downloadingId,
      error: error != null ? error() : this.error,
    );
  }
}

final subtitleSearchProvider =
    StateNotifierProvider.autoDispose.family<SubtitleSearchNotifier, SubtitleSearchModel, String>(
  (ref, itemId) => SubtitleSearchNotifier(ref, itemId),
);

class SubtitleSearchNotifier extends StateNotifier<SubtitleSearchModel> {
  SubtitleSearchNotifier(this.ref, this.itemId) : super(const SubtitleSearchModel());

  final Ref ref;
  final String itemId;

  late final JellyService api = ref.read(jellyApiProvider);

  void setLanguage(String language) {
    if (language == state.language) return;
    state = state.copyWith(language: language, results: const [], searched: false, error: () => null);
  }

  void setPerfectMatch(bool value) {
    if (value == state.perfectMatch) return;
    state = state.copyWith(perfectMatch: value, results: const [], searched: false, error: () => null);
  }

  Future<void> search() async {
    if (state.processing) return;
    state = state.copyWith(processing: true, error: () => null);
    final result = await api.api
        .itemsItemIdRemoteSearchSubtitlesLanguageGet(
          itemId: itemId,
          language: state.language,
          isPerfectMatch: state.perfectMatch ? true : null,
        )
        .apiResult;
    if (!mounted) return;
    final results = [...?result.data]..sort(_byQuality);
    state = state.copyWith(
      processing: false,
      searched: true,
      results: results,
      error: () => result.isSuccess ? null : result.errorMessage,
    );
  }

  /// Asks the server to fetch [subtitle] and store it next to the media.
  /// The server then queues its own refresh of the item; the new stream is
  /// listed once that has run.
  Future<ApiResult<dynamic>> download(RemoteSubtitleInfo subtitle) async {
    final id = subtitle.id;
    if (id == null || id.isEmpty) {
      return ApiResult.failure(ApiError(message: 'Subtitle has no id'));
    }
    state = state.copyWith(downloadingId: () => id);
    final result = await api.api
        .itemsItemIdRemoteSearchSubtitlesSubtitleIdPost(
          itemId: itemId,
          subtitleId: id,
        )
        .apiResult;
    if (mounted) {
      state = state.copyWith(downloadingId: () => null);
    }
    return result;
  }

  /// Hash matches first, then by rating, then by popularity - the same order
  /// a person would scan the list in.
  static int _byQuality(RemoteSubtitleInfo a, RemoteSubtitleInfo b) {
    final hash = (b.isHashMatch == true ? 1 : 0).compareTo(a.isHashMatch == true ? 1 : 0);
    if (hash != 0) return hash;
    final rating = (b.communityRating ?? 0).compareTo(a.communityRating ?? 0);
    if (rating != 0) return rating;
    return (b.downloadCount ?? 0).compareTo(a.downloadCount ?? 0);
  }
}
