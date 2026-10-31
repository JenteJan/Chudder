// The shortest histories the fuzzer found each bug with, kept. Seeds matter:
// they decide the network's timing.
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';

import 'sim_scenarios.dart';
import 'sim_world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  MediaControlsWrapper.useSystemMediaSession = false;

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  // Real web found this one: a Pause a few milliseconds behind the resume it
  // cancels, while the play was waiting for the audio focus.
  test('a pause overtakes a play still on its way', () {
    FakeAsync(initialTime: DateTime.utc(2026, 10, 31)).run((async) {
      final world = SimWorld(Random(1), prefs);
      final m = SimMember(world, 'm0', Link.lan, prefs);
      final model = m.lonelyModel(m.firstEpisodes.first);
      m.container.read(playBackModel.notifier).state = model;
      async.elapse(const Duration(milliseconds: 100));
      final controls = m.container.read(videoPlayerProvider);
      m.sim.lastState = m.sim.lastState.update(playing: false);

      controls.play();
      controls.pause();
      async.elapse(const Duration(seconds: 1));

      expect(m.sim.lastState.playing, isFalse);
      world.server.close();
    });
  });

  void history(String name, Scenario scenario) {
    test(name, () {
      expect(runScenario(scenario, prefs).problems, isEmpty);
    });
  }

  history(
    'a Pause ahead of the state saying so is not undone by the recovery',
    pairScenario(35810),
  );
  history(
    'a seek does not land on the file after it',
    const Scenario(701006, Start.createdThenQueued, [Link.lan, Link.lan, Link.lan], -118, 2700, [
      Step(3098, 2, Act.seek, 1264),
      Step(3246, 2, Act.previous, 0),
      Step(3680, 2, Act.pause, 0),
    ]),
  );
  history(
    'the group changes item twice while a member still loads',
    const Scenario(156, Start.createdWhilePlaying, [Link.wan, Link.bad], -118, 2700, [
      Step(3865, 0, Act.loneEpisode, 2),
      Step(3921, 0, Act.previous, 0),
    ]),
  );
  history(
    'a load the group has left does not say Ready',
    const Scenario(157, Start.createdWhilePlaying, [Link.lan, Link.bad], -118, 2700, [
      Step(3122, 0, Act.previous, 0),
      Step(4048, 1, Act.loneEpisode, 5),
    ]),
  );
  history(
    'previous and next in quick succession over a slow link',
    const Scenario(100216, Start.createdThenQueued, [Link.lan, Link.bad], 2300, 2700, [
      Step(4265, 0, Act.previous, 0),
      Step(4776, 0, Act.next, 0),
    ]),
  );
  history(
    'a held resume is carried out after a rejoin and a new queue',
    const Scenario(100089, Start.createdThenQueued, [Link.bad, Link.lan, Link.lan], -118, 0, [
      Step(3993, 1, Act.leaveAndRejoin, 500),
      Step(4957, 1, Act.loneEpisode, 5),
    ]),
  );
  history(
    'a group paused past the end of the item does not chase its own tail',
    const Scenario(100986, Start.createdWhilePlaying, [Link.lan, Link.lan, Link.bad], -118, 2700, [
      Step(15812, 1, Act.seekNearEnd, 0),
      Step(21962, 2, Act.pause, 0),
      Step(28127, 0, Act.leaveAndRejoin, 500),
    ]),
  );
  history(
    'a member leaving a paused wait does not leave the others showing it',
    const Scenario(200484, Start.createdWhilePaused, [Link.lan, Link.bad], 2300, 2700, [
      Step(3587, 1, Act.leaveForGood, 0),
    ]),
  );
  history(
    'a queue handed to a player already on the item reaches it',
    const Scenario(400006, Start.playingThenHandedQueue, [Link.lan, Link.lan], 0, 0, []),
  );
  history(
    'a player closed during a load and reopened at once finds the group',
    const Scenario(400037, Start.playingThenHandedQueue, [Link.lan, Link.lan], 0, 0, [
      Step(6533, 1, Act.loneEpisode, 0),
      Step(6817, 0, Act.closePlayer, 0),
      Step(6958, 0, Act.reopenPlayer, 0),
    ]),
  );
}
