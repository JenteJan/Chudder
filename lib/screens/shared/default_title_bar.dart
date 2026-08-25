import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';
import 'package:fladder/widgets/shared/status_banners.dart';

/// The glyph Windows uses to say "put the window back to the size it was".
///
/// Drawn rather than picked. Material has no restore glyph: the nearest ones
/// are two offset squares, which is what it uses for copy, and a bar across the
/// top, which reads as a second minimise. This is the shape every other window
/// on the desktop shows - a square with a second one behind it, up and to the
/// right - at the same weight as the plain square it alternates with.
class _RestoreIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _RestoreIcon({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _RestoreIconPainter(color)),
      );
}

class _RestoreIconPainter extends CustomPainter {
  final Color color;

  const _RestoreIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Laid out on a 12x12 grid and scaled, so the proportions hold at any size.
    final unit = size.width / 12;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    Offset at(double x, double y) => Offset(x * unit, y * unit);

    // The window in front.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromPoints(at(1, 4), at(8, 11)), Radius.circular(unit * 0.5)),
      paint,
    );

    // And the one behind it, of which only the top and right edges show.
    canvas.drawPath(
      Path()
        ..moveTo(at(4, 4).dx, at(4, 4).dy)
        ..lineTo(at(4, 2).dx, at(4, 2).dy)
        ..lineTo(at(10, 2).dx, at(10, 2).dy)
        ..lineTo(at(10, 8).dx, at(10, 8).dy)
        ..lineTo(at(8, 8).dx, at(8, 8).dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RestoreIconPainter oldDelegate) => oldDelegate.color != color;
}

class DefaultTitleBar extends ConsumerStatefulWidget {
  final String? label;
  final double? height;
  final Brightness? brightness;
  const DefaultTitleBar({this.height = defaultTitleBarHeight, this.label, this.brightness, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DefaultTitleBarState();
}

class _DefaultTitleBarState extends ConsumerState<DefaultTitleBar> with WindowListener {
  bool hovering = false;

  /// Whether the window is maximised.
  ///
  /// Kept here and kept up to date. It used to be read inside build, through a
  /// FutureBuilder whose future was made in that same build - so every rebuild
  /// started the question again and drew the button from `false` while it
  /// waited. That is what made the middle button strange: it showed the wrong
  /// glyph much of the time, and pressing it acted on whatever the last
  /// finished answer had been.
  ///
  /// It also only ever asked during a build, so maximising the window any other
  /// way - double-clicking the bar, Win+Up, dragging to the top of the screen -
  /// left the button describing a window that no longer existed. This listens
  /// instead, which is what [WindowListener] is for.
  bool _maximized = false;

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
    _readWindowState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _readWindowState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _maximized) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  // A restore can land either way round - from minimised back to a maximised
  // window, or back to a floating one - so this asks rather than assumes.
  @override
  void onWindowRestore() => _readWindowState();

  void _setMaximized(bool value) {
    if (!mounted || _maximized == value) return;
    setState(() => _maximized = value);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(argumentsStateProvider.select((value) => value.htpcMode))) return const SizedBox.shrink();
    final platform = AdaptiveLayout.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) return const StatusBanners();

    final theme = Theme.of(context);
    final brightness = widget.brightness ?? theme.brightness;
    final iconColor = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    final surfaceColor = theme.colorScheme.surface;
    final titleBarHeight = widget.height ?? defaultTitleBarHeight;

    return ExcludeFocus(
      child: MouseRegion(
        onEnter: (event) => setState(() => hovering = true),
        onExit: (event) => setState(() => hovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
              gradient: LinearGradient(
            colors: [
              surfaceColor.withValues(alpha: hovering ? 0.7 : 0),
              surfaceColor.withValues(alpha: 0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )),
          height: titleBarHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!kIsWeb)
                switch (platform) {
                  TargetPlatform.android || TargetPlatform.iOS => SizedBox(height: MediaQuery.paddingOf(context).top),
                  TargetPlatform.windows || TargetPlatform.linux => Container(
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0),
                              child: DragToMoveArea(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: DefaultTextStyle(
                                        style: TextStyle(
                                          color: iconColor,
                                          fontSize: 14,
                                        ),
                                        child: Text(widget.label ?? ""),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(boxShadow: [
                              BoxShadow(
                                color: surfaceColor.withValues(alpha: 0.5),
                                blurRadius: 32,
                                spreadRadius: 10,
                                offset: const Offset(8, -6),
                              ),
                            ]),
                            child: Row(
                              children: [
                                IconButton(
                                  style: IconButton.styleFrom(
                                      hoverColor: brightness == Brightness.light
                                          ? Colors.black.withValues(alpha: 0.1)
                                          : Colors.white.withValues(alpha: 0.2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))),
                                  // Only ever minimises: the window has to be
                                  // on screen for this to be pressed at all,
                                  // and it used to ask whether it was minimised
                                  // in order to decide.
                                  onPressed: () async {
                                    fullScreenHelper.closeFullScreen(ref);
                                    await windowManager.minimize();
                                  },
                                  icon: Transform.translate(
                                    offset: const Offset(0, -2),
                                    child: Icon(
                                      Icons.minimize_rounded,
                                      color: iconColor,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  style: IconButton.styleFrom(
                                    hoverColor: brightness == Brightness.light
                                        ? Colors.black.withValues(alpha: 0.1)
                                        : Colors.white.withValues(alpha: 0.2),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                  ),
                                  onPressed: () async {
                                    fullScreenHelper.closeFullScreen(ref);
                                    if (_maximized) {
                                      await windowManager.unmaximize();
                                    } else {
                                      await windowManager.maximize();
                                    }
                                  },
                                  icon: _maximized
                                      ? _RestoreIcon(color: iconColor, size: 19)
                                      : Icon(Icons.crop_square_rounded, color: iconColor, size: 19),
                                ),
                                IconButton(
                                  style: IconButton.styleFrom(
                                    hoverColor: Colors.red,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  onPressed: () async {
                                    windowManager.close();
                                  },
                                  icon: Transform.translate(
                                    offset: const Offset(0, -2),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: iconColor,
                                      size: 23,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  TargetPlatform.macOS => const SizedBox.shrink(),
                  _ => Text(widget.label ?? "Fladder"),
                },
              const StatusBanners()
            ],
          ),
        ),
      ),
    );
  }
}
