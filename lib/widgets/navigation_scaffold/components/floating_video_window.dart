import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/providers/cast_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/video_player/components/video_volume_slider.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/shared/full_screen_player_launcher.dart';
import 'package:fladder/widgets/navigation_scaffold/components/shared/player_bar_shared.dart';

/// Where the user dragged the window to (top-left corner, logical pixels).
/// Null until they move it — it then starts in the bottom-right corner. Kept
/// in a provider so the position survives the scaffold rebuilding around it.
final floatingVideoWindowOffsetProvider = StateProvider<Offset?>((ref) => null);

/// User's size for the window, as a multiple of the size the layout picks for
/// this screen (see [floatingVideoWindowWidth]). Relative rather than absolute
/// so it still makes sense when the app moves to a different-sized display.
final floatingVideoWindowScaleProvider = StateProvider<double>((ref) => 1.0);

/// Width of the window for a screen [available] wide. A fixed size that reads
/// as "small" on a desktop covers half a phone, so it's a share of the screen
/// with a cap rather than a constant.
double floatingVideoWindowWidth(BuildContext context, double available) => switch (AdaptiveLayout.viewSizeOf(context)) {
      ViewSize.phone => min(available * 0.55, 320),
      ViewSize.tablet => min(available * 0.45, 520),
      _ => min(available * 0.4, 640),
    };

/// Switches the current playback between window and bar, overriding the
/// setting until the app closes. Null follows
/// [VideoPlayerSettingsModel.minimizedVideoAsWindow].
final floatingVideoWindowOverrideProvider = StateProvider<bool?>((ref) => null);

/// Whether this playback *could* show as the small window. Only when there is a
/// picture worth keeping an eye on: audio, items without a video stream and
/// casting keep the bar, which has the seek bar and queue controls those need.
/// A d-pad can't drag a window around either, so TV keeps the bar as well.
bool canUseFloatingVideoWindow(BuildContext context, WidgetRef ref) {
  if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) return false;
  if (ref.watch(castProvider.select((value) => value.isConnected))) return false;
  if (ref.watch(playBackModel.select((value) => value?.item)) is AudioModel) return false;
  return ref.watch(playBackModel.select((value) => value?.mediaStreams?.videoStreams.isNotEmpty == true));
}

/// Whether the minimized player shows as the small draggable window instead of
/// the bottom bar right now: what the user picked, for playback that can do it.
bool useFloatingVideoWindow(BuildContext context, WidgetRef ref) {
  if (!canUseFloatingVideoWindow(context, ref)) return false;
  return ref.watch(floatingVideoWindowOverrideProvider) ??
      ref.watch(videoPlayerSettingsProvider.select((value) => value.minimizedVideoAsWindow));
}

/// The minimized video player: a small window floating over the app that can be
/// dragged anywhere, showing play/pause, stop and mute when hovered.
class FloatingVideoWindow extends ConsumerStatefulWidget {
  const FloatingVideoWindow({super.key});

  @override
  ConsumerState<FloatingVideoWindow> createState() => _FloatingVideoWindowState();
}

