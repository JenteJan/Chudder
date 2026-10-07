// Hypotheses about the app's own half of SyncPlay, as tests.
//
// Not part of the suite - it lives outside test/ on purpose. Each test states
// a suspected inconsistency and asserts that the code does behave that way
// today: a pass means the hypothesis is confirmed, a failure that the
// behaviour has changed (and the test wants turning into a regression test
// under test/). Run with:
//
//   flutter test tool/syncplay_probe/hypotheses_test.dart
//
// The server's half is probed by sp.py / experiments.py next to this file.
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/syncplay/handlers/syncplay_command_handler.dart';
import 'package:chudder/util/continue_row.dart';

EpisodeModel _episode(String id, String show, {DateTime? lastPlayed}) => EpisodeModel(
      seriesName: show,
      season: 1,
      episode: 1,
      episodeEnd: null,
      name: id,
      id: id,
      overview: const OverviewModel(),
      parentId: show,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: UserData(lastPlayed: lastPlayed),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

MovieModel _movie(String id, {DateTime? lastPlayed}) => MovieModel(
      originalTitle: id,
      premiereDate: DateTime(2000),
      sortName: id,
      status: '',
      name: id,
      id: id,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: UserData(lastPlayed: lastPlayed),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

List<String> _ids(List<ItemBaseModel> items) => items.map((item) => item.id).toList();

Map<String, dynamic> _command(String command, DateTime when, int ticks) => {
      'Command': command,
      'When': when.toUtc().toIso8601String(),
      'PositionTicks': ticks,
      'PlaylistItemId': 'playlist-item-1',
    };

void main() {
  group('Continue watching row', () {
    test('D1: the episode after the one just finished sorts under a film paused days ago', () {
      // Tonight: finished show-x e1, so Next Up offers e2, which has never
      // been started and so carries no date. Show-y was last watched on the
      // 10th, a film paused on the 12th.
      final nextUp = <ItemBaseModel>[
        _episode('show-x-e2', 'show-x'),
        _episode('show-y-e5', 'show-y', lastPlayed: DateTime(2026, 9, 10)),
      ];
      final resume = <ItemBaseModel>[_movie('film', lastPlayed: DateTime(2026, 9, 12))];

      final row = _ids(combineContinueRow(nextUp, resume));

      // The server put show-x first: it is what was watched last. The row
      // ranks it by the date borrowed from the show below it.
      expect(row, ['film', 'show-x-e2', 'show-y-e5']);
    });

    test('D2: with no dated Next Up item at all, every resumed film goes above the show just watched', () {
      final nextUp = <ItemBaseModel>[_episode('show-x-e2', 'show-x')];
      final resume = <ItemBaseModel>[
        _movie('film-last-week', lastPlayed: DateTime(2026, 9, 1)),
        _movie('film-last-year', lastPlayed: DateTime(2025, 9, 1)),
      ];

      expect(_ids(combineContinueRow(nextUp, resume)), ['film-last-week', 'film-last-year', 'show-x-e2']);
    });

    test('D3: an earlier unwatched episode hides the one actually in progress', () {
      // What the session of 7 October left behind: e1 unplayed (thrown back
      // to 1:34, under the resume floor), e2 part-way through.
      final nextUp = <ItemBaseModel>[_episode('show-e1', 'show')];
      final resume = <ItemBaseModel>[_episode('show-e2', 'show', lastPlayed: DateTime(2026, 10, 7))];

      expect(_ids(combineContinueRow(nextUp, resume)), ['show-e1']);
    });
  });

  group('Command handler', () {
    test('C1: the server\'s repeat of a Seek is dropped, so a rejected Ready is never retried', () async {
      // The server answers a Ready that is more than 500 ms off the group's
      // position with the group's Seek again - same When, same position - and
      // keeps the group waiting for a Ready at the right place.
      var seeks = 0;
      var readies = 0;
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPause = () async {}
        ..onSeek = (_) async {
          seeks++;
        }
        ..onReportReady = (_) async {
          readies++;
        }
        ..isBuffering = () => false;

      final when = DateTime.now();
      handler.handleCommand(_command('Seek', when, 1200 * ticksPerSecond), SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((seeks, readies), (1, 1));

      handler.handleCommand(_command('Seek', when, 1200 * ticksPerSecond), SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((seeks, readies), (1, 1), reason: 'nothing seeks or reports again');
    });

    test('C2: a re-sent Unpause is dropped when the player merely reads as playing', () async {
      var plays = 0;
      var reportsPlaying = false;
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPlay = () async {
          plays++;
        }
        ..onSeek = ((_) async {})
        ..getPositionTicks = (() => 0)
        ..isPlaying = (() => reportsPlaying);

      final unpause = _command('Unpause', DateTime.now(), 0);
      handler.handleCommand(unpause, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(plays, 1);

      // Something paused the player locally - a media key, the notification -
      // without the flag following, or the flag was never right to begin with.
      reportsPlaying = true;
      handler.handleCommand(unpause, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(plays, 1, reason: 'the only thing that could restart it is thrown away');
    });

  });

  group('Drift correction', () {
    test('S1: a player a second ahead is no longer slowed to a crawl', () {
      final plan = computeSpeedToSync(diffMillis: -1000, baseDurationMs: 1000);
      expect(plan.rate, greaterThanOrEqualTo(0.8));
    });

    test('S2: the server accepts a Ready within 500 ms, the client only corrects from 60 ms', () {
      // Both numbers matter together: a member the chronic-lag backoff lets
      // sit more than half a second behind has every Ready rejected.
      const config = SyncCorrectionConfig();
      final widened = adaptiveCorrectionConfig(base: config, pingMs: 300, jitterMs: 100, extraSlackMultiplier: 4);
      expect(config.minDelaySpeedToSyncMs, 60);
      expect(widened.minDelaySpeedToSyncMs, greaterThan(500),
          reason: 'on a slow link the tolerated drift exceeds what the server will take a Ready at');
    });
  });
}
