import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_segments_model.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';

const _runtime = Duration(minutes: 22);

MovieModel _movie() => MovieModel(
      originalTitle: 'Spoorloos',
      premiereDate: DateTime(1988),
      sortName: 'Spoorloos',
      status: '',
      name: 'Spoorloos',
      id: 'movie',
      overview: const OverviewModel(runTime: _runtime),
      userData: const UserData(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      parentImages: null,
      mediaStreams: MediaStreamsModel(
        defaultAudioStreamIndex: null,
        defaultSubStreamIndex: -1,
        versionStreams: const [],
      ),
      canDownload: null,
      canDelete: null,
    );

DirectPlaybackModel _model({MediaSegment? outro}) => DirectPlaybackModel(
      item: _movie(),
      media: const Media(url: 'stream'),
      mediaSegments: outro == null ? null : MediaSegmentsModel(segments: [outro]),
    );

void main() {
  group('resolvedStopPosition', () {
    final credits = MediaSegment(
      type: MediaSegmentType.outro,
      start: const Duration(minutes: 19, seconds: 30),
      end: _runtime,
    );

    test('a stop in the closing credits is reported at the end', () {
      final model = _model(outro: credits);
      expect(model.resolvedStopPosition(const Duration(minutes: 20), _runtime), _runtime);
    });

    test('the runtime of the item stands in for a player that has no duration', () {
      final model = _model(outro: credits);
      expect(model.resolvedStopPosition(const Duration(minutes: 20), null), _runtime);
    });

    test('a stop before the credits is reported where it happened', () {
      final model = _model(outro: credits);
      expect(model.resolvedStopPosition(const Duration(minutes: 12), _runtime), const Duration(minutes: 12));
    });

    test('without segments nothing changes', () {
      expect(_model().resolvedStopPosition(const Duration(minutes: 20), _runtime), const Duration(minutes: 20));
    });
  });
}
