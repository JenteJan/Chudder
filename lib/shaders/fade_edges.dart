import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class FadeEdges extends SingleChildRenderObjectWidget {
  const FadeEdges({
    super.key,
    required Widget child,
    this.topFade = 0.0,
    this.bottomFade = 0.0,
    this.leftFade = 0.0,
    this.rightFade = 0.0,
  }) : super(child: child);

  final double topFade;
  final double bottomFade;
  final double leftFade;
  final double rightFade;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFadeEdges(
      topFade: topFade,
      bottomFade: bottomFade,
      leftFade: leftFade,
      rightFade: rightFade,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFadeEdges renderObject) {
    renderObject
      ..topFade = topFade
      ..bottomFade = bottomFade
      ..leftFade = leftFade
      ..rightFade = rightFade;
  }
}

class RenderFadeEdges extends RenderProxyBox {
  RenderFadeEdges({
    required double topFade,
    required double bottomFade,
    required double leftFade,
    required double rightFade,
  })  : _topFade = topFade.clamp(0.0, 0.5),
        _bottomFade = bottomFade.clamp(0.0, 0.5),
        _leftFade = leftFade.clamp(0.0, 0.5),
        _rightFade = rightFade.clamp(0.0, 0.5);

  double _topFade;
  double get topFade => _topFade;
  set topFade(double value) {
    value = value.clamp(0.0, 0.5);
    if (_topFade == value) return;
    _topFade = value;
    _fadeChanged();
  }

  double _bottomFade;
  double get bottomFade => _bottomFade;
  set bottomFade(double value) {
    value = value.clamp(0.0, 0.5);
    if (_bottomFade == value) return;
    _bottomFade = value;
    _fadeChanged();
  }

  double _leftFade;
  double get leftFade => _leftFade;
  set leftFade(double value) {
    value = value.clamp(0.0, 0.5);
    if (_leftFade == value) return;
    _leftFade = value;
    _fadeChanged();
  }

  double _rightFade;
  double get rightFade => _rightFade;
  set rightFade(double value) {
    value = value.clamp(0.0, 0.5);
    if (_rightFade == value) return;
    _rightFade = value;
    _fadeChanged();
  }

  bool get _fadesVertically => _topFade > 0 || _bottomFade > 0;
  bool get _fadesHorizontally => _leftFade > 0 || _rightFade > 0;
  bool get _needsFade => _fadesVertically || _fadesHorizontally;

  void _fadeChanged() {
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  // Masks as layers of their own rather than dstIn draws on the canvas inside
  // a saveLayer. That only held while the child painted onto the same canvas:
  // a child with a layer of its own - an AnimatedOpacity, a RepaintBoundary -
  // is painted into a separate picture, the masks landed outside the
  // saveLayer, and they erased whatever was already drawn below instead of
  // fading the child. On a window with a transparent background that punched
  // a hole through to the desktop.
  final LayerHandle<ShaderMaskLayer> _verticalMask = LayerHandle<ShaderMaskLayer>();
  final LayerHandle<ShaderMaskLayer> _horizontalMask = LayerHandle<ShaderMaskLayer>();

  @override
  bool get alwaysNeedsCompositing => child != null && _needsFade;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !_needsFade) {
      _verticalMask.layer = null;
      _horizontalMask.layer = null;
      super.paint(context, offset);
      return;
    }

    if (!_fadesVertically) _verticalMask.layer = null;
    if (!_fadesHorizontally) _horizontalMask.layer = null;

    void paintHorizontal(PaintingContext context, Offset offset) {
      if (!_fadesHorizontally) {
        super.paint(context, offset);
        return;
      }
      final mask = _horizontalMask.layer ??= ShaderMaskLayer();
      mask
        ..shader = _gradient(_leftFade, _rightFade, Alignment.centerLeft, Alignment.centerRight)
        ..maskRect = offset & size
        ..blendMode = BlendMode.dstIn;
      context.pushLayer(mask, super.paint, offset);
    }

    if (!_fadesVertically) {
      paintHorizontal(context, offset);
      return;
    }
    final mask = _verticalMask.layer ??= ShaderMaskLayer();
    mask
      ..shader = _gradient(_topFade, _bottomFade, Alignment.topCenter, Alignment.bottomCenter)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(mask, paintHorizontal, offset);
  }

  /// A mask shader in the child's own coordinates, which is where a
  /// [ShaderMaskLayer] draws it.
  Shader _gradient(double startFade, double endFade, Alignment begin, Alignment end) {
    final colors = <Color>[];
    final stops = <double>[];

    if (startFade > 0) {
      colors.addAll([Colors.transparent, Colors.white]);
      stops.addAll([0.0, startFade]);
    } else {
      colors.add(Colors.white);
      stops.add(0.0);
    }

    if (endFade > 0) {
      colors.addAll([Colors.white, Colors.transparent]);
      stops.addAll([1.0 - endFade, 1.0]);
    } else {
      colors.add(Colors.white);
      stops.add(1.0);
    }

    return LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(Offset.zero & size);
  }

  @override
  void dispose() {
    _verticalMask.layer = null;
    _horizontalMask.layer = null;
    super.dispose();
  }
}
