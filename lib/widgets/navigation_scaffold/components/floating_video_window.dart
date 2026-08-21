import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

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
  static const _ratio = 16 / 9;

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

  /// Grab point inside the window, so the drag tracks the pointer exactly
  /// instead of accumulating deltas against whatever was last painted.
  Offset _grab = Offset.zero;
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

  void _startDrag(DragStartDetails details) {
    _spring.stop();
    _springTween = null;
    _dragging = true;
    _grab = details.globalPosition - (_position ?? _defaultPosition);
  }

  void _updateDrag(DragUpdateDetails details) {
    final free = details.globalPosition - _grab;
    setState(() => _position = Offset(
          _resist(free.dx, _bounds.left, _bounds.right),
          _resist(free.dy, _bounds.top, _bounds.bottom),
        ));
  }

  void _endDrag([DragEndDetails? details]) {
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
  Widget _resizeHandle({
    required Alignment alignment,
    required Size size,
    required MouseCursor cursor,
    required int ax,
    required int ay,
  }) =>
      Align(
        alignment: alignment,
        child: MouseRegion(
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
        ),
      );

  /// Every edge and corner, laid over the window's border.
  List<Widget> _resizeHandles() {
    const edge = Size(_edgeGrab, double.infinity);
    const side = Size(double.infinity, _edgeGrab);
    const corner = Size.square(_cornerGrab);
    return [
      _resizeHandle(
          alignment: Alignment.centerLeft, size: edge, cursor: SystemMouseCursors.resizeLeftRight, ax: -1, ay: 0),
      _resizeHandle(
          alignment: Alignment.centerRight, size: edge, cursor: SystemMouseCursors.resizeLeftRight, ax: 1, ay: 0),
      _resizeHandle(alignment: Alignment.topCenter, size: side, cursor: SystemMouseCursors.resizeUpDown, ax: 0, ay: -1),
      _resizeHandle(
          alignment: Alignment.bottomCenter, size: side, cursor: SystemMouseCursors.resizeUpDown, ax: 0, ay: 1),
      // Corners last: they overlap the edges and must win.
      _resizeHandle(
          alignment: Alignment.topLeft, size: corner, cursor: SystemMouseCursors.resizeUpLeftDownRight, ax: -1, ay: -1),
      _resizeHandle(
          alignment: Alignment.topRight, size: corner, cursor: SystemMouseCursors.resizeUpRightDownLeft, ax: 1, ay: -1),
      _resizeHandle(
          alignment: Alignment.bottomLeft,
          size: corner,
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          ax: -1,
          ay: 1),
      _resizeHandle(
          alignment: Alignment.bottomRight,
          size: corner,
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          ax: 1,
          ay: 1),
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
                  onPanStart: _startDrag,
                  onPanUpdate: _updateDrag,
                  onPanEnd: _endDrag,
                  onPanCancel: _endDrag,
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
                            Hero(
                              tag: videoPlayerHeroTag,
                              child: ref.read(videoPlayerProvider).videoWidget(
                                        const ValueKey("floating_window_video"),
                                        BoxFit.contain,
                                        // The window shows a full-size frame at
                                        // a third of its width; bilinear
                                        // sampling (the default) makes that
                                        // crawl with aliasing, mipmaps don't.
                                        filterQuality: FilterQuality.medium,
                                      ) ??
                                  const SizedBox.shrink(),
                            ),
                            IgnorePointer(
                              ignoring: !_showControls,
                              child: AnimatedOpacity(
                                opacity: _showControls ? 1 : 0,
                                duration: const Duration(milliseconds: 125),
                                child: _FloatingVideoWindowControls(onExpand: openFullScreenPlayer, width: width),
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
                      // Resizing also wants a pointer to grab an edge with, so
                      // touch and TV keep the size the layout picked. No visible
                      // grip: the cursor over the border is the tell.
                      if (pointer) ..._resizeHandles(),
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
  const _FloatingVideoWindowControls({required this.onExpand, required this.width});

  final VoidCallback onExpand;

  /// Controls scale with the window: the same fixed sizes that look right on a
  /// thumbnail are lost in a window three times as wide.
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(mediaPlaybackProvider.select((value) => value.playing));
    final volume = ref.watch(videoPlayerSettingsProvider.select((value) => value.volume));

    // Touch needs a ~48px target, which a window this small only reaches by
    // taking a bigger share of it than a pointer would need.
    final touch = AdaptiveLayout.inputDeviceOf(context) != InputDevice.pointer;
    final icon = (width * (touch ? 0.11 : 0.075)).clamp(touch ? 22.0 : 18.0, 34.0);
    // Never less than a corner handle, or the buttons sit under one.
    final gap = (width * 0.03).clamp(18.0, 24.0);

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      padding: EdgeInsets.all(gap),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: _WindowControl(
              tooltip: "Dock to the bottom bar",
              icon: Icons.keyboard_arrow_down_rounded,
              size: icon * (touch ? 0.85 : 0.7),
              onPressed: () => ref.read(floatingVideoWindowOverrideProvider.notifier).state = false,
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: _WindowControl(
              tooltip: "Expand player",
              icon: Icons.open_in_full_rounded,
              size: icon * (touch ? 0.85 : 0.7),
              onPressed: onExpand,
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: gap,
              children: [
                _WindowControl(
                  tooltip: context.localized.stop,
                  icon: IconsaxPlusBold.stop,
                  size: icon,
                  onPressed: () => ref.read(videoPlayerProvider).stop(),
                ),
                _WindowControl(
                  tooltip: playing ? "Pause" : "Play",
                  icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: icon * 1.35,
                  primary: true,
                  onPressed: () => ref.read(videoPlayerProvider.notifier).userPlayOrPause(),
                ),
                _WindowControl(
                  tooltip: volume == 0 ? "Unmute" : context.localized.mute,
                  icon: volumeIcon(volume),
                  size: icon,
                  onPressed: () => ref.read(videoPlayerSettingsProvider.notifier).toggleMute(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round translucent button, sized off the window rather than the theme.
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
          child: Padding(
            padding: EdgeInsets.all(size * 0.45),
            child: Icon(icon, size: size, color: Colors.white),
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
