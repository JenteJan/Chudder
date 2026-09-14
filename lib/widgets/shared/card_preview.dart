import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart' as mpv;
import 'package:media_kit_video/media_kit_video.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/settings/home_settings_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';

final _log = Logger('CardPreview');

/// How long a card has to stay selected before it starts playing. Long enough
/// that moving across a row does not start a stream for every card on the way.
const Duration kCardPreviewDwell = Duration(milliseconds: 900);

const Duration _fadeIn = Duration(milliseconds: 450);
const Duration _fadeOut = Duration(milliseconds: 250);

/// The one preview playing, if any, and the card it belongs to.
class CardPreviewSession {
  CardPreviewSession._(this.owner, this.itemId, this.controller);

  final Object owner;
  final String itemId;
  final VideoController controller;

  /// Whether the picture is moving: until then the card keeps its artwork, so
  /// the video never shows up as a black box or a frozen first frame.
  final ValueNotifier<bool> ready = ValueNotifier(false);
}

final cardPreviewProvider = Provider<CardPreviewController>((ref) {
  final controller = CardPreviewController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Plays a wide card silently from where it was left off, while it is the
/// selected one.
///
/// One player for the whole app, made the first time a card asks and kept:
/// selecting another card stops what it plays and opens the next. It used to
/// be a new player per preview, disposed when the card lost the selection -
/// and disposing one that was still opening its stream took the whole app
/// down with it. Stopping and reopening is what a player is built for.
///
/// Its own player rather than the app's: the preview must not touch what the
/// player, the mini player or the OS media controls think is playing, nor
/// report progress to the server. None plays while anything else does.
class CardPreviewController {
  CardPreviewController(this.ref) {
    ref.listen(mediaPlaybackProvider.select((value) => value.state), (_, next) {
      if (next != VideoPlayerState.disposed) stopAll();
    });
    ref.listen(isVideoPlayerRouteOpenProvider, (_, next) {
      if (next) stopAll();
    });
  }

  final Ref ref;

  final ValueNotifier<CardPreviewSession?> session = ValueNotifier(null);

  mpv.Player? _player;
  VideoController? _video;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  Object? _pendingOwner;
  Timer? _dwell;
  int _generation = 0;
  bool _disposed = false;

  /// Whether [item] can be previewed at all right now.
  bool canPreview(ItemBaseModel item) {
    if (kIsWeb || _disposed) return false;
    if (item is! MovieModel && item is! EpisodeModel) return false;
    if (!ref.read(homeSettingsProvider).cardPreviews) return false;
    if (ref.read(offlineStateProvider)) return false;
    if (ref.read(mediaPlaybackProvider).state != VideoPlayerState.disposed) return false;
    if (ref.read(isVideoPlayerRouteOpenProvider)) return false;
    return ref.read(userProvider)?.credentials.token != null;
  }

  /// [owner] is selected and shows [item]; it plays once it has stayed so.
  void select(Object owner, ItemBaseModel item) {
    if (_pendingOwner == owner || session.value?.owner == owner) return;
    stopAll();
    if (!canPreview(item)) return;
    _pendingOwner = owner;
    final generation = _generation;
    _dwell = Timer(kCardPreviewDwell, () => _start(owner, item, generation));
  }

  /// [owner] is no longer selected.
  void deselect(Object owner) {
    if (_pendingOwner == owner || session.value?.owner == owner) stopAll();
  }

  void stopAll() {
    final generation = ++_generation;
    _dwell?.cancel();
    _dwell = null;
    _pendingOwner = null;
    if (session.value == null) return;
    session.value = null;
    // The card fades the picture out first; the player stops once it has, and
    // only if nothing has been opened on it meanwhile.
    Future.delayed(_fadeOut + const Duration(milliseconds: 50), () async {
      if (generation != _generation || _disposed) return;
      try {
        await _player?.stop();
      } catch (_) {}
    });
  }

  Future<(mpv.Player, VideoController)> _ensurePlayer() async {
    final existing = _player;
    final existingVideo = _video;
    if (existing != null && existingVideo != null) return (existing, existingVideo);

    // Normally done by the app's player the first time something plays; a
    // preview can come first.
    mpv.MediaKit.ensureInitialized();
    final player = mpv.Player(
      configuration: const mpv.PlayerConfiguration(
        title: 'Chudder preview',
        muted: true,
        libass: false,
        bufferSize: 32 * 1024 * 1024,
        logLevel: mpv.MPVLogLevel.warn,
      ),
    );
    final video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: ref.read(videoPlayerSettingsProvider).hardwareAccel,
      ),
    );
    _player = player;
    _video = video;

    if (player.platform is mpv.NativePlayer) {
      final native = player.platform as dynamic;
      // No sound to play, so none to decode - and no audio device opened.
      await native.setProperty('aid', 'no');
      await native.setProperty('sid', 'no');
      await native.setProperty('cache', 'yes');
      await native.setProperty('cache-on-disk', 'no');
      await native.setProperty('demuxer-max-bytes', '32M');
      await native.setProperty('network-timeout', '20');
    }

    // What mpv has to say about a file it cannot play is the only clue to why
    // one title previews and the next does not.
    _subscriptions
      ..add(player.stream.error.listen((error) => _log.info('Preview of ${session.value?.itemId}: $error')))
      ..add(player.stream.log.where((entry) => entry.level == 'error' || entry.level == 'fatal').listen(
          (entry) => _log.info('Preview of ${session.value?.itemId}: mpv ${entry.prefix}: ${entry.text.trim()}')))
      ..add(player.stream.completed.listen((completed) {
        if (completed && session.value?.ready.value == true) stopAll();
      }));
    return (player, video);
  }

  Future<void> _start(Object owner, ItemBaseModel item, int generation) async {
    _dwell = null;
    if (generation != _generation || !canPreview(item)) return;
    _pendingOwner = null;

    final position = item.userData.playBackPosition;
    final started = DateTime.now();
    try {
      final (player, video) = await _ensurePlayer();
      if (generation != _generation) return;

      final current = CardPreviewSession._(owner, item.id, video);
      session.value = current;
      bool stale() => generation != _generation || !identical(session.value, current);

      _log.info('Preview of ${item.id} (${item.name}) opening at $position');
      // On the media, not set on the player beforehand: the player clears
      // its start position as it lets go of the last file, which comes after.
      await player.open(mpv.Media(_streamUrl(item), start: position), play: true);
      if (stale()) return;

      // Ready once this file is moving past where it started. Opening resets
      // what the player reports, so what it said about the last file does not
      // count.
      final moving = position + const Duration(milliseconds: 200);
      final deadline = started.add(const Duration(seconds: 20));
      while (player.state.position < moving) {
        if (DateTime.now().isAfter(deadline)) throw TimeoutException('no moving picture after 20s');
        await Future.delayed(const Duration(milliseconds: 100));
        if (stale()) return;
      }
      current.ready.value = true;
      _log.info('Preview of ${item.id}: playing after ${DateTime.now().difference(started).inMilliseconds}ms');
    } catch (error) {
      if (generation != _generation) return;
      _log.info('Preview of ${item.id} stopped: $error');
      stopAll();
    }
  }

  String _streamUrl(ItemBaseModel item) => buildServerUrl(
        ref,
        pathSegments: ['Videos', item.id, 'stream'],
        queryParameters: {
          'Static': 'true',
          'mediaSourceId': item.id,
          ...authQueryParameters(ref.read(userProvider)?.credentials.token),
        },
      );

  void dispose() {
    stopAll();
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    // The app is going away with it; the player goes with the process rather
    // than being torn down while it may still be busy.
  }
}

