// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/recommended_model.dart';

class HomeModel {
  final bool loading;
  final List<ItemBaseModel> resumeVideo;
  final List<ItemBaseModel> resumeAudio;
  final List<ItemBaseModel> resumeBooks;
  final List<ItemBaseModel> activePrograms;
  final List<ItemBaseModel> nextUp;

  /// The one row of things to carry on with: what is half-watched and what
  /// comes next, in the order they were last played. Built where the lists are
  /// fetched, so the screen only draws it.
  final List<ItemBaseModel> continueWatching;

  /// A row per genre, the way the libraries page shows them: something to
  /// browse once there is nothing left to carry on with. The dashboard was
  /// three rows long on a well-watched account.
  final List<RecommendedModel> genres;

  /// What the server suggests off the back of what has been played - similar to
  /// recently played, the same director, the same actor. Films only; that is
  /// all the endpoint answers for.
  final List<RecommendedModel> suggestions;

  HomeModel({
    this.loading = false,
    this.resumeVideo = const [],
    this.resumeAudio = const [],
    this.resumeBooks = const [],
    this.activePrograms = const [],
    this.nextUp = const [],
    this.continueWatching = const [],
    this.genres = const [],
    this.suggestions = const [],
  });

  HomeModel copyWith({
    bool? loading,
    List<ItemBaseModel>? resumeVideo,
    List<ItemBaseModel>? resumeAudio,
    List<ItemBaseModel>? resumeBooks,
    List<ItemBaseModel>? activePrograms,
    List<ItemBaseModel>? nextUp,
    List<ItemBaseModel>? nextUpBooks,
    List<ItemBaseModel>? continueWatching,
    List<RecommendedModel>? genres,
    List<RecommendedModel>? suggestions,
  }) {
    return HomeModel(
      loading: loading ?? this.loading,
      resumeVideo: resumeVideo ?? this.resumeVideo,
      resumeAudio: resumeAudio ?? this.resumeAudio,
      resumeBooks: resumeBooks ?? this.resumeBooks,
      activePrograms: activePrograms ?? this.activePrograms,
      nextUp: nextUp ?? this.nextUp,
      continueWatching: continueWatching ?? this.continueWatching,
      genres: genres ?? this.genres,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}
