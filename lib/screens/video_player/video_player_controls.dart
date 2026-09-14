import 'dart:async';

import 'package:async/async.dart';
import 'package:volume_controller/volume_controller.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/media_segments_model.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/providers/arguments_provider.dart';
import 'package:chudder/providers/pip_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/player_controls_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/shared/chudder_icon.dart';
import 'package:chudder/screens/shared/default_title_bar.dart';
import 'package:chudder/screens/shared/media/components/item_logo.dart';
import 'package:chudder/screens/video_player/components/cast_button.dart';
import 'package:chudder/screens/video_player/components/scrub_ramp.dart';
import 'package:chudder/screens/video_player/components/syncplay_command_indicator.dart';
import 'package:chudder/screens/video_player/components/video_playback_information.dart';
import 'package:chudder/screens/video_player/components/video_player_brightness_indicator.dart';
import 'package:chudder/screens/video_player/components/video_player_controls_extras.dart';
import 'package:chudder/screens/video_player/components/video_player_episodes.dart';
import 'package:chudder/screens/video_player/components/video_player_options_sheet.dart';
import 'package:chudder/screens/video_player/components/video_player_quality_controls.dart';
import 'package:chudder/screens/video_player/components/video_player_screenshot_indicator.dart';
import 'package:chudder/screens/video_player/components/video_player_seek_indicator.dart';
import 'package:chudder/screens/video_player/components/video_player_speed_indicator.dart';
import 'package:chudder/screens/video_player/components/video_player_volume_indicator.dart';
import 'package:chudder/screens/video_player/components/video_progress_bar.dart';
import 'package:chudder/screens/video_player/components/video_volume_slider.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/widgets/shared/focus_ring.dart';
import 'package:chudder/util/player_shortcuts.dart';
import 'package:chudder/util/trackpad_navigation.dart';
import 'package:chudder/util/duration_extensions.dart';
import 'package:chudder/util/input_handler.dart';
import 'package:chudder/util/list_padding.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/string_extensions.dart';
import 'package:chudder/widgets/full_screen_helpers/full_screen_wrapper.dart';
import 'package:chudder/widgets/syncplay/syncplay_badge.dart';
import 'package:chudder/widgets/syncplay/syncplay_button.dart';
import 'package:chudder/wrappers/pip_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';

