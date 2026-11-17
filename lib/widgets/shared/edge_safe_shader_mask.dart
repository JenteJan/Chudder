import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A [ShaderMask] that leaves no line along its edges.
///
/// A shader mask lays its shader over exactly its box. Where the box's edge
/// falls inside a pixel - at most window sizes, now and then, which is why it
/// came and went in a resize - that pixel is covered by the child in part and
/// by the mask in part, and what the mask did not cover kept the child as it
/// was. A fade to nothing at the edge ended in a hairline of the picture it
/// had faded out.
///
/// This one's mask reaches a pixel past the box all round, so every pixel the
/// child touches is masked whole. The shader is made for that larger rect:
/// [shaderCallback] gets it, a pixel bigger each way than the box, with the
/// box at (1, 1).
class EdgeSafeShaderMask extends SingleChildRenderObjectWidget {
  const EdgeSafeShaderMask({
    required this.shaderCallback,
    this.blendMode = BlendMode.modulate,
    super.child,
    super.key,
  });

  final ShaderCallback shaderCallback;
  final BlendMode blendMode;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderEdgeSafeShaderMask(shaderCallback, blendMode);

  @override
  void updateRenderObject(BuildContext context, RenderEdgeSafeShaderMask renderObject) => renderObject
    ..shaderCallback = shaderCallback
    ..blendMode = blendMode;
}

class RenderEdgeSafeShaderMask extends RenderProxyBox {
  RenderEdgeSafeShaderMask(this._shaderCallback, this._blendMode);

  ShaderCallback _shaderCallback;
  set shaderCallback(ShaderCallback value) {
    if (value == _shaderCallback) return;
    _shaderCallback = value;
    markNeedsPaint();
  }

  BlendMode _blendMode;
  set blendMode(BlendMode value) {
    if (value == _blendMode) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      layer = null;
      return;
    }
    final maskRect = (offset & size).inflate(1);
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = _shaderCallback(Offset.zero & maskRect.size)
      ..maskRect = maskRect
      ..blendMode = _blendMode;
    context.pushLayer(layer!, super.paint, offset);
  }
}
