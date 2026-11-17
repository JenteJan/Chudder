import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// What sets a wide banner's words off from the picture behind them.
///
/// There used to be a shade for that: one round shape from the banner's corner,
/// the same for every item, so it fitted none of them. It darkened picture
/// nowhere near the words, ran on over whatever stood under the hero, and was
/// a colour of its own, which the page around it was not.
///
/// Now the words make the shape themselves. Each piece - the logo as it is
/// drawn, each line of text - pushes its right edge out, and the edge rounds
/// off from one to the next ([BannerTextBacking]). Inside that shape the
/// picture is partly wiped out, down to the page behind it, and partly
/// blurred ([BannerPictureMask]). The page behind is what the picture's left
/// and bottom edges already fade into, so the shape and the fades are one.

/// How far past each piece the shape reaches.
const double _pad = 20;

/// How soft the shape's edge is.
const double _feather = 48;

/// Over how far each corner of the shape rounds off.
const double _round = 90;

/// How much of the picture gives way to the page inside the shape. The rest
/// is the picture's blur.
const double _erase = 0.46;

/// How hard the picture is blurred inside the shape.
const double kBannerWordsBlur = 9;

/// A piece of the banner's words the shape is made around.
class BannerBackingTarget extends SingleChildRenderObjectWidget {
  const BannerBackingTarget({super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBackingTarget();
}

class _RenderBackingTarget extends RenderProxyBox {
  RenderBannerTextBacking? _owner;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject? node = parent;
    while (node != null && node is! RenderBannerTextBacking) {
      node = node.parent;
    }
    _owner = node as RenderBannerTextBacking?;
    _owner?._targets.add(this);
  }

  @override
  void detach() {
    _owner?._targets.remove(this);
    _owner = null;
    super.detach();
  }

  /// This piece's shapes in [ancestor]'s coordinates: one per line if it is
  /// text, so a short last line does not carry a full-width block; the part
  /// of its box a picture is drawn in if it is a logo; its box otherwise.
  List<Rect> rectsIn(RenderBox ancestor) {
    if (!hasSize || !attached) return const [];
    final paragraph = _findParagraph(this);
    if (paragraph == null || !paragraph.hasSize) {
      final drawn = _drawnImage(this);
      if (drawn != null) return [MatrixUtils.transformRect(drawn.$1.getTransformTo(ancestor), drawn.$2)];
      return [MatrixUtils.transformRect(getTransformTo(ancestor), Offset.zero & size)];
    }
    final plain = paragraph.text.toPlainText();
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: plain.length));
    // Runs on one line come back as separate boxes; one shape per line.
    final lines = <Rect>[];
    for (final box in boxes) {
      final rect = box.toRect();
      final index = lines.indexWhere((line) => (line.center.dy - rect.center.dy).abs() < rect.height / 2);
      if (index == -1) {
        lines.add(rect);
      } else {
        lines[index] = lines[index].expandToInclude(rect);
      }
    }
    final transform = paragraph.getTransformTo(ancestor);
    if (lines.isEmpty) return [MatrixUtils.transformRect(transform, Offset.zero & paragraph.size)];
    return [for (final line in lines) MatrixUtils.transformRect(transform, line)];
  }

  /// How visible this piece is: the product of the fades it is under, up to
  /// the backing. The outgoing header's shape fades out with its words.
  double opacityUpTo(RenderObject ancestor, Set<Animation<double>> fades) {
    var alpha = 1.0;
    RenderObject? node = parent;
    while (node != null && node != ancestor) {
      if (node is RenderAnimatedOpacity) {
        alpha *= node.opacity.value;
        fades.add(node.opacity);
      }
      if (node is RenderOpacity) alpha *= node.opacity;
      node = node.parent;
    }
    return alpha.clamp(0.0, 1.0);
  }

  /// A picture under [node] - a logo - and the part of its box it is drawn
  /// in: a logo fitted into a wide box covers only a part of it.
  static (RenderImage, Rect)? _drawnImage(RenderObject node) {
    if (node is RenderImage) {
      final image = node.image;
      if (image == null || !node.hasSize) return null;
      final input = Size(image.width / node.scale, image.height / node.scale);
      final fitted = applyBoxFit(node.fit ?? BoxFit.scaleDown, input, node.size).destination;
      final alignment = node.alignment.resolve(node.textDirection ?? TextDirection.ltr);
      return (node, alignment.inscribe(fitted, Offset.zero & node.size));
    }
    (RenderImage, Rect)? found;
    node.visitChildren((child) => found ??= _drawnImage(child));
    return found;
  }

  static RenderParagraph? _findParagraph(RenderObject node) {
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((child) => found ??= _findParagraph(child));
    return found;
  }
}

