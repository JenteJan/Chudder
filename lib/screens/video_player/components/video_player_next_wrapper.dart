import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/pip_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/player_controls_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/screens/shared/default_title_bar.dart';
import 'package:fladder/screens/video_player/components/cast_button.dart';
import 'package:fladder/screens/video_player/components/video_player_options_sheet.dart';
import 'package:fladder/screens/video_player/components/video_progress_bar.dart';
import 'package:fladder/screens/video_player/components/video_volume_slider.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/duration_extensions.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/shared/player_bar_shared.dart';
import 'package:fladder/widgets/shared/pip_next_up_strip.dart';
import 'package:fladder/widgets/shared/progress_floating_button.dart';
import 'package:fladder/widgets/syncplay/syncplay_badge.dart';
import 'package:fladder/widgets/syncplay/syncplay_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';

class VideoPlayerNextWrapper extends ConsumerStatefulWidget {
  final Widget video;
  final Widget controls;
  final List<Widget> overlays;

  const VideoPlayerNextWrapper({
    required this.video,
    required this.controls,
    this.overlays = const [],
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _VideoPlayerNextWrapperState();
}

class _VideoPlayerNextWrapperState extends ConsumerState<VideoPlayerNextWrapper> {
  bool show = false;
  bool showOverwrite = false;

  /// The next-up card's own focus scope.
  ///
  /// The card is never removed from the tree - only faded - so the autofocus on
  /// its play button fires once, at player start, while the card is invisible,
  /// and never again when it actually appears. Focus has to be put there by
  /// hand each time instead.
  final FocusScopeNode _nextUpScope = FocusScopeNode(debugLabel: 'nextUp');
  late RestartableTimerController timerController =
      RestartableTimerController(const Duration(seconds: 30), const Duration(milliseconds: 33), onTimeout: onTimeOut);

  // Resolved in [initState] rather than lazily: [dispose] reads it, and a
  // lazy initializer firing there would touch `ref` after the widget is gone.
  late final StateController<VoidCallback?> nextUpAction;
  bool mediaButtonActionPublished = false;

  /// Marks the next-up thumbnail so the new episode can be animated out of it.
  final GlobalKey nextUpPosterKey = GlobalKey();

  /// Set while the new episode's artwork expands from the thumbnail to fill
  /// the player, covering the outgoing episode until it has been swapped out.
  _PopOut? popOut;

  /// [determineShow] runs from a provider listener that keeps firing after the
  /// player is gone, and `mounted` still reads true while riverpod's element is
  /// already disposed - so track it ourselves rather than throwing once per
  /// position tick and drowning the crash log.
  bool disposed = false;

  /// Offers `onTimeOut` to the hardware media button while the card is up, so
  /// a headphone/keyboard play press starts the next item.
  ///
  /// Written straight through rather than deferred: [determineShow] runs from
  /// a provider listener, so there is no build in progress, and a deferred
  /// write can be overtaken by the button press it exists to serve.
  void publishMediaButtonAction(bool visible) {
    if (visible == mediaButtonActionPublished) return;
    mediaButtonActionPublished = visible;
    try {
      nextUpAction.state = visible ? onTimeOut : null;
    } catch (_) {
      // ProviderContainer may already be torn down.
    }
  }

  void onTimeOut() {
    timerController.cancel();
    if (showOverwrite == true) return;
    final nextUp = ref.read(playBackModel.select((value) => value?.nextVideo));
    if (nextUp != null) {
      startPopOut(nextUp);
      ref.read(playbackModelHelper).loadNewVideo(nextUp);
    }
    hideNextUp();
  }

  /// Measures the next-up thumbnail and hands it to the pop-out overlay.
  ///
  /// Without this the shrunken player simply grows back, which reads as the
  /// episode that just finished carrying on rather than a new one starting.
  void startPopOut(ItemBaseModel nextUp) {
    final poster = nextUpPosterKey.currentContext?.findRenderObject() as RenderBox?;
    final self = context.findRenderObject() as RenderBox?;
    if (poster == null || self == null || !poster.hasSize || !self.hasSize) return;

    final origin = self.globalToLocal(poster.localToGlobal(Offset.zero));
    setState(() => popOut = _PopOut(rect: origin & poster.size, item: nextUp));
  }

  void showNextScreen(MediaPlaybackModel model) {
    final nextUp = ref.read(playBackModel.select((value) => value?.nextVideo));
    if (nextUp == null) return;
    if (show) return;
    if (showOverwrite) return;
    if (!model.playing) return;
    if (model.buffering) return;

    setState(() {
      show = true;
      timerController.reset();
      timerController.play();
    });
    publishMediaButtonAction(true);
    _landFocusOnCard();
  }

  /// Moves the selection onto the card once it is on screen and focusable.
  ///
  /// Deferred a frame: until the rebuild lands the card is still excluded from
  /// traversal, and asking an excluded scope for its next node finds nothing.
  void _landFocusOnCard() {
    if (!ref.read(argumentsStateProvider).htpcMode && !ref.read(argumentsStateProvider).leanBackMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !show) return;
      if (_nextUpScope.focusedChild != null) return;
      _nextUpScope.nextFocus();
    });
  }

