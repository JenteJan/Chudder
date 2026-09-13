import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';

/// The one mark of the selection, everywhere in the app.
///
/// On a television nothing is under a cursor and nothing is under a finger:
/// the ring is the only thing that says where you are. It used to be drawn in
/// the theme's primary, which on most themes is a pastel - the pale blue of a
/// dark blue seed - and on a poster full of colour it vanished. And it was
/// drawn four different ways, in four widths and four colours, so the eye had
/// to learn a new mark on every screen.
///
/// The ring is now the colour that contrasts with the surface - white in the
/// dark, near-black in the light - hemmed on both sides by a hairline of the
/// surface's own colour, so it stands off the artwork it is drawn over as well
/// as off the ground around it. One width, one shape, one colour family, on
/// every theme.
///
/// [FocusRing] draws it around any widget; [focusRingSide] is the same ring
/// for a Material button, which can only take a plain [BorderSide]; and
/// [FocusScale] is the lift a card gets on top of its ring, on a pad.
class FocusRing extends StatelessWidget {
  final bool visible;
  final BorderRadiusGeometry? borderRadius;
  final Duration duration;
  final Widget child;

  const FocusRing({
    required this.visible,
    required this.child,
    this.borderRadius,
    this.duration = const Duration(milliseconds: 200),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = (borderRadius ?? FladderTheme.smallShape.borderRadius).resolve(Directionality.of(context));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visible ? 1 : 0),
      duration: duration,
      curve: Curves.easeInOut,
      builder: (context, opacity, child) => CustomPaint(
        foregroundPainter: opacity == 0
            ? null
            : FocusRingPainter(
                opacity: opacity,
                radius: radius,
                ring: focusRingColor(colors),
                edge: focusRingEdgeColor(colors),
              ),
        child: child,
      ),
      child: child,
    );
  }
}

/// How wide the ring is, hairlines included. Everything drawn inside the box,
/// so nothing the ring is around changes size or gets clipped.
const double kFocusRingWidth = 3;
const double kFocusRingEdge = 1;
const double kFocusRingTotal = kFocusRingWidth + 2 * kFocusRingEdge;

/// The ring's colour on this scheme: what contrasts with the surface.
Color focusRingColor(ColorScheme colors) => colors.onSurface;

/// The hairline either side of the ring: the surface's own colour, so the
/// ring stands off whatever is inside and outside it.
Color focusRingEdgeColor(ColorScheme colors) => colors.surface;

/// How much a selected card lifts out of its row on a pad.
///
/// Five percent: enough to see, and less than the gap between cards, so a
/// lifted card never lies over the one beside it.
const double kFocusScale = 1.05;

/// The ring as the side of a Material button, for [ButtonStyle.side] and the
/// chip and checkbox themes. A single [BorderSide] cannot carry the hairlines,
/// so the button gets the ring alone - and, see [focusInvertedFill], its fill
/// turned inside out.
WidgetStateProperty<BorderSide> focusRingSide(ColorScheme colors) => WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        width: kFocusRingWidth,
        color: focusRingColor(colors).withValues(alpha: states.contains(WidgetState.focused) ? 1 : 0),
      ),
    );

/// A focused button's fill: the ring's own colour, edge to edge.
///
/// A button is small, and on the row of icons under a film a ring around one
/// of them is a line among lines. Turned inside out - light on dark becomes
/// dark on light - the selected one is the one that is a different colour
/// from all the others, which reads from across a room. The same thing a
/// selected genre chip does.
WidgetStateProperty<Color?> focusInvertedFill(ColorScheme colors) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusRingColor(colors) : null,
    );

/// What sits on [focusInvertedFill]: text and icons in the surface colour.
WidgetStateProperty<Color?> focusInvertedContent(ColorScheme colors) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusRingEdgeColor(colors) : null,
    );

/// The lift a selected card gets on a pad, on top of its ring.
///
/// Driven by the card's own highlight - hovered or selected - and only ever
/// applied for a pad, where hovered cannot happen; a pointer gets the ring
/// and nothing that moves. A paint-time transform, so the row's layout, the
/// scroll sums and the focus rectangles are all unaffected.
class FocusScale extends StatelessWidget {
  final ValueListenable<bool> highlight;
  final Widget child;

  const FocusScale({required this.highlight, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final onPad = AdaptiveLayout.maybeOf(context)?.data.inputDevice == InputDevice.dPad;
    if (!onPad) return child;
    // Not while a page is moving over this one. A hero flight measures the
    // card it is flying to on every frame of a pop, and the card grows the
    // moment it gets the selection back - mid-flight - so the flight kept
    // re-aiming and landed on a card of another size; on a push the card it
    // left was measured lifted and the flight began a few pixels off. So the
    // lift waits for the transition to finish, and is dropped in one frame
    // rather than animated away when one begins, so the hero measures the
    // card at its real size.
    final settling = ModalRoute.of(context)?.secondaryAnimation;
    return ValueListenableBuilder<bool>(
      valueListenable: highlight,
      child: child,
      builder: (context, lifted, child) {
        if (settling == null) return _scaled(lifted, settled: true, child: child!);
        return AnimatedBuilder(
          animation: settling,
          child: child,
          builder: (context, child) =>
              _scaled(lifted, settled: settling.status == AnimationStatus.dismissed, child: child!),
        );
      },
    );
  }

  Widget _scaled(bool lifted, {required bool settled, required Widget child}) => AnimatedScale(
        scale: lifted && settled ? kFocusScale : 1,
        duration: settled ? const Duration(milliseconds: 200) : Duration.zero,
        curve: Curves.easeOutCubic,
        child: child,
      );
}

/// Draws the ring: a stroke of the ring colour with a hairline of the edge
/// colour on either side of it, all inside the box.
class FocusRingPainter extends CustomPainter {
  final double opacity;
  final BorderRadius radius;
  final Color ring;
  final Color edge;

  const FocusRingPainter({
    required this.opacity,
    required this.radius,
    required this.ring,
    required this.edge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Both strokes centred on the same line, half the full width in from the
    // edge: the wider one in the edge colour, the ring on top of it, so a
    // hairline of the edge shows on each side.
    final line = radius.toRRect(rect).deflate(kFocusRingTotal / 2);
    canvas.drawRRect(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kFocusRingTotal
        ..color = edge.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kFocusRingWidth
        ..color = ring.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter old) =>
      old.opacity != opacity || old.radius != radius || old.ring != ring || old.edge != edge;
}