/// Gathers the [BannerBackingTarget]s under it into one shape, for the
/// [BannerPictureMask]s over the picture to cut the picture with.
///
/// It paints nothing itself. It is there to be found by the masks, and to
/// have the banner painted again when its words move or fade.
class BannerTextBacking extends SingleChildRenderObjectWidget {
  const BannerTextBacking({super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBannerTextBacking();
}

class RenderBannerTextBacking extends RenderProxyBox {
  final Set<_RenderBackingTarget> _targets = {};

  /// The fades the words are under. Their opacity layers update without a
  /// repaint, so the shape has to ask for one when they move.
  Set<Animation<double>> _fades = {};

  void _listenTo(Set<Animation<double>> fades) {
    for (final fade in _fades.difference(fades)) {
      fade.removeListener(markNeedsPaint);
    }
    for (final fade in fades.difference(_fades)) {
      fade.addListener(markNeedsPaint);
    }
    _fades = fades;
  }

  @override
  void detach() {
    _listenTo({});
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Only to hear about the fades: the masks over the picture, painted
    // before this, read the shape with [paintMask].
    _groups();
    super.paint(context, offset);
  }

  /// The pieces' shapes, one group per header: during a crossfade there are
  /// two, each as strong as its words.
  Map<double, List<Rect>> _groups() {
    final fades = <Animation<double>>{};
    final groups = <double, List<Rect>>{};
    for (final target in _targets) {
      final alpha = target.opacityUpTo(this, fades);
      if (alpha <= 0.01) continue;
      for (final rect in target.rectsIn(this)) {
        if (rect.isEmpty) continue;
        groups.putIfAbsent((alpha * 100).roundToDouble() / 100, () => []).add(rect);
      }
    }
    _listenTo(fades);
    return groups;
  }

  /// The shape, soft-edged, in white, drawn into [canvas] in [into]'s
  /// coordinates.
  ///
  /// The wipe draws it whole, a little smaller than the blur does, so that
  /// along the edge the blur takes over from the picture before the page
  /// shows through.
  void paintMask(Canvas canvas, RenderBox into, {required bool erase}) {
    if (!attached || !hasSize) return;
    final groups = _groups();
    if (groups.isEmpty) return;
    final strength = erase ? 1.0 : 1 - _erase;
    canvas
      ..save()
      ..transform(getTransformTo(into).storage);
    for (final MapEntry(key: alpha, value: rects) in groups.entries) {
      canvas.drawPath(
        _envelope(rects, _pad + (erase ? -_feather * 0.25 : 0), _round),
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * strength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _feather / 2),
      );
    }
    canvas.restore();
  }

  /// One free-formed shape around [rects], open to the left.
  ///
  /// The right edge starts as the hard outline - [pad] past each line's end,
  /// [pad] above and below it - which is then grown by [round] up and down and
  /// smoothed over the same distance. Grown first, so the smoothing only ever
  /// rounds outwards: no line's end comes nearer the edge than [pad]. Every
  /// corner - a logo narrower than the line under it, the step from the genres
  /// to the summary, the top and the bottom - rounds off over the same
  /// distance.
  static Path _envelope(List<Rect> rects, double pad, double round) {
    var left = double.infinity, top = double.infinity, bottom = -double.infinity;
    for (final rect in rects) {
      left = math.min(left, rect.left);
      top = math.min(top, rect.top);
      bottom = math.max(bottom, rect.bottom);
    }
    left -= pad;
    final far = left - 2000;
    const step = 2.0;
    final reach = math.max(round, step);
    final radius = (reach / step).round();
    final from = top - pad - reach * 2;
    final count = ((bottom + pad + reach * 2 - from) / step).ceil() + 1;
    double yAt(int i) => from + i * step;

    final outline = List<double>.generate(count, (i) {
      final y = yAt(i);
      var x = left;
      for (final rect in rects) {
        if (y >= rect.top - pad && y <= rect.bottom + pad) x = math.max(x, rect.right + pad);
      }
      return x;
    });
    final grown = List<double>.generate(count, (i) {
      var x = left;
      for (var j = math.max(0, i - radius); j <= math.min(count - 1, i + radius); j++) {
        x = math.max(x, outline[j]);
      }
      return x;
    });
    final sigma = radius / 2.5;
    final weights = [for (var k = -radius; k <= radius; k++) math.exp(-(k * k) / (2 * sigma * sigma))];
    final edge = List<double>.generate(count, (i) {
      var sum = 0.0, total = 0.0;
      for (var k = -radius; k <= radius; k++) {
        final j = i + k;
        final value = j < 0 || j >= count ? left : grown[j];
        sum += value * weights[k + radius];
        total += weights[k + radius];
      }
      return sum / total;
    });

    final path = Path()..moveTo(far, yAt(0));
    for (var i = 0; i < count; i++) {
      path.lineTo(edge[i], yAt(i));
    }
    path
      ..lineTo(far, yAt(count - 1))
      ..close();
    return path;
  }
}

/// The banner's picture, cut by the shape of the [BannerTextBacking] under
/// [shape]: with [erase], the sharp picture wiped out inside it so the page
/// behind shows through; without, a blurred copy over it shown only inside
/// it - a blur with an edge that fades out, which a backdrop filter cannot do.
///
/// Lies exactly over the picture's box, before the words.
class BannerPictureMask extends SingleChildRenderObjectWidget {
  const BannerPictureMask({required this.shape, this.erase = false, super.child, super.key});