class DesktopControls extends ConsumerStatefulWidget {
  const DesktopControls({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DesktopControlsState();
}

class _DesktopControlsState extends ConsumerState<DesktopControls> {
  final GlobalKey _bottomControlsKey = GlobalKey();

  late final initInputDevice = AdaptiveLayout.inputDeviceOf(context);

  late RestartableTimer timer = RestartableTimer(
    const Duration(seconds: 5),
    () {
      if (!mounted) return;
      // While casting there's no video underneath — the controls ARE the
      // screen, so they stay visible.
      if (ref.read(videoPlayerProvider).isCasting) return;
      // Nor while a dialog is up. Hiding the controls underneath one takes the
      // selection with it - down to the player surface, behind the barrier,
      // where it is invisible and nothing responds to the pad. Wait instead,
      // and the controls are still there when the dialog closes.
      if (!_routeIsCurrent) {
        timer.reset();
        return;
      }
      // Nor while the scrubber is walked and waiting for OK: hiding the
      // controls would take the walk with them, unanswered.
      if (_scrubTarget != null) {
        timer.reset();
        return;
      }
      toggleOverlay(value: false);
    },
  );

  double? previousVolume;

  bool _volumePanelOpen = false;

  /// Somewhere for focus to sit while the controls are down.
  ///
  /// Focus must never be left with nowhere to be. Hiding the controls takes
  /// them out of the focus order, and a focus that has landed nowhere receives
  /// no key events at all - which is how a remote stopped answering after the
  /// controls timed out, and could not be got back.
  final FocusNode _playerFocus = FocusNode(debugLabel: 'playerSurface');

  /// The controls, as somewhere focus can be sent.
  final FocusScopeNode _controlsScope = FocusScopeNode(debugLabel: 'playerControls');

  /// Play/pause, which is where a remote should find itself when the controls
  /// first come up - it is the one control anybody is looking for.
  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'playPause');

  /// The scrubber and the volume, which a remote steers rather than presses.
  final FocusNode _scrubberFocus = FocusNode(debugLabel: 'scrubber');
  final FocusNode _volumeFocus = FocusNode(debugLabel: 'volume');

  /// Where the scrubber has been walked to, before it is committed.
  ///
  /// A remote seeks by travelling: you hold a direction and watch the position
  /// move, then stop where you want it. Seeking the player on every press
  /// instead would ask it to reopen the stream a dozen times on the way, which
  /// is what made a single press jump so far - the step had to be large enough
  /// to be worth one seek.
  ///
  /// Nothing is sought until OK: the walk is only a proposal, read off the
  /// preview, and Back or leaving the bar withdraws it. The controls stay up
  /// for as long as one is pending - see [timer].
  Duration? _scrubTarget;

  /// How far each press moves - a tap a nudge, a hold a ramp. See [ScrubRamp].
  final ScrubRamp _scrubRamp = ScrubRamp();

  final fadeDuration = const Duration(milliseconds: 350);
  bool showOverlay = true;
  bool wasPlaying = false;
  SystemUiMode? _currentSystemUiMode;

  bool _speedBoostActive = false;
  double? _originalSpeed;

  Offset? _doubleTapPosition;

  final SeekIndicatorController _seekController = SeekIndicatorController();

  late final double topPadding = MediaQuery.of(context).viewPadding.top;
  late final double bottomPadding = MediaQuery.of(context).viewPadding.bottom;

  String? _vDragSide;
  double? _vDragStartValue;
  double? _vDragLastValue;

  int? _lastSelectedSubtitleIndex;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _controlsVisible = _container.read(playerControlsVisibleProvider.notifier);
    timer.reset();
    _lastSelectedSubtitleIndex = null;

    // Said once at the start as well as on every change. The controls open
    // already showing, so [toggleOverlay] - which only speaks when the answer
    // changes - never got to say so, and the seek indicator went on believing
    // they were down. It kept its arrows bound and seeked ten seconds on top
    // of every press that was meant to be walking the scrubber.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controlsVisible.state = showOverlay;
    });
  }

  /// Held from the start so it can still be cleared once this is going away.
  /// The container itself, held from [initState], for anything that has to
  /// reach a provider from [dispose] or later.
  ///
  /// `ref` is unusable by then - the element is already unmounted - and a
  /// throw from inside dispose leaves Flutter's own unmount half done, which
  /// is a tree that cannot build another frame until the app restarts. The
  /// container does not care whether this widget still exists.
  late final ProviderContainer _container;

  // Not a lazy initialiser: one of those resolves on first use, and the first
  // use could be [dispose].
  late final StateController<bool> _controlsVisible;

  @override
  void dispose() {
    // Nothing is on top of the player any more.
    //
    // Deferred: dispose can run inside a build - unmounting happens while the
    // tree is being rebuilt - and writing a provider there throws
    // "Tried to modify a provider while the widget tree was building". The
    // throw lands mid-unmount, which is what produced the "deactivated
    // widget's ancestor" and "_lifecycleState != defunct" cascade behind it.
    // The container outlives this widget, so the write is safe a tick later.
    final controlsVisible = _controlsVisible;
    Future(() => controlsVisible.state = false);
    _clickToggle?.cancel();
    _playerFocus.dispose();
    _controlsScope.dispose();
    _playPauseFocus.dispose();
    _scrubberFocus.dispose();
    _volumeFocus.dispose();
    // Never cancelled before: it went on to fire after the player was gone and
    // reached for providers through an element that was no longer in the tree.
    timer.cancel();
    _deactivateSpeedBoost();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInPip = ref.watch(pipStateProvider).asData?.value ?? false;
    final player = ref.watch(videoPlayerProvider);
    if (isInPip) {
      // Keep only the subtitle widget so it's captured in the PiP frame.
      final pipSubtitleWidget = player.subtitleWidget(false, controlsKey: _bottomControlsKey);
      return Stack(
        children: [
          if (pipSubtitleWidget != null) Positioned.fill(child: pipSubtitleWidget),
        ],
      );
    }
    final mediaSegments = ref.watch(playBackModel.select((value) => value?.mediaSegments));
    final subtitleWidget = player.subtitleWidget(showOverlay, controlsKey: _bottomControlsKey);
    final isDesktop = AdaptiveLayout.of(context).isDesktop || kIsWeb;
    final speedBoostEnabled = ref.watch(videoPlayerSettingsProvider.select((value) => value.enableSpeedBoost));

    // Read every build, unlike [initInputDevice], which is taken once when the
    // player opens and never revised - so starting playback with a mouse left
    // it saying "pointer" for the whole session and a remote picked up
    // afterwards was never recognised as one.
    final inputDevice = AdaptiveLayout.inputDeviceOf(context);

    return Listener(
      onPointerSignal: setVolume,
      child: InputHandler(
        autoFocus: true,
        keyMap: ref
            .watch(videoPlayerSettingsProvider.select((value) => value.currentShortcuts))
            .withoutPlainArrows(when: inputDevice == InputDevice.dPad),
        keyMapResult: _onKey,
        onKeyEvent: (node, event) {
          final remote = _handleRemoteKey(inputDevice, event);
          if (remote != KeyEventResult.ignored) return remote;
          if (isDesktop && speedBoostEnabled && event.logicalKey == LogicalKeyboardKey.space) {
            return _handleSpacebarEvent(event);
          }
          return KeyEventResult.ignored;
        },
        child: PopScope(
          canPop: false,
          // Back, backspace and the mouse's back button leave the player. At a
          // desk that is not the film: it drops to the minimized surfaces and
          // plays on, and stopping is the close button's job. On a television
          // leaving is stopping - see leavePlayer.
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              leavePlayer(context);
            }
          },
          child: Focus(
              focusNode: _playerFocus,
              // Not a stop on the way round - only a home for focus while the
              // controls are down.
              skipTraversal: true,
              child: MouseRegion(
                cursor: showOverlay ? SystemMouseCursors.basic : SystemMouseCursors.none,
                onExit: (event) => toggleOverlay(value: false),
                onEnter: (event) => toggleOverlay(value: true),
                onHover: AdaptiveLayout.of(context).isDesktop || kIsWeb ? (event) => toggleOverlay(value: true) : null,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: initInputDevice == InputDevice.pointer ? null : () => toggleOverlay(),
                        onDoubleTapDown: initInputDevice == InputDevice.touch ? _handleDoubleTapDown : null,
                        onDoubleTap: initInputDevice == InputDevice.pointer
                            ? () => fullScreenHelper.toggleFullScreen(ref)
                            : _handleDoubleTapSeek,
                        onLongPressStart: initInputDevice == InputDevice.touch ? _handleLongPressStart : null,
                        onLongPressEnd: initInputDevice == InputDevice.touch ? _handleLongPressEnd : null,
                        onVerticalDragStart: initInputDevice == InputDevice.touch ? _handleVerticalDragStart : null,
                        onVerticalDragUpdate: initInputDevice == InputDevice.touch ? _handleVerticalDragUpdate : null,
                        onVerticalDragEnd: initInputDevice == InputDevice.touch ? _handleVerticalDragEnd : null,
                        //better play/pause handling on Desktop (works with dragging on click)
                        onHorizontalDragDown:
                            initInputDevice == InputDevice.pointer ? (details) => _clickPlayPause() : null,
                      ),
                    ),
                    if (subtitleWidget != null) subtitleWidget,
                    if (AdaptiveLayout.of(context).isDesktop)
                      Consumer(builder: (context, ref, child) {
                        final playing = ref.watch(mediaPlaybackProvider.select((value) => value.playing));
                        final buffering = ref.watch(mediaPlaybackProvider.select((value) => value.buffering));
                        return playButton(playing, buffering);
                      }),
                    IgnorePointer(
                      ignoring: !showOverlay,
                      // Out of the focus order as well as out of reach while they
                      // are down: they stay in the tree, only faded, so without
                      // this a remote could put focus on something invisible.
                      child: ExcludeFocus(
                        excluding: !showOverlay,
                        child: FocusScope(
                          node: _controlsScope,
                          child: AnimatedOpacity(
                            duration: fadeDuration,
                            opacity: showOverlay ? 1 : 0,
                            child: Column(
                              children: [
                                topButtons(context),
                                const Spacer(),
                                bottomButtons(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    VideoPlayerSeekIndicator(controller: _seekController),
                    const VideoPlayerVolumeIndicator(),
                    const VideoPlayerBrightnessIndicator(),
                    const VideoPlayerSpeedIndicator(),
                    const VideoPlayerScreenshotIndicator(),
                    const SyncPlayCommandIndicator(),
                    Consumer(
                      builder: (context, ref, child) {
                        final position = ref.watch(mediaPlaybackProvider.select((value) => value.position));
                        final skippedSegments =
                            ref.watch(mediaPlaybackProvider.select((value) => value.skippedSegments));
                        MediaSegment? segment = mediaSegments?.atPosition(position);
                        SegmentVisibility forceShow =
                            segment?.visibility(position, force: showOverlay) ?? SegmentVisibility.hidden;
                        final segmentSkipType = ref.watch(
                            videoPlayerSettingsProvider.select((value) => value.segmentSkipSettings[segment?.type]));

                        final segmentId = segment?.skipId;
                        final wasSkipped = segmentId != null && skippedSegments.contains(segmentId);

                        final autoSkip = forceShow != SegmentVisibility.hidden &&
                            (segmentSkipType == SegmentSkip.skip ||
                                (segmentSkipType == SegmentSkip.skipOnce && !wasSkipped)) &&
                            player.lastState?.buffering == false;

                        if (autoSkip) {
                          skipToSegmentEnd(segment, segmentId);
                        }
                        return Stack(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: SkipSegmentButton(
                                  segment: segment,
                                  skipType: segmentSkipType,
                                  visibility: forceShow,
                                  pressedSkip: () => skipToSegmentEnd(segment, null),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              )),
        ),
      ),
    );
  }

  Widget playButton(bool playing, bool buffering) {
    return Align(
      alignment: Alignment.center,
      child: AnimatedScale(
        curve: Curves.easeInOutCubicEmphasized,
        scale: playing
            ? 0
            : buffering
                ? 0
                : 1,
        duration: const Duration(milliseconds: 250),
        child: IconButton.outlined(
          onPressed: () => ref.read(videoPlayerProvider.notifier).userPlay(),
          isSelected: true,
          iconSize: 65,
          tooltip: "Resume video",
          icon: const ChudderPlayIcon(),
        ),
      ),
    );
  }

  Widget topButtons(BuildContext context) {
    final currentItem = ref.watch(playBackModel.select((value) => value?.item));
    final maxHeight = 150.clamp(50, (MediaQuery.sizeOf(context).height * 0.25).clamp(51, double.maxFinite)).toDouble();
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.8),
          Colors.black.withValues(alpha: 0),
        ],
      )),
      child: Padding(
        padding: MediaQuery.paddingOf(context).copyWith(bottom: 0, top: 0),
        child: Container(
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              const Align(
                alignment: Alignment.topCenter,
                child: DefaultTitleBar(),
              ),
              Padding(
                // Top inset matches the chrome buttons' offset on the
                // dashboard, so minimizing the player doesn't shift them.
                padding: const EdgeInsets.only(left: 12, right: 12, top: 6),
                child: Row(
                  spacing: 16,
                  mainAxisSize: MainAxisSize.max,
                  // Aligned to the top rather than centred: the logo beside
                  // them is up to a quarter of the screen tall, and centring
                  // in that dragged every button down with it.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_onTelevision)
                      IconButton(
                        onPressed: () => minimizePlayer(context),
                        icon: const Icon(
                          IconsaxPlusLinear.arrow_down_1,
                          size: 24,
                        ),
                      ),
                    if (currentItem != null)
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: maxHeight,
                                ),
                                child: ItemLogo(
                                  item: currentItem,
                                  imageAlignment: Alignment.topLeft,
                                  textStyle: Theme.of(context).textTheme.headlineLarge,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // The pill is shorter than an icon button; give it the
                    // button's height to centre against so the row's trailing
                    // end stays on one line.
                    const SizedBox(height: 48, child: Center(child: SyncPlayBadge())),
                    // Open the SyncPlay group sheet (join/leave, state,
                    // playback-offset trim) without leaving the player. Unique
                    // hero tag so it never clashes with the nav SyncPlay FAB.
                    const SyncPlayButton(),
                    // Hand over the minimize action: once connected, the
                    // player drops to the bottom bar (remote-control mode).
                    CastButton(onConnected: () => leavePlayer(context)),
                    if (initInputDevice == InputDevice.touch)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                            message: context.localized.stop,
                            child: IconButton(
                                onPressed: () => closePlayer(), icon: const Icon(IconsaxPlusLinear.close_square))),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget bottomButtons(BuildContext context) {
    return Consumer(builder: (context, ref, child) {
      final playing = ref.watch(mediaPlaybackProvider.select((state) => state.playing));
      final bitRateOptions = ref.watch(playBackModel.select((value) => value?.bitRateOptions));
      final subLanguage = ref.watch(playBackModel.select((value) {
        final language = value?.mediaStreams?.currentSubStream?.language;
        return language?.isEmpty == true ? context.localized.off : language;
      }))?.capitalize();
      final audioLanguage = ref.watch(playBackModel.select((value) {
        final language = value?.mediaStreams?.currentAudioStream?.language;
        return language?.isEmpty == true ? context.localized.off : language;
      }))?.capitalize();
      final hasPlayer = ref.watch(videoPlayerProvider.select((value) => value.hasPlayer));
      final hasPrevious = ref.watch(playBackModel.select((value) => value?.previousVideo != null));
      final hasNext = ref.watch(playBackModel.select((value) => value?.nextVideo != null));
      final hasEpisodes = ref.watch(playBackModel.select(canBrowseEpisodes));

      final safeArea = MediaQuery.paddingOf(context);
      final viewSize = AdaptiveLayout.viewSizeOf(context);
      final pointer = initInputDevice == InputDevice.pointer || AdaptiveLayout.of(context).isDesktop;
      // A narrow desktop window is not a phone. View size is measured off the
      // window, so it calls one that has been dragged small a phone and used to
      // hide half the row on that basis — how much fits is the budget's job
      // below, and these gates are about the device, so they ask the platform
      // too. On an actual phone the volume keys and a permanently full screen
      // make those two buttons redundant anyway.
      final handheld = viewSize == ViewSize.phone && !AdaptiveLayout.of(context).isDesktop;
      // Wide enough for the track buttons to carry their language.
      final wideLabels = viewSize >= ViewSize.desktop;
      final trackWidth = wideLabels ? _labelledWidth : _iconWidth;

      // Only take room for the episode arrows when there is an episode to go
      // to. On a film they are two dead buttons costing a hundred pixels the
      // row would rather spend on something that works.
      final arrows = (hasPrevious ? 1 : 0) + (hasNext ? 1 : 0);
      final rowWidth = MediaQuery.sizeOf(context).width - safeArea.horizontal - _rowInset;

      // Play/pause is the only button the row will not part with. Everything
      // else, the middle included, bids for the rest in one order of
      // importance, so shrinking the player sheds controls from the bottom of
      // that list up rather than overflowing. Width comes from the media query
      // rather than a LayoutBuilder so the decision happens in the build pass
      // with the rest of the lookups, instead of once more on every layout.
      final row = _ControlBudget(rowWidth - _fixedWidth);

      // The options sheet is the way back to everything the row drops, so it is
      // never dropped itself — and it is charged for even when it did not fit,
      // so the flex below still leaves it room.
      row.takeLeft(_iconWidth, evenIfShort: true);
      // Charged at its collapsed width here; whether the row can afford to
      // unroll it inline is settled at the end, once everything else has had
      // its turn, because the extra width is a luxury and not the control.
      // Shown to a remote as well as to a pointer. It used to be pointer-only,
      // so on a television there was no volume control on screen at all - and
      // nothing to put focus on, whatever the arrows were bound to.
      final showVolume = (pointer || _onTelevision) && !handheld && row.takeRight(_iconWidth);
      final showFullScreen = pointer && !handheld && row.takeRight(_iconWidth);
      final showClose = pointer && row.takeRight(_iconWidth);
      // Both arrows or neither: one of the pair coming and going on its own
      // reads as a glitch rather than a decision.
      final showArrows = arrows > 0 && row.takeMiddle(arrows * (_arrowButton + _rowGap));
      // Ranked under the volume and the arrows: the progress bar already
      // scrubs, and nothing else sets the volume or changes episode.
      final showSkips = row.takeMiddle(_skipButton * 2 + _rowGap * 2);
      // Above the track pickers: jumping to any episode in the show beats
      // choosing a language for the one already playing. Only on a show,
      // though - a film has nothing to browse - and the options sheet keeps
      // it when the row cannot.
      final showEpisodes = hasEpisodes && row.takeLeft(_iconWidth);
      final showSubs = !handheld && row.takeLeft(trackWidth);
      final showAudio = !handheld && row.takeLeft(trackWidth);
      final showQuality = !handheld && bitRateOptions?.isNotEmpty == true && hasPlayer && row.takeRight(_iconWidth);
      final showPip = pipPlatformSupported &&
          !_onTelevision &&
          MediaQuery.orientationOf(context) == Orientation.landscape &&
          row.takeLeft(_iconWidth);

      // Last in line, and the only bid that buys comfort rather than a control:
      // the slider lies down beside its button instead of unrolling on hover.
      final volumeInline = showVolume && row.takeRight(_volumeWidth - _iconWidth);

      final (leftFlex, rightFlex) = row.flex;

      return Container(
        key: _bottomControlsKey,
        decoration: BoxDecoration(
            gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.black.withValues(alpha: 0),
          ],
        )),
        child: Padding(
          padding: MediaQuery.paddingOf(context).add(
            const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 12),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Consumer(
                  builder: (context, ref, child) {
                    final mediaPlayback = ref.watch(mediaPlaybackProvider);
                    return progressBar(mediaPlayback);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    flex: leftFlex,
                    child: Row(
                      children: <Widget>[
                        IconButton(
                            onPressed: () => showVideoPlayerOptions(context, () => leavePlayer(context)),
                            icon: const Icon(IconsaxPlusLinear.more)),
                        if (showEpisodes)
                          IconButton(
                            tooltip: context.localized.episode(2),
                            onPressed: () {
                              resetTimer();
                              showPlayerEpisodes(context, ref);
                            },
                            icon: const Icon(IconsaxPlusLinear.video_vertical),
                          ),
                        if (showPip)
                          IconButton(
                            tooltip: context.localized.pictureInPictureTitle,
                            onPressed: () async {
                              final ok = await ref.read(pipManagerProvider).enter();
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(context.localized.pictureInPictureNotSupported)),
                                );
                              }
                            },
                            icon: const Icon(IconsaxPlusLinear.screenmirroring),
                          ),
                        if (!wideLabels) ...[
                          if (showSubs)
                            IconButton(
                              onPressed: () => showSubSelection(context),
                              icon: const Icon(IconsaxPlusLinear.subtitle),
                            ),
                          if (showAudio)
                            IconButton(
                              onPressed: () => showAudioSelection(context),
                              icon: const Icon(IconsaxPlusLinear.audio_square),
                            ),
                        ] else ...[
                          if (showSubs)
                            Flexible(
                              child: ElevatedButton.icon(
                                onPressed: () => showSubSelection(context),
                                icon: const Icon(IconsaxPlusLinear.subtitle),
                                label: Text(subLanguage ?? "", maxLines: 1),
                              ),
                            ),
                          if (showAudio)
                            Flexible(
                              child: ElevatedButton.icon(
                                onPressed: () => showAudioSelection(context),
                                icon: const Icon(IconsaxPlusLinear.audio_square),
                                label: Text(audioLanguage ?? "", maxLines: 1),
                              ),
                            ),
                        ],
                      ].addInBetween(const SizedBox(
                        width: 4,
                      )),
                    ),
                  ),
                  if (showArrows && hasPrevious) previousButton,
                  if (showSkips) seekBackwardButton(ref),
                  IconButton.filledTonal(
                    focusNode: _playPauseFocus,
                    iconSize: 38,
                    onPressed: () {
                      ref.read(videoPlayerProvider.notifier).userPlayOrPause();
                    },
                    icon: playing ? const Icon(IconsaxPlusBold.pause) : const ChudderPlayIcon(),
                  ),
                  if (showSkips) seekForwardButton(ref),
                  if (showArrows && hasNext) nextVideoButton,
                  Flexible(
                    flex: rightFlex,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (showClose)
                          Tooltip(
                            message: context.localized.stop,
                            child: IconButton(
                              onPressed: () => closePlayer(),
                              icon: const Icon(IconsaxPlusLinear.close_square),
                            ),
                          ),
                        const Spacer(),
                        if (showQuality)
                          Tooltip(
                            message: context.localized.qualityOptionsTitle,
                            child: IconButton(
                              onPressed: () => openQualityOptions(context),
                              icon: const Icon(IconsaxPlusLinear.speedometer),
                            ),
                          ),
                        if (showVolume)
                          Focus(
                            focusNode: _volumeFocus,
                            // Somewhere a remote stops. Landing on it turns up
                            // and down into volume - see [_steer] - and leaves
                            // left and right to carry you off it again.
                            canRequestFocus: _onTelevision,
                            onFocusChange: (_) => setState(() {}),
                            // Ringed like the scrubber: it was the one control
                            // on the bar that gave no sign of being selected.
                            child: FocusRing(
                              visible: _onTelevision && _volumeFocus.hasFocus,
                              // One stop, this node: the mute button and the
                              // slider inside - the unrolled panel's included,
                              // it hangs off this subtree - could take the
                              // selection themselves, and the slider then
                              // kept every arrow for its own steps.
                              child: ExcludeFocus(
                                excluding: _onTelevision,
                                child: VideoVolumeSlider(
                                  // Unrolled for as long as it is the selected
                                  // control; there is no pointer to hover it open.
                                  forceOpen: _onTelevision && _volumeFocus.hasFocus,
                                  // Standing up rather than lying down for a
                                  // remote: it unrolls upward from its button,
                                  // which is the shape the up and down keys mean.
                                  collapsed: _onTelevision || !volumeInline,
                                  onChanged: () => resetTimer(),
                                  onPanelVisible: (open) => _volumePanelOpen = open,
                                ),
                              ),
                            ),
                          ),
                        if (showFullScreen) const FullScreenButton(),
                      ].addInBetween(const SizedBox(width: 8)),
                    ),
                  ),
                ].addInBetween(const SizedBox(width: 6)),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget progressBar(MediaPlaybackModel mediaPlayback) {
    return Consumer(
      builder: (context, ref, child) {
        final playbackModel = ref.watch(playBackModel);
        final item = playbackModel?.item;

        // Where the scrubber is being walked to, whichever way it is being
        // walked. A remote accumulates into [_scrubTarget]; the arrow keys
        // accumulate seconds through the seek indicator, which used to show
        // that total only in its own floating box while the bar and the clock
        // stayed put. Both now move the same way.
        final pendingSeek = ref.watch(pendingSeekSecondsProvider);
        final Duration previewPosition = _scrubTarget ??
            (pendingSeek == 0
                ? mediaPlayback.position
                : Duration(
                    milliseconds: (mediaPlayback.position.inMilliseconds + pendingSeek * 1000)
                        .clamp(0, mediaPlayback.duration.inMilliseconds),
                  ));
        final travelling = _scrubTarget != null || pendingSeek != 0;
        final List<String?> details = [
          if (AdaptiveLayout.of(context).isDesktop) item?.label(context.localized),
          context.localized.endsAt(DateTime.now().add(Duration(
            milliseconds: (mediaPlayback.duration.inMilliseconds - mediaPlayback.position.inMilliseconds) ~/
                ref.read(playbackRateProvider),
          )))
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    details.nonNulls.join(' - '),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                  ),
                ),
                const Spacer(),
                if (playbackModel != null)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => showVideoPlaybackInformation(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          playbackModel.label(context) ?? "",
                        ),
                      ),
                    ),
                  ),
                if (item != null) ...{
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        item.streamModel?.mediaInfoTag ?? "",
                      ),
                    ),
                  ),
                },
              ].addPadding(const EdgeInsets.symmetric(horizontal: 4)),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 33,
              child: Focus(
                focusNode: _scrubberFocus,
                // Only somewhere a remote stops; a pointer scrubs it directly.
                canRequestFocus: _onTelevision,
                // A plain Focus draws nothing, and a bar with no ring round it
                // is the one control you cannot tell is selected. Leaving the
                // bar with a walk pending withdraws the walk: the proposal
                // was the bar's, and OK anywhere else means something else.
                onFocusChange: (focused) {
                  if (!focused) _cancelScrub();
                  setState(() {});
                },
                child: FocusRing(
                  visible: _scrubberFocus.hasFocus,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    // The bar's own slider is a stop of its own on a pad, with
                    // steps of a twentieth; the walk above is the remote's way.
                    child: ExcludeFocus(
                      excluding: _onTelevision,
                      child: VideoProgressBar(
                        wasPlayingChanged: (value) => wasPlaying = value,
                        wasPlaying: wasPlaying,
                        duration: mediaPlayback.duration,
                        // Where it is being walked to while a direction is held, and
                        // the real position otherwise.
                        position: previewPosition,
                        // The preview over the walk: the frame at the target,
                        // the clock, and how far from where the film still is.
                        scrubbing: _scrubTarget != null,
                        scrubDelta: _scrubTarget == null ? null : _scrubTarget! - mediaPlayback.position,
                        // Where the film still is, marked while the bar shows
                        // the walk instead: what Back goes back to.
                        origin: _scrubTarget == null ? null : mediaPlayback.position,
                        remote: _onTelevision,
                        buffer: mediaPlayback.buffer,
                        buffering: mediaPlayback.buffering,
                        timerReset: () => timer.reset(),
                        onPositionChanged: (position) => ref.read(videoPlayerProvider.notifier).userSeek(position),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Where the scrubber has been walked to, not where the video
                // still is: travelling without a clock to read is guesswork.
                Text(
                  previewPosition.readAbleDuration,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: travelling ? FontWeight.bold : null,
                      ),
                ),
                Text(
                  "-${(mediaPlayback.duration - previewPosition).readAbleDuration}",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget get previousButton {
    return Consumer(
      builder: (context, ref, child) {
        final previousVideo = ref.watch(playBackModel.select((value) => value?.previousVideo));
        return Tooltip(
          message: previousVideo?.detailedName(context.localized) ?? "",
          textAlign: TextAlign.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge,
          child: IconButton(
            onPressed: loadPreviousVideo(ref, video: previousVideo),
            iconSize: 30,
            icon: const Icon(
              IconsaxPlusLinear.backward,
            ),
          ),
        );
      },
    );
  }

  Function()? loadPreviousVideo(WidgetRef ref, {ItemBaseModel? video}) {
    final previousVideo = video ?? ref.read(playBackModel.select((value) => value?.previousVideo));
    final buffering = ref.read(mediaPlaybackProvider.select((value) => value.buffering));
    return previousVideo != null && !buffering ? () => ref.read(playbackModelHelper).loadNewVideo(previousVideo) : null;
  }

  Widget get nextVideoButton {
    return Consumer(
      builder: (context, ref, child) {
        final nextVideo = ref.watch(playBackModel.select((value) => value?.nextVideo));
        return Tooltip(
          message: nextVideo?.detailedName(context.localized) ?? "",
          textAlign: TextAlign.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge,
          child: IconButton(
            onPressed: loadNextVideo(ref, video: nextVideo),
            iconSize: 30,
            icon: const Icon(
              IconsaxPlusLinear.forward,
            ),
          ),
        );
      },
    );
  }

  Function()? loadNextVideo(WidgetRef ref, {ItemBaseModel? video}) {
    final nextVideo = video ?? ref.read(playBackModel.select((value) => value?.nextVideo));
    final buffering = ref.read(mediaPlaybackProvider.select((value) => value.buffering));
    return nextVideo != null && !buffering ? () => ref.read(playbackModelHelper).loadNewVideo(nextVideo) : null;
  }

  Widget seekBackwardButton(WidgetRef ref) {
    final backwardSpeed =
        ref.read(userProvider.select((value) => value?.userSettings?.skipBackDuration.inSeconds ?? 30));
    return IconButton(
      onPressed: () => seekBack(ref, seconds: backwardSpeed),
      tooltip: "-$backwardSpeed",
      iconSize: 40,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            IconsaxPlusBroken.refresh,
            size: 45,
          ),
          Transform.translate(
            offset: const Offset(0, 1),
            child: Text(
              "-$backwardSpeed",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget seekForwardButton(WidgetRef ref) {
    final forwardSpeed =
        ref.read(userProvider.select((value) => value?.userSettings?.skipForwardDuration.inSeconds ?? 30));
    return IconButton(
      onPressed: () => seekForward(ref, seconds: forwardSpeed),
      tooltip: forwardSpeed.toString(),
      iconSize: 40,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(
            flipX: true,
            child: const Icon(
              IconsaxPlusBroken.refresh,
              size: 45,
            ),
          ),
          Transform.translate(
            offset: const Offset(0, 1),
            child: Text(
              forwardSpeed.toString(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  void skipToSegmentEnd(MediaSegment? mediaSegment, String? segmentId) {
    final end = mediaSegment?.end;
    if (end != null) {
      resetTimer();
      ref.read(videoPlayerProvider.notifier).userSeek(end);

      if (segmentId != null) {
        Future(() {
          final currentSkipped = ref.read(mediaPlaybackProvider).skippedSegments;
          ref.read(mediaPlaybackProvider.notifier).update(
                (state) => state.copyWith(
                  skippedSegments: {...currentSkipped, segmentId},
                ),
              );
        });
      }
    }
  }

  void seekBack(WidgetRef ref, {int seconds = 15}) {
    _seek(ref, -seconds);
  }

  void seekForward(WidgetRef ref, {int seconds = 15}) {
    _seek(ref, seconds);
  }

  void _seek(WidgetRef ref, int seconds) {
    final mediaPlayback = ref.read(mediaPlaybackProvider);
    resetTimer();
    final newPosition = (mediaPlayback.position.inSeconds + seconds).clamp(0, mediaPlayback.duration.inSeconds);
    ref.read(videoPlayerProvider.notifier).userSeek(Duration(seconds: newPosition));
  }

  void stepBack(WidgetRef ref) {
    _step(ref, -1);
  }

  void stepForward(WidgetRef ref) {
    _step(ref, 1);
  }

  void _step(WidgetRef ref, int frames) {
    final mediaPlayback = ref.read(mediaPlaybackProvider);
    final framerate = ref.read(playBackModel.select((value) => value?.mediaStreams?.videoStreams.first.frameRate));
    if (framerate == null || framerate == 0) return;

    final step = ((1000000.0 / framerate) * frames).round();
    resetTimer();
    final newPosition = (mediaPlayback.position.inMicroseconds + step).clamp(0, mediaPlayback.duration.inMicroseconds);
    ref.read(videoPlayerProvider).seek(Duration(microseconds: newPosition));
  }

  void seekBackWithIndicator() {
    _seekController.seekBack();
  }

  void seekForwardWithIndicator() {
    _seekController.seekForward();
  }

  /// Whether the app is running on a television.
  ///
  /// A television has no small player. Minimising into a bar or a floating
  /// window, and picture-in-picture, are both answers to "I want to do
  /// something else with this screen" - which is a thing you do at a desk and
  /// not from a sofa. Judged on where the app is running rather than on what is
  /// being held, so a desktop keeps them the moment an arrow key is used.
  /// Whether the player is being driven from a sofa: a television build, or
  /// any device whose input is a pad. A pad is what makes the sofa the sofa -
  /// no pointer to hover the volume open with, no way to reach a minimized
  /// window - so a controller on a desktop gets the television's controls too.
  bool get _onTelevision =>
      ref.watch(argumentsStateProvider.select((value) => value.htpcMode || value.leanBackMode)) ||
      AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

  /// Whether [event] is a press on a remote's pad.
  bool _isRemoteKey(KeyEvent event) =>
      (event is KeyDownEvent || event is KeyRepeatEvent) &&
      (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter);

  /// What a remote press means, given where the controls and focus are.
  ///
  /// A press is only ever spent when it has something to do: seeking, waking
  /// the controls, or landing focus on them. Once focus is genuinely on a
  /// control the press belongs to traversal and this stands out of the way.
  KeyEventResult _handleRemoteKey(InputDevice input, KeyEvent event) {
    // Only a remote. At a keyboard the arrows are volume and seek, and taking
    // the first press to wake the controls would cost a volume step every time
    // they had timed out.
    if (input != InputDevice.dPad) return KeyEventResult.ignored;

    // The next-episode card owns the pad while it is up. Without this the very
    // first branch below spends every press waking the controls - which are
    // timed out by then, since that is when the card appears - and drags focus
    // off the card in the process, so its buttons can never be reached.
    if (ref.read(nextUpVisibleProvider)) return KeyEventResult.ignored;

    // Back while the scrubber is walked abandons the walk, and only that: the
    // player stays. Caught before the exit shortcut and the route can see it.
    if (_scrubTarget != null && _isBackKey(event)) {
      _cancelScrub();
      return KeyEventResult.handled;
    }

    // A digit on a remote that has them jumps to a tenth of the film.
    if (event is KeyDownEvent && _digitOf(event.logicalKey) != null) {
      return _scrubToTenth(event, ref.read(mediaPlaybackProvider));
    }

    if (!_isRemoteKey(event)) return KeyEventResult.ignored;

    // Asked of the focus tree, not of the scope's memory:
    // [FocusScopeNode.focusedChild] stays set to whatever was last focused
    // inside it even while the scope is nowhere near the focus chain. Reading
    // that as "focus is here" was true almost always, so every press was spent
    // putting focus where it already was and none of them reached traversal.
    final primary = FocusManager.instance.primaryFocus;
    final onAControl = primary != null && _controlsScope.descendants.contains(primary);

    // With nothing on screen, left and right are seeking - which the seek
    // indicator has already done by now, from the raw keyboard. Spent here
    // only so they do not also wake the controls: up, down and select are
    // what bring those up, and from then on left and right walk them.
    if (!showOverlay &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      return KeyEventResult.handled;
    }

    if (!showOverlay) {
      toggleOverlay(value: true);
      _focusControls();
      return KeyEventResult.handled;
    }

    if (!onAControl) {
      // Up, but nothing on them holds focus - so this press lands it.
      _focusControls();
      return KeyEventResult.handled;
    }

    // On a control that steers, the press is its own.
    final steered = _steer(event, ref.read(mediaPlaybackProvider));
    if (steered != KeyEventResult.ignored) return steered;

    // Otherwise it belongs to traversal. Hold the controls open while they are
    // being used.
    timer.reset();
    return KeyEventResult.ignored;
  }

  /// Walks the scrubber, and commits once the pressing stops.
  KeyEventResult _scrub(bool forward, KeyEvent event, MediaPlaybackModel playback) {
    // Nothing to walk yet - the stream is still opening - and a walk over
    // nothing would put the preview at a share of zero.
    if (playback.duration <= Duration.zero) return KeyEventResult.handled;
    final from = _scrubTarget ?? playback.position;
    final step = _scrubRamp.step(
      forward: forward,
      repeat: event is KeyRepeatEvent,
      now: event.timeStamp,
      total: playback.duration,
    );
    _scrubTo(from + step, playback);
    return KeyEventResult.handled;
  }

  /// Parks the scrubber at [target], shown but not sought until OK.
  void _scrubTo(Duration target, MediaPlaybackModel playback) {
    setState(() {
      _scrubTarget = Duration(
        milliseconds: target.inMilliseconds.clamp(0, playback.duration.inMilliseconds),
      );
    });
    timer.reset();
  }

  /// Seeks to where the scrubber was walked to: OK was pressed on it.
  void _commitScrub() {
    _scrubRamp.reset();
    final target = _scrubTarget;
    if (!mounted || target == null) return;
    ref.read(videoPlayerProvider.notifier).userSeek(target);
    setState(() => _scrubTarget = null);
  }

  /// Abandons the walk: the bar and the preview snap back to where the film
  /// still is, and nothing is sought.
  void _cancelScrub() {
    _scrubRamp.reset();
    if (!mounted || _scrubTarget == null) return;
    setState(() => _scrubTarget = null);
    timer.reset();
  }

  /// A digit is a tenth of the runtime: 0 is the start, 5 the middle, 9 near
  /// the end. Walked to like a hold - shown, and sought on OK - so a wrong
  /// digit can be corrected before it takes.
  KeyEventResult _scrubToTenth(KeyEvent event, MediaPlaybackModel playback) {
    final tenth = _digitOf(event.logicalKey);
    if (tenth == null || playback.duration <= Duration.zero) return KeyEventResult.ignored;
    if (!showOverlay) toggleOverlay(value: true);
    if (!_scrubberFocus.hasFocus && _scrubberFocus.canRequestFocus) _scrubberFocus.requestFocus();
    _scrubRamp.reset();
    _scrubTo(playback.duration * tenth ~/ 10, playback);
    return KeyEventResult.handled;
  }

  static int? _digitOf(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    final index = digits.indexOf(key);
    if (index != -1) return index;
    final pad = numpad.indexOf(key);
    return pad != -1 ? pad : null;
  }

  static bool _isBackKey(KeyEvent event) =>
      event is KeyDownEvent &&
      (event.logicalKey == LogicalKeyboardKey.goBack ||
          event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.backspace);

  /// The control that currently has focus takes one axis for itself.
  ///
  /// The scrubber steers with left and right, the volume with up and down, and
  /// in both cases the other axis is left alone so it can still carry you off
  /// the control. Nothing else on the row wants an axis, so nothing else is
  /// asked about.
  KeyEventResult _steer(KeyEvent event, MediaPlaybackModel playback) {
    final key = event.logicalKey;

    if (_scrubberFocus.hasFocus) {
      if (key == LogicalKeyboardKey.arrowRight) return _scrub(true, event, playback);
      if (key == LogicalKeyboardKey.arrowLeft) return _scrub(false, event, playback);
      // OK on a walked scrubber is what seeks.
      if ((key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) &&
          event is KeyDownEvent &&
          _scrubTarget != null) {
        _commitScrub();
        return KeyEventResult.handled;
      }
    }

    if (_volumeFocus.hasFocus) {
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        ref.read(videoPlayerSettingsProvider.notifier).steppedVolume(key == LogicalKeyboardKey.arrowUp ? 5 : -5);
        timer.reset();
        return KeyEventResult.handled;
      }
      // The mute button under the ring is out of the pad's reach - see the
      // ExcludeFocus round it - so OK on the control is what presses it.
      if ((key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) && event is KeyDownEvent) {
        _onKey(VideoHotKeys.mute);
        timer.reset();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Whether the player is the topmost route, rather than sitting under a
  /// dialog. Focus must never be moved onto the player while it is covered.
  bool get _routeIsCurrent => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  /// Puts focus on a control once the controls are on screen.
  void _focusControls() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !showOverlay || !_routeIsCurrent) return;

      // Back where you were if that is still possible; play/pause the first
      // time, since that is the control anybody is looking for; and only
      // failing both, whatever traversal finds first.
      final remembered = _controlsScope.focusedChild;
      if (remembered != null && remembered.canRequestFocus) {
        remembered.requestFocus();
        return;
      }
      if (_playPauseFocus.canRequestFocus && _playPauseFocus.context != null) {
        _playPauseFocus.requestFocus();
        return;
      }
      _controlsScope.nextFocus();
    });
  }

  void toggleOverlay({bool? value}) {
    // The volume panel floats in the app's overlay, above the chrome, so the
    // pointer moving onto it reads to this widget as the pointer leaving the
    // player entirely. Hiding on that took the panel down with it, which put
    // the pointer back over the video, which brought everything back — the
    // flicker. Hold instead, the way any other control holds while hovered.
    if (value == false && _volumePanelOpen) {
      resetTimer();
      return;
    }
    if (showOverlay == (value ?? !showOverlay)) return;
    setState(() => showOverlay = (value ?? !showOverlay));

    // Said out loud: the seek indicator listens to the raw keyboard, which runs
    // before focus is consulted, so it has to stand aside while these are being
    // navigated. See [playerControlsVisibleProvider].
    Future.microtask(() {
      if (mounted) _controlsVisible.state = showOverlay;
    });

    if (!showOverlay && _routeIsCurrent) _playerFocus.requestFocus();
    resetTimer();

    final desiredMode = showOverlay ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky;

    if (_currentSystemUiMode != desiredMode) {
      _currentSystemUiMode = desiredMode;
      SystemChrome.setEnabledSystemUIMode(desiredMode, overlays: []);
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  /// Back, Escape and the exit shortcut. A desk keeps the film going in a
  /// small player. A television has nowhere to put one - the d-pad cannot
  /// reach the floating window or the bar, so a film minimized from the sofa
  /// could not be paused or stopped again - so leaving the player there stops
  /// the film outright.
  void leavePlayer(BuildContext context) {
    final onTelevision = ref.read(argumentsStateProvider.select((value) => value.htpcMode || value.leanBackMode)) ||
        AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    if (onTelevision) {
      closePlayer();
    } else {
      minimizePlayer(context);
    }
  }

  void minimizePlayer(BuildContext context) {
    clearOverlaySettings();
    ref.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
    ref.read(mediaPlaybackProvider.notifier).update(
          (state) => state.copyWith(state: VideoPlayerState.minimized),
        );
    Navigator.of(context).pop();
  }

  void resetTimer() => timer.reset();

  Future<void> closePlayer() async {
    clearOverlaySettings();
    // Mark the route as closed immediately so that a SyncPlay
    // _startPlayback call arriving during the pop animation knows
    // it must push a new route.
    ref.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
    // Fire-and-forget the stop. The wrapper's stop() chain reports the
    // session to the server (POST /Sessions/Playing/Stopped, ~2s) and
    // we don't want the user staring at a black player with live
    // controls during that time. Awaiting it would also reach `ref`
    // after the widget is disposed by the route pop, throwing.
    ref.read(videoPlayerProvider).stop();
    if (ref.read(isSyncPlayActiveProvider)) {
      // In SyncPlay we previously only paused, which left the floating
      // mini-player visible and let a server-broadcast Unpause resume
      // local playback in the background. Null out the playback model
      // so the mini-player disappears; the user can re-attach via the
      // SyncPlay sheet's "Resume Playback" button.
      ref.read(playBackModel.notifier).update((_) => null);
    }
    Navigator.of(context).pop();
  }

  Future<void> clearOverlaySettings() async {
    toggleOverlay(value: true);
    if (initInputDevice != InputDevice.pointer) {
      ScreenBrightness().resetApplicationScreenBrightness();
    } else {
      disableFullScreen();
    }

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarIconBrightness: ref.read(clientSettingsProvider.select((value) => value.statusBarBrightness(context))),
    ));

    timer.cancel();
  }

  Future<void> disableFullScreen() async {
    resetTimer();
    if (AdaptiveLayout.of(context).isDesktop && defaultTargetPlatform != TargetPlatform.macOS) {
      fullScreenHelper.closeFullScreen(ref);
    }
  }

  void setVolume(PointerEvent event) {
    if (event is PointerScrollEvent) {
      if (event.scrollDelta.dy > 0) {
        ref.read(videoPlayerSettingsProvider.notifier).steppedVolume(-5);
      } else {
        ref.read(videoPlayerSettingsProvider.notifier).steppedVolume(5);
      }
    }
  }

  void _activateSpeedBoost() {
    if (_speedBoostActive) return;

    final settings = ref.read(videoPlayerSettingsProvider);
    if (!settings.enableSpeedBoost) return;

    _originalSpeed = ref.read(playbackRateProvider);
    _speedBoostActive = true;
    ref.read(videoPlayerProvider).setSpeed(settings.speedBoostRate);
    ref.read(playbackRateProvider.notifier).state = settings.speedBoostRate;
  }

  void _deactivateSpeedBoost() {
    if (!_speedBoostActive) return;

    _speedBoostActive = false;
    if (_originalSpeed != null) {
      // Through the container, not `ref`: this also runs from [dispose].
      _container.read(videoPlayerProvider).setSpeed(_originalSpeed!);
      _container.read(playbackRateProvider.notifier).state = _originalSpeed!;
      _originalSpeed = null;
    }
  }

  // --- Keyboard Speed Boost Handler (Desktop) ---

  KeyEventResult _handleSpacebarEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      return KeyEventResult.handled;
    } else if (event is KeyRepeatEvent) {
      final isPlaying = ref.read(mediaPlaybackProvider.select((value) => value.playing));
      if (isPlaying) {
        _activateSpeedBoost();
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      if (_speedBoostActive) {
        _deactivateSpeedBoost();
      } else {
        ref.read(videoPlayerProvider.notifier).userPlayOrPause();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Touch Gesture Handlers (Mobile) ---

  void _handleDoubleTapDown(TapDownDetails details) {
    final doubleTapSeekEnabled = ref.read(videoPlayerSettingsProvider.select((value) => value.enableDoubleTapSeek));
    if (doubleTapSeekEnabled) {
      _doubleTapPosition = details.globalPosition;
    }
  }

  void _handleDoubleTapSeek() {
    final doubleTapSeekEnabled = ref.read(videoPlayerSettingsProvider.select((value) => value.enableDoubleTapSeek));
    if (!doubleTapSeekEnabled) return;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final tapX = _doubleTapPosition?.dx ?? screenWidth / 2;
    final zoneThird = screenWidth / 3;

    if (tapX < zoneThird) {
      seekBackWithIndicator();
    } else if (tapX > zoneThird * 2) {
      seekForwardWithIndicator();
    } else {
      ref.read(videoPlayerProvider.notifier).userPlayOrPause();
    }
    _doubleTapPosition = null;
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    final settings = ref.read(videoPlayerSettingsProvider);
    final isPlaying = ref.read(mediaPlaybackProvider.select((value) => value.playing));
    if (settings.enableSpeedBoost && isPlaying) {
      _activateSpeedBoost();
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _deactivateSpeedBoost();
  }

  Future<void> _handleVerticalDragStart(DragStartDetails details) async {
    final settings = ref.read(videoPlayerSettingsProvider);
    if (!settings.enableEdgeGestures) return;

    final size = MediaQuery.sizeOf(context);
    final y = details.localPosition.dy;
    // Safety margin of 10% top/bottom to avoid accidental system gestures (notification tray, home bar)
    if (y < size.height * 0.1 || y > size.height * 0.9) {
      _vDragSide = null;
      return;
    }

    final isLeft = details.localPosition.dx < size.width / 2;
    final isBrightness = settings.reverseEdgeGestures ? !isLeft : isLeft;

    _vDragSide = isBrightness ? 'brightness' : 'volume';

    if (isBrightness) {
      _vDragStartValue = settings.screenBrightness ?? 1.0;
    } else {
      final currentVolume = ({TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform))
          ? (await VolumeController.instance.getVolume())
          : settings.volume / 100;
      _vDragStartValue = currentVolume;
    }
    _vDragLastValue = _vDragStartValue;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_vDragSide == null || _vDragStartValue == null) return;

    final screenHeight = MediaQuery.sizeOf(context).height;
    // Slide up to increase, down to decrease.
    // details.delta.dy is positive when sliding down.
    final delta = -details.primaryDelta! / (screenHeight * 0.7); // 70% of screen height for full range
    final newValue = (_vDragLastValue! + delta).clamp(0.0, 1.0);

    if (newValue == _vDragLastValue) return;
    _vDragLastValue = newValue;

    if (_vDragSide == 'brightness') {
      ref.read(videoPlayerSettingsProvider.notifier).setScreenBrightness(newValue);
    } else {
      ref.read(videoPlayerSettingsProvider.notifier).setVolume(newValue * 100);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    _vDragSide = null;
    _vDragStartValue = null;
    _vDragLastValue = null;
  }

  Timer? _clickToggle;

  /// A click on the video toggles playback - on the way down, so a click
  /// that turns into a drag still counts. On a Mac trackpad the fingers
  /// landing for a two-finger swipe can register as a tap-to-click first,
  /// which paused or resumed the film on every swipe back. There the toggle
  /// waits a moment and stands down if a trackpad gesture has begun.
  void _clickPlayPause() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      ref.read(videoPlayerProvider.notifier).userPlayOrPause();
      return;
    }
    _clickToggle?.cancel();
    _clickToggle = Timer(const Duration(milliseconds: 120), () {
      _clickToggle = null;
      if (!mounted) return;
      if (TrackpadNavigation.gestureBeganWithin(const Duration(milliseconds: 500))) return;
      ref.read(videoPlayerProvider.notifier).userPlayOrPause();
    });
  }

  void _toggleSubtitles() {
    final playbackModel = ref.read(playBackModel);
    final player = ref.read(videoPlayerProvider);
    final subStreams = playbackModel?.subStreams;

    if (subStreams == null || subStreams.isEmpty) return;

    // Filter out the "off" track (index == -1)
    final availableSubtitles = subStreams.where((s) => s.index != -1).toList();
    if (availableSubtitles.isEmpty) return;

    final currentIndex = playbackModel?.mediaStreams?.defaultSubStreamIndex ?? -1;
    if (currentIndex != -1) {
      // Subtitles are ON -> Turn OFF and remember this index
      _lastSelectedSubtitleIndex = currentIndex;
      _setSubtitleTrack(SubStreamModel.no(), playbackModel, player);
    } else {
      // Subtitles are OFF -> Turn ON
      if (_lastSelectedSubtitleIndex != null) {
        // Use the last selected index
        final lastSub = subStreams.firstWhere(
          (s) => s.index == _lastSelectedSubtitleIndex,
          orElse: () => availableSubtitles.first,
        );
        _setSubtitleTrack(lastSub, playbackModel, player);
      } else if (availableSubtitles.length == 1) {
        // If only one subtitle is available, just use it
        _setSubtitleTrack(availableSubtitles.first, playbackModel, player);
      } else {
        // Multiple subtitles and no last selection -> Show selection dialog
        showSubSelection(context).then((_) {
          final newModel = ref.read(playBackModel);
          final selectedIndex = newModel?.mediaStreams?.defaultSubStreamIndex;
          if (selectedIndex != null && selectedIndex != -1) {
            _lastSelectedSubtitleIndex = selectedIndex;
          }
        });
      }
    }
  }

  void _setSubtitleTrack(SubStreamModel subModel, PlaybackModel? playbackModel, dynamic player) async {
    if (playbackModel == null) return;
    final newModel = await playbackModel.setSubtitle(subModel, player);
    ref.read(playBackModel.notifier).update((state) => newModel);
    if (newModel != null) {
      await ref.read(playbackModelHelper).shouldReload(newModel);
    }
  }

  bool _onKey(VideoHotKeys value) {
    final mediaSegments = ref.read(playBackModel.select((value) => value?.mediaSegments));
    final position = ref.read(mediaPlaybackProvider).position;
    final playing = ref.read(mediaPlaybackProvider.select((value) => value.playing));

    MediaSegment? segment = mediaSegments?.atPosition(position);

    final volume = ref.read(videoPlayerSettingsProvider.select((value) => value.volume));

    switch (value) {
      case VideoHotKeys.playPause:
        if (_speedBoostActive) {
          return false;
        }
        ref.read(videoPlayerProvider.notifier).userPlayOrPause();
        return true;
      case VideoHotKeys.volumeUp:
        resetTimer();
        ref.read(videoPlayerSettingsProvider.notifier).steppedVolume(5);
        return true;
      case VideoHotKeys.volumeDown:
        resetTimer();
        ref.read(videoPlayerSettingsProvider.notifier).steppedVolume(-5);
        return true;
      case VideoHotKeys.speedUp:
        resetTimer();
        ref.read(videoPlayerSettingsProvider.notifier).steppedSpeed(0.1);
        return true;
      case VideoHotKeys.speedDown:
        resetTimer();
        ref.read(videoPlayerSettingsProvider.notifier).steppedSpeed(-0.1);
        return true;
      case VideoHotKeys.fullScreen:
        fullScreenHelper.toggleFullScreen(ref);
        return true;
      case VideoHotKeys.skipMediaSegment:
        if (segment != null) {
          skipToSegmentEnd(segment, null);
        }
        return true;
      case VideoHotKeys.exit:
        if (ModalRoute.of(context)?.isCurrent == true) {
          leavePlayer(context);
          return true;
        }
        return false;

      case VideoHotKeys.mute:
        if (volume != 0) {
          previousVolume = volume;
        }
        ref.read(videoPlayerSettingsProvider.notifier).setVolume(volume == 0 ? (previousVolume ?? 100) : 0);
        return true;
      case VideoHotKeys.nextVideo:
        loadNextVideo(ref)?.call();
        return true;
      case VideoHotKeys.prevVideo:
        loadPreviousVideo(ref)?.call();
        return true;
      case VideoHotKeys.nextChapter:
        ref.read(videoPlayerSettingsProvider.notifier).nextChapter();
        return true;
      case VideoHotKeys.prevChapter:
        ref.read(videoPlayerSettingsProvider.notifier).prevChapter();
        return true;
      case VideoHotKeys.toggleSubtitles:
        _toggleSubtitles();
        return true;
      case VideoHotKeys.seekForwardInstant:
        final seekForwardSeconds =
            ref.read(userProvider.select((value) => value?.userSettings?.skipForwardDuration.inSeconds ?? 30));
        seekForward(ref, seconds: seekForwardSeconds);
        return true;
      case VideoHotKeys.seekBackInstant:
        final seekBackSeconds =
            ref.read(userProvider.select((value) => value?.userSettings?.skipBackDuration.inSeconds ?? 30));
        seekBack(ref, seconds: seekBackSeconds);
        return true;
      case VideoHotKeys.stepForward:
        playing ? ref.read(videoPlayerProvider.notifier).userPlayOrPause() : stepForward(ref);
        return true;
      case VideoHotKeys.stepBack:
        playing ? ref.read(videoPlayerProvider.notifier).userPlayOrPause() : stepBack(ref);
        return true;
      default:
        return false;
    }
  }
}

/// What the row owes before anything optional: play/pause, and the gaps either
/// side of it that separate it from the two flanking groups. Everything else is
/// measured against what this leaves behind, and pays for its own gap as it
/// goes.
const _fixedWidth = _playButton + 2 * _rowGap;

/// The play button, drawn at 38 inside a filled tonal button.
const _playButton = 54.0;

/// A skip button. Wider than it was asked for: the icon is drawn at 45 rather
/// than the 40 the button set.
const _skipButton = 61.0;

/// A previous- or next-episode button.
const _arrowButton = 48.0;

/// The gap the row puts between each of its children.
const _rowGap = 6.0;

/// The horizontal padding the bottom bar puts around its own contents, on top
/// of whatever the safe area already claims.
const _rowInset = 32.0;

/// An icon button plus the gap that follows it.
const _iconWidth = 56.0;

/// The mute button with its slider and readout lying down beside it.
const _volumeWidth = 183.0;

/// A track button wide enough to spell out the language it selected.
const _labelledWidth = 130.0;

/// Hands out the bottom bar's spare width to the optional controls, most
/// important first. Once it runs dry every later take refuses, so the row drops
/// its least useful buttons instead of overflowing. Which side each button
/// lands on is tracked as it goes, because that is what decides how the row
/// divides the space between the two flanking groups.
class _ControlBudget {
  _ControlBudget(this.remaining) : _flanks = remaining;

  /// What the two flanking groups have to share, before the middle takes its
  /// cut.
  final double _flanks;

  double remaining;
  double _left = 0;
  double _right = 0;
  double _middle = 0;

  bool takeLeft(double width, {bool evenIfShort = false}) {
    if (!_take(width, evenIfShort)) return false;
    _left += width;
    return true;
  }

  bool takeRight(double width) {
    if (!_take(width, false)) return false;
    _right += width;
    return true;
  }

  bool takeMiddle(double width) {
    if (!_take(width, false)) return false;
    _middle += width;
    return true;
  }

  bool _take(double width, bool evenIfShort) {
    if (remaining < width && !evenIfShort) return false;
    remaining -= width;
    return true;
  }

  /// Equal flex keeps the play button dead centre, which is worth having while
  /// both flanks fit in half of what is left to them. Only once one of them has
  /// outgrown its half does the split follow what each is holding — a play
  /// button a little off centre beats a button that isn't there. Floored at
  /// one, because a flex of zero is not "no room" but "unconstrained", and
  /// would hand the group unbounded width to overflow into.
  (int, int) get flex {
    final half = (_flanks - _middle) / 2;
    if (_left <= half && _right <= half) return (1, 1);
    return (_left.round().clamp(1, 1 << 20), _right.round().clamp(1, 1 << 20));
  }
}
