// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:fladder/models/item_base_model.dart';

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

  HomeModel({
    this.loading = false,
    this.resumeVideo = const [],
    this.resumeAudio = const [],
    this.resumeBooks = const [],
    this.activePrograms = const [],
    this.nextUp = const [],
    this.continueWatching = const [],
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
  }) {
    return HomeModel(
      loading: loading ?? this.loading,
      resumeVideo: resumeVideo ?? this.resumeVideo,
      resumeAudio: resumeAudio ?? this.resumeAudio,
      resumeBooks: resumeBooks ?? this.resumeBooks,
      activePrograms: activePrograms ?? this.activePrograms,
      nextUp: nextUp ?? this.nextUp,
      continueWatching: continueWatching ?? this.continueWatching,
    );
  }
}
