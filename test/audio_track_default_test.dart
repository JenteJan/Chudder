import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/util/streams_selection.dart';

AudioStreamModel _audio({
  required int index,
  required String language,
  String codec = 'ac3',
}) =>
    AudioStreamModel(
      displayTitle: '${language.toUpperCase()} - AC3',
      name: '',
      codec: codec,
      isDefault: false,
      isExternal: false,
      index: index,
      language: language,
      channelLayout: '5.1',
      sampleRate: 48000,
      channels: 6,
      bitRate: 448000,
      bitDepth: null,
      profile: null,
      spatialFormat: null,
    );

/// A film with two unflagged audio tracks, which is what a DVD rip of a
/// non-English film looks like: nothing carries the default flag and nothing
/// matches the account's preferred language, so the server hands over no
/// default index at all.
MediaStreamsModel _streams({int? defaultAudioStreamIndex}) => MediaStreamsModel(
      defaultAudioStreamIndex: defaultAudioStreamIndex,
      defaultSubStreamIndex: -1,
      versionStreams: [
        VersionStreamModel(
          name: 'main',
          index: 0,
          id: 'source',
          defaultAudioStreamIndex: defaultAudioStreamIndex,
          defaultSubStreamIndex: -1,
          videoStreams: const [],
          audioStreams: [
            _audio(index: 1, language: 'dut'),
            _audio(index: 2, language: 'ger'),
          ],
          subStreams: const [],
        ),
      ],
    );

MovieModel _movie(MediaStreamsModel streams) => MovieModel(
      originalTitle: 'Spoorloos',
      premiereDate: DateTime(1988),
      sortName: 'Spoorloos',
      status: '',
      name: 'Spoorloos',
      id: 'movie',
      overview: const OverviewModel(),
      userData: const UserData(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      parentImages: null,
      mediaStreams: streams,
      canDownload: null,
      canDelete: null,
    );

void main() {
  group('currentAudioStream', () {
    test('no index from the server means the first track, not off', () {
      final current = _streams().currentAudioStream;

      expect(current?.index, 1);
      expect(current?.language, 'dut');
    });

    test('-1 is still off, because somebody chose it', () {
      expect(_streams(defaultAudioStreamIndex: -1).currentAudioStream?.index, -1);
    });

    test('an index that is listed wins', () {
      expect(_streams(defaultAudioStreamIndex: 2).currentAudioStream?.language, 'ger');
    });
  });

  group('defaultAudioStream', () {
    DirectPlaybackModel model({int? defaultAudioStreamIndex}) {
      final streams = _streams(defaultAudioStreamIndex: defaultAudioStreamIndex);
      return DirectPlaybackModel(
        item: _movie(streams),
        media: const Media(url: 'stream'),
        mediaStreams: streams,
      );
    }

    test('an index nothing answers to plays the first track rather than silence', () {
      expect(model(defaultAudioStreamIndex: 7).defaultAudioStream?.index, 1);
    });

    test('off stays off', () {
      expect(model(defaultAudioStreamIndex: -1).defaultAudioStream?.index, -1);
    });
  });

  group('selectAudioStream across a reload', () {
    test('a film with no default index keeps its track instead of muting', () {
      final before = _streams();
      final after = _streams();

      final selected = selectAudioStream(
        true,
        before.currentAudioStream,
        [AudioStreamModel.no(), ...after.audioStreams],
        after.defaultAudioStreamIndex,
      );

      expect(selected, isNot(-1), reason: 'remembering "off" is how a switch of subtitle killed the audio');
      expect(selected, 1);
    });

    test('a chosen off is remembered as off', () {
      final before = _streams(defaultAudioStreamIndex: -1);
      final after = _streams(defaultAudioStreamIndex: -1);

      final selected = selectAudioStream(
        true,
        before.currentAudioStream,
        [AudioStreamModel.no(), ...after.audioStreams],
        after.defaultAudioStreamIndex,
      );

      expect(selected, -1);
    });
  });
}