class _FloatingVideoWindowState extends ConsumerState<FloatingVideoWindow>
    with FullScreenPlayerLauncher, SingleTickerProviderStateMixin {
  static const _margin = 12.0;

  /// Shape of what is playing, refreshed every build. Locking the window to
  /// 16:9 letterboxed anything that wasn't - the window is the picture, so it
  /// takes the picture's shape and there are no bars to letterbox with.
  double _ratio = 16 / 9;

  /// How far past the edge a drag can pull the window, and how much of the
  /// pull actually lands there — enough to feel elastic, not enough to lose
  /// the window off screen.
  static const _maxOvershoot = 56.0;
  static const _overshootResistance = 0.4;

  bool _showControls = false;
  Timer? _hideControls;

  /// Top-left of the window. Null until placed (see [_defaultPosition]) and
  /// allowed past the edges mid-drag, where [_springBack] pulls it in again.
  Offset? _position;

  /// Where in the window the gesture started, as a fraction of its size, so a
  /// move tracks the fingers exactly and a pinch scales around the same spot.
  Offset _grabFraction = Offset.zero;
  double _gestureStartWidth = 0;
  bool _dragging = false;

  /// How far the user may scale the window either side of the layout's own
  /// size for this screen.
  static const _minScale = 0.6;
  static const _maxScale = 2.0;

  /// Range the top-left may settle in, refreshed every build from the current
  /// layout so a resized app window can't strand it.
  Rect _bounds = Rect.zero;

  /// Sizes for the current layout, refreshed every build: what the layout
  /// picked, what is actually painted, and the largest that still fits.
  double _baseWidth = 0;
  double _width = 0;
  double _widthLimit = 0;

  /// Grab area of the resize handles: a strip along each edge, squares in the
  /// corners.
  static const _edgeGrab = 8.0;
  static const _cornerGrab = 16.0;

  /// Where a resize was grabbed, the window at that moment, and which way the
  /// grabbed handle grows it.
  Offset _resizeAnchor = Offset.zero;
  Rect _resizeStartRect = Rect.zero;
  int _resizeAx = 1;
  int _resizeAy = 1;

  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..addListener(() {
      if (_springTween != null) setState(() => _position = _springTween!.evaluate(_springCurve));
    });
  Tween<Offset>? _springTween;
  late final CurvedAnimation _springCurve = CurvedAnimation(parent: _spring, curve: Curves.elasticOut);

  @override
  void dispose() {
    _hideControls?.cancel();
    _springCurve.dispose();
    _spring.dispose();
    super.dispose();
  }

  Offset _clamp(Offset offset) => Offset(
        offset.dx.clamp(_bounds.left, _bounds.right),
        offset.dy.clamp(_bounds.top, _bounds.bottom),
      );

  /// Pulls back against a drag that has left [_bounds], so the window lags
  /// further and further behind the pointer instead of following it out.
  double _resist(double value, double min, double max) {
    if (value < min) return min - _overshootOf(min - value);
    if (value > max) return max + _overshootOf(value - max);
    return value;
  }

  double _overshootOf(double distance) =>
      _maxOvershoot * (1 - 1 / (1 + distance * _overshootResistance / _maxOvershoot));

  /// Moving and pinch-resizing are the same gesture: [ScaleGestureRecognizer]
  /// tracks the focal point of however many fingers there are. A pan
  /// recognizer instead re-targets to the newest pointer, which threw the
  /// window at the second finger the moment a pinch began.
  void _startGesture(ScaleStartDetails details) {
    _spring.stop();
    _springTween = null;
    _dragging = true;
    final position = _position ?? _defaultPosition;
    final size = Size(_width, _width / _ratio);
    _gestureStartWidth = _width;
    _grabFraction = Offset(
      size.width == 0 ? 0.5 : (details.focalPoint.dx - position.dx) / size.width,
      size.height == 0 ? 0.5 : (details.focalPoint.dy - position.dy) / size.height,
    );
  }

  void _updateGesture(ScaleUpdateDetails details) {
    var width = _width;
    if (details.pointerCount > 1) {
      width =
          (_gestureStartWidth * details.scale).clamp(_baseWidth * _minScale, min(_baseWidth * _maxScale, _widthLimit));
      ref.read(floatingVideoWindowScaleProvider.notifier).state = width / _baseWidth;
    }
    // Anchored on the grab point rather than the corner, so the window grows
    // out from between the fingers instead of sliding away from them.
    final free = details.focalPoint - Offset(_grabFraction.dx * width, _grabFraction.dy * width / _ratio);
    setState(() => _position = Offset(
          _resist(free.dx, _bounds.left, _bounds.right),
          _resist(free.dy, _bounds.top, _bounds.bottom),
        ));
  }

  void _endGesture([ScaleEndDetails? details]) {
    _dragging = false;
    _springBack();
  }

  /// Bounces the window off the wall it was dragged into and leaves it stuck
  /// against that edge; a drop well inside the bounds just stays put.
  void _springBack() {
    final from = _position ?? _defaultPosition;
    final to = _clamp(from);
    ref.read(floatingVideoWindowOffsetProvider.notifier).state = to;
    if (from == to) {
      setState(() => _position = to);
      return;
    }
    _springTween = Tween(begin: from, end: to);
    _spring.forward(from: 0);
  }

  void _startResize(DragStartDetails details, int ax, int ay) {
    // Touch arms the handles off the controls being visible, so keep them up
    // (and restart their countdown) for as long as the user is resizing.
    if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.pointer) {
      _setControlsVisible(true, autoHide: true);
    }
    _spring.stop();
    _springTween = null;
    _resizeAnchor = details.globalPosition;
    _resizeAx = ax;
    _resizeAy = ay;
    _resizeStartRect = (_position ?? _defaultPosition) & Size(_width, _width / _ratio);
  }

  void _updateResize(DragUpdateDetails details) {
    final delta = details.globalPosition - _resizeAnchor;
    // Each axis the handle can move in contributes a width; a corner takes
    // whichever the user pulled further, so a diagonal drag doesn't fight back.
    final grows = [
      if (_resizeAx != 0) _resizeAx * delta.dx,
      if (_resizeAy != 0) _resizeAy * delta.dy * _ratio,
    ];
    final grow = grows.isEmpty ? 0.0 : grows.reduce(max);
    final width =
        (_resizeStartRect.width + grow).clamp(_baseWidth * _minScale, min(_baseWidth * _maxScale, _widthLimit));
    final height = width / _ratio;

    // The side opposite the handle stays put; an edge handle grows both ways
    // on the axis it doesn't control, so the window stays centred on it.
    final left = switch (_resizeAx) {
      -1 => _resizeStartRect.right - width,
      1 => _resizeStartRect.left,
      _ => _resizeStartRect.center.dx - width / 2,
    };
    final top = switch (_resizeAy) {
      -1 => _resizeStartRect.bottom - height,
      1 => _resizeStartRect.top,
      _ => _resizeStartRect.center.dy - height / 2,
    };

    ref.read(floatingVideoWindowScaleProvider.notifier).state = width / _baseWidth;
    setState(() => _position = Offset(left, top));
  }

  /// Growing can push the far side off screen; the build pins it back as it
  /// goes, and this settles the position on release.
  void _endResize([DragEndDetails? details]) => _springBack();

  /// Invisible grab strip along one edge or corner. [ax]/[ay] are which way
  /// that handle grows the window: -1 left/up, 1 right/down, 0 not on that axis.
  /// [widthFactor]/[heightFactor] shorten the strip to part of that edge.
  Widget _resizeHandle({
    required Alignment alignment,
    required Size size,
    required MouseCursor cursor,
    required int ax,
    required int ay,
  }) {
    final Widget handle = MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Deeper in the tree than the window's own drag, so it takes the
        // gesture when the pointer is on an edge.
        onPanStart: (details) => _startResize(details, ax, ay),
        onPanUpdate: _updateResize,
        onPanEnd: _endResize,
        onPanCancel: _endResize,
        child: SizedBox.fromSize(size: size),
      ),
    );
    return Align(alignment: alignment, child: handle);
  }

  /// Every edge and corner, laid over the window's border. Sizes are explicit
  /// rather than fractional: a FractionallySizedBox fills its parent and
  /// centres its child, which lands the strips in the middle of the window
  /// instead of on its edges.
  List<Widget> _resizeHandles({required double width, required double height}) {
    final edge = Size(_edgeGrab, height);
    final side = Size(width, _edgeGrab);
    const corner = Size.square(_cornerGrab);
    return [
      _resizeHandle(
        alignment: Alignment.centerLeft,
        size: edge,
        cursor: SystemMouseCursors.resizeLeftRight,
        ax: -1,
        ay: 0,
      ),
      _resizeHandle(
        alignment: Alignment.centerRight,
        size: edge,
        cursor: SystemMouseCursors.resizeLeftRight,
        ax: 1,
        ay: 0,
      ),
      _resizeHandle(
        alignment: Alignment.topCenter,
        size: side,
        cursor: SystemMouseCursors.resizeUpDown,
        ax: 0,
        ay: -1,
      ),
      _resizeHandle(
        alignment: Alignment.bottomCenter,
        size: side,
        cursor: SystemMouseCursors.resizeUpDown,
        ax: 0,
        ay: 1,
      ),
      // Corners last: they overlap the edges and must win.
      _resizeHandle(
        alignment: Alignment.topLeft,
        size: corner,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        ax: -1,
        ay: -1,
      ),
      _resizeHandle(
        alignment: Alignment.topRight,
        size: corner,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        ax: 1,
        ay: -1,
      ),
      _resizeHandle(
        alignment: Alignment.bottomLeft,
        size: corner,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        ax: -1,
        ay: 1,
      ),
      _resizeHandle(
        alignment: Alignment.bottomRight,
        size: corner,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        ax: 1,
        ay: 1,
      ),
    ];
  }

  Offset get _defaultPosition {
    // The phone's bottom navigation bar occupies exactly the corner the window
    // would start in, so start above it. It can still be dragged down there.
    final lift = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone ? 77.0 : 0.0;
    return Offset(_bounds.right, max(_bounds.top, _bounds.bottom - lift));
  }

  void _setControlsVisible(bool value, {bool autoHide = false}) {
    _hideControls?.cancel();
    // Without a mouse there is no "exit" to hide on, so a tap shows the
    // controls and they fade out again on their own.
    if (value && autoHide) {
      _hideControls = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
    if (_showControls != value) {
      setState(() => _showControls = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final pointer = AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer;

    return LayoutBuilder(
      builder: (context, constraints) {
        _ratio = ref.watch(
              playBackModel.select((value) {
                final video = value?.mediaStreams?.videoStreams.firstOrNull;
                if (video == null || video.width <= 0 || video.height <= 0) return null;
                return video.width / video.height;
              }),
            ) ??
            16 / 9;
        // Anything beyond these is a stream describing itself oddly; the window
        // still has to be a usable shape.
        _ratio = _ratio.clamp(0.5, 3.2);

        _baseWidth = floatingVideoWindowWidth(context, constraints.maxWidth);
        // Never wider than the screen, nor so tall it can't fit between the
        // insets - a 2x scale on a short window would otherwise run off it.
        _widthLimit = max(
          120.0,
          min(
            constraints.maxWidth - _margin * 2,
            (constraints.maxHeight - padding.vertical - _margin * 2) * _ratio,
          ),
        );
        final scale = ref.watch(floatingVideoWindowScaleProvider).clamp(_minScale, _maxScale);
        final width = _width = min(_baseWidth * scale, _widthLimit);
        final height = width / _ratio;

        final minX = padding.left + _margin;
        final maxX = max(minX, constraints.maxWidth - padding.right - _margin - width);
        final minY = padding.top + _margin;
        final maxY = max(minY, constraints.maxHeight - padding.bottom - _margin - height);
        // Rect of allowed *top-left* positions, not of the window itself.
        _bounds = Rect.fromLTRB(minX, minY, maxX, maxY);

        final stored = ref.watch(floatingVideoWindowOffsetProvider);
        // Start in the bottom-right corner, roughly where the bar used to sit —
        // but clear of the phone's bottom navigation bar, which sits there too.
        _position ??= stored ?? _defaultPosition;
        // A resized app window can leave the last position out of bounds; pull
        // it back in, but never while the drag or its bounce is in flight.
        // Written back, not just painted clamped: a stale out-of-bounds
        // position would make the next drag or bounce start from a jump.
        final offset = _dragging || _spring.isAnimating ? _position! : (_position = _clamp(_position!));

        return Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy,
              width: width,
              height: height,
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                onEnter: (_) => _setControlsVisible(true),
                onExit: (_) => _setControlsVisible(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _startGesture,
                  onScaleUpdate: _updateGesture,
                  onScaleEnd: _endGesture,
                  // Touch has no hover, so a tap reveals the controls (and the
                  // expand button with them) instead of expanding outright.
                  // Deliberately no double-tap: pairing one with onTap makes
                  // every single tap wait out the double-tap timer first.
                  onTap: () => pointer ? openFullScreenPlayer() : _setControlsVisible(!_showControls, autoHide: true),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Material(
                        elevation: 12,
                        color: Colors.black,
                        clipBehavior: Clip.antiAlias,
                        borderRadius: FladderTheme.defaultShape.borderRadius,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // The flight this pairs with is cheap now: the
                            // full screen player's hero builds a plain
                            // rectangle for the shuttle rather than itself.
                            //
                            // FilterQuality stays at the default: medium
                            // mipmaps the texture, which for a video means
                            // regenerating them every frame.
                            Hero(
                              tag: videoPlayerHeroTag,
                              child: ref.read(videoPlayerProvider).videoWidget(
                                        const ValueKey("floating_window_video"),
                                        // The window is cut to the video's own
                                        // shape, so cover and contain agree -
                                        // and cover hides a rounding gap.
                                        BoxFit.cover,
                                      ) ??
                                  const SizedBox.shrink(),
                            ),
                            IgnorePointer(
                              ignoring: !_showControls,
                              child: AnimatedOpacity(
                                opacity: _showControls ? 1 : 0,
                                duration: const Duration(milliseconds: 125),
                                child: _FloatingVideoWindowControls(
                                  onExpand: openFullScreenPlayer,
                                  width: width,
                                  height: height,
                                ),
                              ),
                            ),
                            const Align(
                              alignment: Alignment.bottomCenter,
                              child: _FloatingVideoWindowProgress(),
                            ),
                          ],
                        ),
                      ),
                      // Outside the Material on purpose: its rounded clip would
                      // cut the corner handles down to the arc, leaving the very
                      // corner - where you aim to resize - dead.
                      //
                      // Pointer only: a pinch covers this on touch, and a strip
                      // wide enough for a fingertip would cover the buttons.
                      if (pointer) ..._resizeHandles(width: width, height: height),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FloatingVideoWindowControls extends ConsumerWidget {
  const _FloatingVideoWindowControls({required this.onExpand, required this.width, required this.height});

  final VoidCallback onExpand;

  /// Controls are laid out against the window's real size: fixed sizes that
  /// look right on a desktop window collide inside a phone-sized one.
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(mediaPlaybackProvider.select((value) => value.playing));
    final volume = ref.watch(videoPlayerSettingsProvider.select((value) => value.volume));
    final nextVideo = ref.watch(playBackModel.select((value) => value?.nextVideo));

    final touch = AdaptiveLayout.inputDeviceOf(context) != InputDevice.pointer;
    final pad = (height * 0.06).clamp(6.0, 14.0);
    var gap = (width * 0.035).clamp(6.0, 18.0);
    final smallest = touch ? 26.0 : 20.0;

    // Diameters, derived from the window and then made to fit it. Touch wants
    // ~44px targets, but not at the cost of buttons landing on top of another.
    var main = (height * 0.34).clamp(touch ? 34.0 : 26.0, 62.0);
    var play = main * 1.25;

    // How much room is left above the centre row for a corner button. Sizing
    // the two independently is what made them overlap on a phone.
    final clearance = (height - play) / 2 - pad;
    // Too short to stack: put everything in one row instead of overlapping.
    final compact = clearance < smallest;

    final transportCount = nextVideo != null ? 4 : 3;
    final buttons = transportCount + (compact ? 2 : 0);
    final row = main * (buttons - 1) + play + gap * (buttons - 1);
    if (row > width - pad * 2) {
      // Gaps shrink with the buttons; shrinking only the buttons leaves the
      // row still too wide, which is how five of them overflowed.
      final shrink = (width - pad * 2) / row;
      main *= shrink;
      play *= shrink;
      gap *= shrink;
    }
    final corner = compact ? main : min((height * 0.22).clamp(smallest, 40.0), clearance);

    final dock = _WindowControl(
      tooltip: "Dock to the bottom bar",
      icon: Icons.keyboard_arrow_down_rounded,
      size: corner,
      onPressed: () => ref.read(floatingVideoWindowOverrideProvider.notifier).state = false,
    );
    // Top right is where a window's close button lives, and closing this one
    // means stopping playback - which is clearer than a square icon in the
    // middle of the transport row.
    final close = _WindowControl(
      tooltip: context.localized.stop,
      icon: Icons.close_rounded,
      size: corner,
      onPressed: () => ref.read(videoPlayerProvider).stop(),
    );
    final transport = [
      _WindowControl(
        tooltip: "Expand player",
        icon: Icons.open_in_full_rounded,
        size: main,
        onPressed: onExpand,
      ),
      _WindowControl(
        tooltip: playing ? "Pause" : "Play",
        icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: play,
        primary: true,
        onPressed: () => ref.read(videoPlayerProvider.notifier).userPlayOrPause(),
      ),
      if (nextVideo != null)
        _WindowControl(
          tooltip: "${context.localized.upNext}: ${nextVideo.detailedName(context.localized) ?? nextVideo.title}",
          icon: Icons.skip_next_rounded,
          size: main,
          onPressed: () => ref.read(videoPlayerProvider).loadNextVideo(),
        ),
      _WindowControl(
        tooltip: volume == 0 ? "Unmute" : context.localized.mute,
        icon: volumeIcon(volume),
        size: main,
        onPressed: () => ref.read(videoPlayerSettingsProvider.notifier).toggleMute(),
      ),
    ];

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      padding: EdgeInsets.all(pad),
      child: Stack(
        children: [
          if (!compact) ...[
            Align(alignment: Alignment.topLeft, child: dock),
            Align(alignment: Alignment.topRight, child: close),
          ],
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: gap,
              children: [
                if (compact) dock,
                ...transport,
                if (compact) close,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round translucent button of [size] across, sized off the window rather than
/// the theme so it scales with it.
class _WindowControl extends StatelessWidget {
  const _WindowControl({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;

  /// Diameter of the button, not of the glyph inside it.
  final double size;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.white.withValues(alpha: primary ? 0.22 : 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: size * 0.52, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _FloatingVideoWindowProgress extends ConsumerWidget {
  const _FloatingVideoWindowProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(mediaPlaybackProvider.select((value) => (
          position: value.position,
          duration: value.duration,
        )));
    return LinearProgressIndicator(
      minHeight: 3,
      backgroundColor: Colors.black.withValues(alpha: 0.25),
      color: Theme.of(context).colorScheme.primary,
      value: playback.duration.inMilliseconds > 0
          ? (playback.position.inMilliseconds / playback.duration.inMilliseconds).clamp(0, 1)
          : 0,
    );
  }
}
