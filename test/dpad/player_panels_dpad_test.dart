// The player's own panels, by remote.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/video_player_episodes.dart';
import 'package:chudder/util/focus_provider.dart';

import 'dpad_fakes.dart';
import 'dpad_walk.dart';

EpisodeModel _episode(int season, int episode) => EpisodeModel(
      seriesName: 'Show',
      season: season,
      episode: episode,
      episodeEnd: null,
      name: 'Episode $season.$episode',
      id: 'show-$season-$episode',
      overview: const OverviewModel(),
      parentId: 'show',
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

void main() {
  testWidgets('the episodes panel: every episode and season by remote', (tester) async {
    final episodes = [
      for (var s = 1; s <= 2; s++)
        for (var e = 1; e <= 4; e++) _episode(s, e)
    ];
    final PlaybackModel playing = DirectPlaybackModel(
      item: episodes[1],
      media: const Media(url: 'episode'),
      queue: episodes,
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    late WidgetRef pageRef;
    await openDpad(
      tester,
      (context) {
        pageRef = context as WidgetRef;
        showPlayerEpisodes(context, pageRef);
      },
      overrides: [
        ...playerFakes,
        sharedPreferencesProvider.overrideWithValue(preferences),
        playBackModel.overrideWith((ref) => playing),
      ],
    );
    // It opens on the episode that is playing.
    expect(
        find.descendant(
            of: find.ancestor(of: find.textContaining('Episode 1.2'), matching: find.byType(FocusButton)).first,
            matching: find.byWidgetPredicate((w) => w is Focus && w.focusNode == FocusManager.instance.primaryFocus)),
        findsWidgets);
    final panel = find.ancestor(of: find.textContaining('Episode 1.2'), matching: find.byType(SafeArea)).first;
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: panel);

    // Up from the top of the list is its season, in one press.
    await expectPress(
      tester,
      from: find.ancestor(of: find.textContaining('Episode 1.1'), matching: find.byType(FocusButton)).first,
      key: LogicalKeyboardKey.arrowUp,
      to: find.ancestor(of: find.text('Season 1'), matching: find.byType(FocusButton)).first,
    );
  });
}