  void determineShow(MediaPlaybackModel model) {
    // Runs from a provider listener, not from build, so `ref` is off limits -
    // watching here threw on every position tick once the player was gone,
    // filling the crash log. The state wanted is already on the model the
    // listener was handed.
    if (disposed || !mounted) return;
    final playerState = model.state;
    // The full next-up card in a picture-in-picture window is a postage
    // stamp of unusable UI; the PiP next action (and the compact strip)
    // cover it there.
    final inPip = ref.read(pipStateProvider).asData?.value ?? false;
    if (playerState != VideoPlayerState.fullScreen || inPip) {
      // setState, not bare assignment: entering PiP triggers no other
      // rebuild, so a card that was already up stayed painted in the
      // tiny window.
      if (show || showOverwrite) {
        setState(() {
          showOverwrite = false;
          show = false;
        });
      }
      publishMediaButtonAction(false);
      return;
    }

    final nextType = ref.read(videoPlayerSettingsProvider.select((value) => value.nextVideoType));
    if (nextType == AutoNextType.off || model.duration < const Duration(seconds: 40)) {
      showOverwrite = false;
      show = false;
      publishMediaButtonAction(false);
      return;
    }

    final credits = ref.read(playBackModel)?.mediaSegments?.outro;

    if (nextType == AutoNextType.static || credits == null) {
      if ((model.duration - model.position).abs() < const Duration(seconds: 32)) {
        showNextScreen(model);
        return;
      }
    } else if (nextType == AutoNextType.smart) {
      final maxTime = ref.read(userProvider.select((value) => value?.serverConfiguration?.maxResumePct ?? 90));
      final resumeDuration = model.duration * (maxTime / 100);
      final timeLeft = model.duration - credits.end;
      if (credits.end > resumeDuration && timeLeft < const Duration(seconds: 30)) {
        if (model.position >= credits.start) {
          showNextScreen(model);
          return;
        }
      } else if ((model.duration - model.position).abs() < const Duration(seconds: 32)) {
        showNextScreen(model);
        return;
      }
    }
    setState(() {
      show = false;
      showOverwrite = false;
      timerController.cancel();
    });
    publishMediaButtonAction(false);
  }

  void hideNextUp() {
    timerController.cancel();
    setState(() {
      show = false;
      showOverwrite = true;
    });
    publishMediaButtonAction(false);
  }

  /// Starts an item other than the one the countdown is offering - the
  /// previous episode, from the retained controls.
  ///
  /// No pop-out: that animation grows the artwork out of the next-up
  /// thumbnail, and the thumbnail is showing a different episode than the one
  /// about to start.
  void playItem(ItemBaseModel item) {
    hideNextUp();
    ref.read(playbackModelHelper).loadNewVideo(item);
  }

  /// Drops the player to the bottom bar. Same steps as the full controls'
  /// minimize, which the card used to cover up.
  void minimizePlayer() {
    clearOverlaySettings();
    ref.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
    ref.read(mediaPlaybackProvider.notifier).update(
          (state) => state.copyWith(state: VideoPlayerState.minimized),
        );
    Navigator.of(context).pop();
  }