  final GlobalKey shape;
  final bool erase;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBannerPictureMask(shape, erase);

  @override
  void updateRenderObject(BuildContext context, RenderBannerPictureMask renderObject) => renderObject
    ..shape = shape
    ..erase = erase;
}

class RenderBannerPictureMask extends RenderProxyBox {
  RenderBannerPictureMask(this._shape, this._erase);

  GlobalKey _shape;
  set shape(GlobalKey value) {
    if (value == _shape) return;
    _shape = value;
    markNeedsPaint();
  }

  bool _erase;
  set erase(bool value) {
    if (value == _erase) return;
    _erase = value;
    markNeedsPaint();
  }

  /// The mask is soft all over; a quarter of the pixels lose nothing.
  static const _scale = 0.25;

  ui.Image? _mask;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final owner = _shape.currentContext?.findRenderObject();
    final width = (size.width * _scale).ceil();
    final height = (size.height * _scale).ceil();
    if (child == null || owner is! RenderBannerTextBacking || width <= 0 || height <= 0) {
      layer = null;
      // The sharp picture as it is; the blur not at all.
      if (_erase) super.paint(context, offset);
      return;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_scale);
    owner.paintMask(canvas, this, erase: _erase);
    final picture = recorder.endRecording();
    final mask = picture.toImageSync(width, height);
    picture.dispose();
    _mask?.dispose();
    _mask = mask;
    final shaderLayer = (layer as ShaderMaskLayer?) ?? ShaderMaskLayer();
    shaderLayer
      // Clamped: the mask is a quarter the size, and sampled between its
      // pixels it mixed in the nothing past its edge - a line down the
      // picture's side where it was not wiped out.
      ..shader = ImageShader(
        mask,
        TileMode.clamp,
        TileMode.clamp,
        (Matrix4.translationValues(1, 1, 0)..scaleByDouble(1 / _scale, 1 / _scale, 1, 1)).storage,
      )
      // A pixel past the box all round: at a fractional edge, as in a resize,
      // the picture and the mask each covered the edge pixel in part, and
      // what the one left over the other showed as a line.
      ..maskRect = (offset & size).inflate(1)
      ..blendMode = _erase ? BlendMode.dstOut : BlendMode.dstIn;
    context.pushLayer(shaderLayer, super.paint, offset);
    layer = shaderLayer;
  }

  @override
  void dispose() {
    _mask?.dispose();
    _mask = null;
    super.dispose();
  }
}