/// Whether a card is the selected one: under the pointer, or holding the focus.
class PreviewSelection {
  final ValueNotifier<bool> _active = ValueNotifier(false);
  bool _hovered = false;
  bool _focused = false;

  ValueListenable<bool> get active => _active;

  set hovered(bool value) {
    _hovered = value;
    _active.value = _hovered || _focused;
  }

  set focused(bool value) {
    _focused = value;
    _active.value = _hovered || _focused;
  }

  void dispose() => _active.dispose();
}

/// [child] - a card's artwork - with [item] playing over it while [active].
class CardPreview extends ConsumerStatefulWidget {
  const CardPreview({required this.item, required this.active, required this.child, super.key});

  final ItemBaseModel item;
  final ValueListenable<bool> active;
  final Widget child;

  @override
  ConsumerState<CardPreview> createState() => _CardPreviewState();
}

class _CardPreviewState extends ConsumerState<CardPreview> {
  final Object _owner = Object();
  late final CardPreviewController _controller = ref.read(cardPreviewProvider);

  /// The session this card is showing, kept through the fade after it ends.
  CardPreviewSession? _shown;
  bool _visible = false;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    widget.active.addListener(_onActive);
    _controller.session.addListener(_onSession);
  }

  @override
  void didUpdateWidget(covariant CardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      oldWidget.active.removeListener(_onActive);
      widget.active.addListener(_onActive);
    }
    if (oldWidget.item.id != widget.item.id) {
      _controller.deselect(_owner);
      _onActive();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A page pushed over this one, or a tab left, turns tickers off. Nothing
    // there is selected any more as far as the viewer can tell.
    _enabled = TickerMode.valuesOf(context).enabled;
    _onActive();
  }

  void _onActive() {
    if (widget.active.value && _enabled) {
      _controller.select(_owner, widget.item);
    } else {
      _controller.deselect(_owner);
    }
  }

  void _onSession() {
    final session = _controller.session.value;
    if (session != null && session.owner == _owner) {
      if (identical(session, _shown)) return;
      _shown?.ready.removeListener(_onReady);
      _shown = session..ready.addListener(_onReady);
      _onReady();
    } else if (_shown != null) {
      _shown!.ready.removeListener(_onReady);
      // Never seen, nothing to fade: gone at once, before its player is.
      _update(() => _visible ? _visible = false : _shown = null);
    }
  }

  void _onReady() {
    final ready = _shown?.ready.value ?? false;
    if (ready != _visible) _update(() => _visible = ready);
  }

  /// Sessions change when another card is selected, which can be in the middle
  /// of building that card; this one catches up after the frame then.
  void _update(VoidCallback change) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _update(change));
      return;
    }
    setState(change);
  }

  @override
  void dispose() {
    widget.active.removeListener(_onActive);
    _controller.session.removeListener(_onSession);
    _shown?.ready.removeListener(_onReady);
    _controller.deselect(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    // The video goes under the artwork, and the artwork fades away. Faded in
    // from nothing, the video was never painted - and a texture nobody paints
    // is one the player renders no frame into, so it never became ready.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (shown != null)
          IgnorePointer(
            child: Video(
              controller: shown.controller,
              fit: BoxFit.cover,
              fill: Colors.transparent,
              wakelock: false,
              filterQuality: FilterQuality.medium,
              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
              controls: NoVideoControls,
            ),
          ),
        AnimatedOpacity(
          opacity: _visible ? 0 : 1,
          duration: _visible ? _fadeIn : _fadeOut,
          curve: Curves.easeOut,
          onEnd: () {
            if (!_visible && mounted) setState(() => _shown = null);
          },
          child: widget.child,
        ),
      ],
    );
  }
}