  Future<void> closePlayer() async {
    clearOverlaySettings();
    ref.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
    ref.read(videoPlayerProvider).stop();
    Navigator.of(context).pop();
  }

  Future<void> clearOverlaySettings() async {
    if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.pointer) {
      ScreenBrightness().resetApplicationScreenBrightness();
    } else {
      fullScreenHelper.closeFullScreen(ref);
    }

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarIconBrightness: ref.read(clientSettingsProvider.select((value) => value.statusBarBrightness(context))),
    ));
  }

  /// Resolved in [initState] for the same reason as [nextUpAction]: `ref` is
  /// already unusable by the time [dispose] runs, and a throw from inside
  /// dispose leaves Flutter's unmount half done.
  late final StateController<bool> nextUpVisible;

  @override
  void initState() {
    super.initState();
    nextUpAction = ref.read(nextUpPlayNowProvider.notifier);
    nextUpVisible = ref.read(nextUpVisibleProvider.notifier);
  }

  @override
  void dispose() {
    _nextUpScope.dispose();
    // The card goes with the player; leaving this set would leave the next
    // player standing down for a card that is not there.
    final visible = nextUpVisible;
    Future.microtask(() => visible.state = false);
    disposed = true;
    timerController.cancel();
    // Unlike the show/hide path this one has to be deferred: dispose runs
    // inside the build phase, where providers can't be modified. Only clears
    // our own action, in case a new player registered in the meantime.
    mediaButtonActionPublished = false;
    final action = onTimeOut;
    final controller = nextUpAction;
    Future.microtask(() {
      try {
        if (controller.state == action) controller.state = null;
      } catch (_) {
        // ProviderContainer may already be torn down.
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A remote has nowhere else to be once the controls step out of the
    // focus order behind the card, so the card takes focus itself.
    final onTelevision = ref.watch(argumentsStateProvider.select((value) => value.htpcMode || value.leanBackMode));

    // Published from here rather than from each of the half-dozen places that
    // flip `show`, so it cannot drift out of step with what is on screen. The
    // player reads it to know to keep its hands off the pad.
    if (ref.read(nextUpVisibleProvider) != show) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(nextUpVisibleProvider.notifier).state = show;
      });
    }

    const animSpeed = Duration(milliseconds: 250);
    final nextUp = ref.watch(playBackModel.select((value) => value?.nextVideo));
    final currentItem = ref.watch(playBackModel.select((value) => value?.item));
    final portraitMode = MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;

    double padding = show ? 16 : 0;

    ref.listen(mediaPlaybackProvider, (previous, next) => determineShow(next));
    // Entering/leaving PiP changes what may be shown without a playback tick.
    ref.listen(pipStateProvider, (previous, next) => determineShow(ref.read(mediaPlaybackProvider)));
    return Hero(
      tag: videoPlayerHeroTag,
      // Without this the flight's shuttle is this hero's child - the whole
      // player, controls and next-up card included - built a second time and
      // animated over a live video texture, which is what made expanding
      // stutter. The zoom only needs a rectangle of the right shape.
      flightShuttleBuilder: (context, animation, direction, fromContext, toContext) => const DecoratedBox(
        decoration: BoxDecoration(color: Colors.black),
      ),
      child: Stack(
        children: [
          if (nextUp != null)
            // Faded out is not gone: without this the pad walks onto the card's
            // buttons while they are invisible, which is the selection
            // disappearing into nothing mid-episode.
            ExcludeFocus(
              excluding: !show,
              child: FocusScope(
                  node: _nextUpScope,
                  child: AnimatedAlign(
                    duration: animSpeed,
                    alignment: portraitMode ? Alignment.bottomCenter : Alignment.centerRight,
                    child: AnimatedOpacity(
                      duration: animSpeed,
                      opacity: show ? 1 : 0,
                      child: Padding(
                        padding: MediaQuery.paddingOf(context).add(const EdgeInsets.all(32)),
                        child: FractionallySizedBox(
                          widthFactor: portraitMode ? null : 0.35,
                          heightFactor: portraitMode ? 0.5 : null,
                          child: Card(
                            elevation: 10,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          context.localized.nextUp,
                                          softWrap: false,
                                          overflow: TextOverflow.fade,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(fontWeight: FontWeight.bold, fontSize: 24.0),
                                        ),
                                      ),
                                      SizedBox.square(
                                        dimension: 45.0,
                                        child: ProgressFloatingButton(
                                          controller: timerController,
                                        ),
                                      ),
                                    ].addInBetween(
                                      const SizedBox(
                                        height: 16,
                                        width: 16,
                                      ),
                                    ),
                                  ),
                                  const Divider(),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      child: _NextUpInformation(
                                        item: nextUp,
                                        posterKey: nextUpPosterKey,
                                        onTelevision: onTelevision,
                                        onPlayNow: () => onTimeOut(),
                                      ),
                                    ),
                                  ),
                                ].addInBetween(const SizedBox(
                                  height: 8,
                                  width: 8,
                                )),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )),
            ),
          AnimatedAlign(
            duration: animSpeed,
            alignment: portraitMode ? Alignment.topCenter : Alignment.centerLeft,
            child: AnimatedPadding(
              duration: animSpeed,
              padding: EdgeInsets.all(padding).add(show ? MediaQuery.paddingOf(context) : EdgeInsets.zero),
              child: AnimatedFractionallySizedBox(
                duration: animSpeed,
                heightFactor: show ? (portraitMode ? 0.40 : 0.9) : 1.0,
                widthFactor: show ? (portraitMode ? 1 : 0.60) : 1.0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (currentItem != null)
                      AnimatedFadeSize(
                        duration: animSpeed,
                        child: show
                            // Stands in for the player's own top bar, in the
                            // same order: minimize on the far left, the title
                            // where the logo sits, SyncPlay and cast trailing.
                            ? Padding(
                                // Reserve the corner the close button now owns:
                                // in portrait the shrunken player spans the
                                // full width, so the row would run under it.
                                padding: EdgeInsets.only(bottom: 16, right: portraitMode ? 56 : 0),
                                child: Row(
                                  spacing: 8,
                                  children: [
                                    IconButton(
                                      onPressed: minimizePlayer,
                                      icon: const Icon(IconsaxPlusLinear.arrow_down_1, size: 24),
                                    ),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            currentItem.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.fade,
                                            softWrap: false,
                                            style: Theme.of(context).textTheme.displaySmall,
                                          ),
                                          if (currentItem.label(context.localized) != null)
                                            Text(
                                              currentItem.label(context.localized)!,
                                              maxLines: 2,
                                              overflow: TextOverflow.fade,
                                              style: Theme.of(context).textTheme.bodyMedium,
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Given the icon buttons' height to centre
                                    // against: the pill is shorter than they
                                    // are, same as in the player's top bar.
                                    const SizedBox(height: 48, child: Center(child: SyncPlayBadge())),
                                    const SyncPlayButton(),
                                    CastButton(onConnected: minimizePlayer),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    Flexible(
                      child: Stack(
                        fit: StackFit.passthrough,
                        children: [
                          AnimatedContainer(
                            duration: animSpeed,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(show ? 16 : 0),
                            ),
                            child: widget.video,
                          ),
                          // The shrunken player is the way back to the episode
                          // still running inside it: tapping it dismisses the
                          // card and hands the screen back. Sits above the
                          // video and below the real controls, which are not
                          // taking pointers while the card is up anyway.
                          if (show)
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: hideNextUp,
                              ),
                            ),
                          IgnorePointer(
                            ignoring: show,
                            // Out of the focus order too, not merely faded. The
                            // controls stay in the tree behind the card, so a
                            // remote went on holding a button nobody could see
                            // and every press did nothing - the pad appeared to
                            // die the moment the card came up.
                            child: ExcludeFocus(
                              excluding: show,
                              child: AnimatedOpacity(
                                opacity: show ? 0 : 1,
                                duration: animSpeed,
                                child: widget.controls,
                              ),
                            ),
                          ),
                          // Fullscreen player shrunk into a PiP window: same
                          // slim strip the minimized PiP path shows.
                          const PipNextUpStrip(),
                        ],
                      ),
                    ),
                    ExcludeFocus(
                        excluding: !show,
                        child: IgnorePointer(
                          ignoring: !show,
                          child: AnimatedFadeSize(
                            duration: animSpeed,
                            child: show
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: _NextUpControls(
                                      playNext: nextUp != null ? () => onTimeOut() : null,
                                      playItem: playItem,
                                      minimizePlayer: minimizePlayer,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ),
          if (AdaptiveLayout.of(context).isDesktop)
            ExcludeFocus(
                excluding: !show,
                child: IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    duration: animSpeed,
                    opacity: show ? 1 : 0,
                    child: const Align(
                      alignment: Alignment.topRight,
                      child: DefaultTitleBar(),
                    ),
                  ),
                )),
          // Owns the screen's top-right corner rather than the shrunken
          // player's header, so it reads as closing the whole thing and stays
          // clear of the next-up card beneath it. On desktop it sits under the
          // window buttons the title bar above already put there.
          ExcludeFocus(
              excluding: !show,
              child: IgnorePointer(
                ignoring: !show,
                child: AnimatedOpacity(
                  duration: animSpeed,
                  opacity: show ? 1 : 0,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: (AdaptiveLayout.of(context).isDesktop
                                ? defaultTitleBarHeight
                                : MediaQuery.paddingOf(context).top) +
                            8,
                        right: MediaQuery.paddingOf(context).right + 12,
                      ),
                      child: IconButton.filledTonal(
                        onPressed: () => closePlayer(),
                        tooltip: context.localized.closeVideo,
                        icon: const Icon(IconsaxPlusBold.close_square),
                      ),
                    ),
                  ),
                ),
              )),
          if (popOut != null)
            Positioned.fill(
              child: IgnorePointer(
                child: _PopOutOverlay(
                  popOut: popOut!,
                  onFinished: () {
                    if (mounted) setState(() => popOut = null);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The next-up thumbnail's artwork and where on screen it sat when the next
/// episode was started.
class _PopOut {
  final Rect rect;
  final ItemBaseModel item;

  const _PopOut({required this.rect, required this.item});
}

/// Grows the next episode's artwork out of its thumbnail to fill the player,
/// then fades to reveal the episode now playing underneath.
class _PopOutOverlay extends StatelessWidget {
  final _PopOut popOut;
  final VoidCallback onFinished;

  static const _duration = Duration(milliseconds: 500);

  /// Fraction of the animation spent expanding before the fade begins.
  static const _holdFraction = 0.6;

  const _PopOutOverlay({required this.popOut, required this.onFinished});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = Offset.zero & constraints.biggest;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: _duration,
          curve: Curves.linear,
          onEnd: onFinished,
          builder: (context, value, child) {
            final expansion = Curves.easeOutCubic.transform(value);
            final rect = Rect.lerp(popOut.rect, target, expansion)!;
            final fade = value <= _holdFraction ? 1.0 : 1 - ((value - _holdFraction) / (1 - _holdFraction));
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16 * (1 - expansion)),
                      child: child,
                    ),
                  ),
                ),
              ],
            );
          },
          child: FladderImage(
            image: popOut.item.images?.primary,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _NextUpInformation extends StatelessWidget {
  final ItemBaseModel item;
  final Key? posterKey;
  final VoidCallback? onPlayNow;

  /// Whether a remote is what will be pressing this, in which case the card
  /// takes focus as it arrives - there is nowhere else for focus to be once
  /// the controls behind it have left the focus order.
  final bool onTelevision;

  const _NextUpInformation({
    required this.item,
    this.posterKey,
    this.onPlayNow,
    this.onTelevision = false,
  });

  Widget _playOverlay(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.5),
        ),
        child: const Icon(
          IconsaxPlusBold.play,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      MovieModel _ => Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: AspectRatio(
                      key: posterKey,
                      aspectRatio: 0.67,
                      child: FocusButton(
                        // Takes focus as the card arrives, so a remote lands on
                        // the one thing the card is for.
                        autoFocus: onTelevision,
                        onTap: onPlayNow,
                        borderRadius: FladderTheme.smallShape.borderRadius,
                        overlays: [_playOverlay(context)],
                        child: Card(
                          child: FladderImage(
                            image: item.images?.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ].addInBetween(
                const SizedBox(height: 8),
              ),
            ),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.localized.overview,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  Text(item.overview.summary),
                ],
              ),
            )
          ].addInBetween(
            const SizedBox(width: 16),
          ),
        ),
      _ => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (item.label(context.localized) != null)
              Text(
                item.label(context.localized)!,
              ),
            Flexible(
              child: AspectRatio(
                key: posterKey,
                aspectRatio: 2.1,
                child: FocusButton(
                  autoFocus: onTelevision,
                  onTap: onPlayNow,
                  borderRadius: FladderTheme.smallShape.borderRadius,
                  overlays: [_playOverlay(context)],
                  child: Card(
                    child: FladderImage(
                      image: item.images?.primary,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              context.localized.overview,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(item.overview.summary),
            const SizedBox(height: 12)
          ].addInBetween(
            const SizedBox(height: 8),
          ),
        )
    };
  }
}

/// The slice of the player's chrome that stays live while the next-up card is
/// up. The card used to take every control with it, which left the episode
/// still running underneath unreachable - it could not be paused, scrubbed
/// back into, or turned down without dismissing the card first.
///
/// Deliberately a subset. The track pickers, seek skips and playback readouts
/// belong to an episode that is on its way out, and the overflow menu is the
/// way back to all of them.
class _NextUpControls extends ConsumerStatefulWidget {
  /// Starts the episode the card is offering, with the same pop-out the
  /// countdown uses. Null when there is nothing queued behind this one.
  final VoidCallback? playNext;

  /// Starts some other item - the previous episode, once the row has looked
  /// one up.
  final void Function(ItemBaseModel item) playItem;

  final VoidCallback minimizePlayer;

  const _NextUpControls({
    required this.playNext,
    required this.playItem,
    required this.minimizePlayer,
  });

  @override
  ConsumerState<_NextUpControls> createState() => _NextUpControlsState();
}

class _NextUpControlsState extends ConsumerState<_NextUpControls> {
  bool wasPlaying = false;

  @override
  Widget build(BuildContext context) {
    final mediaPlayback = ref.watch(mediaPlaybackProvider);
    final previousVideo = ref.watch(playBackModel.select((value) => value?.previousVideo));
    // The bottom bar's rule for the same two buttons: on a handheld the volume
    // keys and a permanently full screen leave them nothing to do.
    final handheld = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone && !AdaptiveLayout.of(context).isDesktop;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 25,
          child: VideoProgressBar(
            wasPlayingChanged: (value) => wasPlaying = value,
            wasPlaying: wasPlaying,
            duration: mediaPlayback.duration,
            position: mediaPlayback.position,
            buffer: mediaPlayback.buffer,
            buffering: mediaPlayback.buffering,
            // Nothing to keep awake here: the card has its own countdown and
            // the chrome behind it is already hidden.
            timerReset: () {},
            onPositionChanged: (position) => ref.read(videoPlayerProvider.notifier).userSeek(position),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                mediaPlayback.position.readAbleDuration,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                "-${(mediaPlayback.duration - mediaPlayback.position).readAbleDuration}",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // The bottom bar's own shape: the overflow menu holding the left
        // flank, the transport centred on play/pause, volume and full screen
        // trailing right.
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => showVideoPlayerOptions(context, widget.minimizePlayer),
                    icon: const Icon(IconsaxPlusLinear.more),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed:
                  previousVideo != null && !mediaPlayback.buffering ? () => widget.playItem(previousVideo) : null,
              iconSize: 30,
              icon: const Icon(IconsaxPlusLinear.backward),
            ),
            IconButton.filledTonal(
              iconSize: 38,
              onPressed: () => ref.read(videoPlayerProvider.notifier).userPlayOrPause(),
              icon: Icon(mediaPlayback.playing ? IconsaxPlusBold.pause : IconsaxPlusBold.play),
            ),
            IconButton(
              onPressed: mediaPlayback.buffering ? null : widget.playNext,
              tooltip: context.localized.playNextVideo,
              iconSize: 30,
              icon: const Icon(IconsaxPlusLinear.forward),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!handheld) const VideoVolumeSlider(collapsed: true),
                  if (!handheld) const FullScreenButton(),
                ].addInBetween(const SizedBox(width: 8)),
              ),
            ),
          ].addInBetween(const SizedBox(width: 6)),
        ),
      ],
    );
  }
}
