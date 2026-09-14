import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/chapters_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/items/trick_play_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/playback/transcode_playback_model.dart';
import 'package:chudder/models/video_stream_model.dart';

MediaStreamsModel _streams({bool withVersion = true}) => MediaStreamsModel(
      versionStreams: [
        if (withVersion)
          VersionStreamModel(
            name: 'main',
            index: 0,
            id: 'source',
            defaultAudioStreamIndex: 1,
            defaultSubStreamIndex: -1,
            videoStreams: const [],
            audioStreams: const [],
            subStreams: const [],
          ),
      ],
    );

MovieModel _movie({
  String id = 'movie',
  String name = 'Movie',
  bool withStreams = true,
  UserData userData = const UserData(),
  OverviewModel overview = const OverviewModel(),
}) =>
    MovieModel(
      originalTitle: name,
      premiereDate: DateTime(2000),
      sortName: name,
      status: '',
      name: name,
      id: id,
      overview: overview,
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: userData,
      parentImages: null,
      mediaStreams: _streams(withVersion: withStreams),
      canDownload: null,
      canDelete: null,
    );

bool _canStart(
  MovieModel item, {
  bool showPlaybackOptions = false,
  PlaybackType? forcedPlaybackType,
  bool isSynced = false,
  bool nativePlayer = false,
  bool casting = false,
}) =>
    canStartAheadOfFullItem(
      item: item,
      showPlaybackOptions: showPlaybackOptions,
      forcedPlaybackType: forcedPlaybackType,
      isSynced: isSynced,
      nativePlayer: nativePlayer,
      casting: casting,
    );

void main() {
  group('canStartAheadOfFullItem', () {
    test('a plain play of an item with its media sources starts ahead', () {
      expect(_canStart(_movie()), isTrue);
    });

    test('an item picked from a list without sources waits for the full item', () {
      expect(_canStart(_movie(withStreams: false)), isFalse);
    });

    test('anything that asks the user or hands the model over whole waits', () {
      expect(_canStart(_movie(), showPlaybackOptions: true), isFalse);
      expect(_canStart(_movie(), forcedPlaybackType: PlaybackType.transcode), isFalse);
      expect(_canStart(_movie(), isSynced: true), isFalse);
      expect(_canStart(_movie(), nativePlayer: true), isFalse);
      expect(_canStart(_movie(), casting: true), isFalse);
    });
  });

  group('mergeFullItem', () {
    final chapter = Chapter(name: 'one', imageUrl: '', startPosition: const Duration(minutes: 1));
    final trickPlay = TrickPlayModel(
      width: 320,
      height: 180,
      tileWidth: 10,
      tileHeight: 10,
      thumbnailCount: 5,
      interval: const Duration(seconds: 10),
    );

    test('takes the full item and its chapters, keeps the user data the play started from', () {
      const startedFrom = UserData(playbackPositionTicks: 840000000);
      final model = DirectPlaybackModel(
        item: _movie(userData: startedFrom),
        media: const Media(url: 'stream'),
        chapters: const [],
      );
      final full = _movie(
        name: 'Movie (full)',
        userData: const UserData(),
        overview: OverviewModel(summary: 'details', chapters: [chapter]),
      );

      final merged = mergeFullItem(model, full, trickPlay: trickPlay);

      expect(merged, isA<DirectPlaybackModel>());
      expect(merged!.item.name, 'Movie (full)');
      expect(merged.item.overview.summary, 'details');
      expect(merged.item.userData, startedFrom);
      expect(merged.chapters, [chapter]);
      expect(merged.trickPlay, trickPlay);
      expect(merged.media?.url, 'stream');
    });

    test('keeps chapters and trickplay the model already had', () {
      final own = Chapter(name: 'own', imageUrl: '', startPosition: Duration.zero);
      final ownTrickPlay = trickPlay.copyWith(width: 640);
      final model = TranscodePlaybackModel(
        item: _movie(),
        media: const Media(url: 'hls'),
        playbackInfo: null,
        chapters: [own],
        trickPlay: ownTrickPlay,
      );
      final full = _movie(overview: OverviewModel(chapters: [chapter]));

      final merged = mergeFullItem(model, full, trickPlay: trickPlay);

      expect(merged, isA<TranscodePlaybackModel>());
      expect(merged!.chapters, [own]);
      expect(merged.trickPlay, ownTrickPlay);
    });

    test('never merges a different item', () {
      final model = DirectPlaybackModel(item: _movie(), media: const Media(url: 'stream'));
      expect(mergeFullItem(model, _movie(id: 'other')), isNull);
    });
  });
}
