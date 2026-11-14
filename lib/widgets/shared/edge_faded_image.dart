import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:chudder/routes/zoom_opening.dart';

/// How far in from each side a picture fades to nothing, as a share of its
/// width or height. The same straight ramps [FadeEdges] draws.
@immutable
class EdgeFades {
  const EdgeFades({this.top = 0, this.bottom = 0, this.left = 0, this.right = 0});

  final double top;
  final double bottom;
  final double left;
  final double right;

  bool get any => top > 0 || bottom > 0 || left > 0 || right > 0;

  @override
  bool operator ==(Object other) =>
      other is EdgeFades && other.top == top && other.bottom == bottom && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(top, bottom, left, right);
}

/// A picture cover-fitted into its box with its edges faded out, drawn in one
/// pass.
///
/// [FadeEdges] fades whatever it is given by masking it: the child is drawn
/// into a layer of its own, and the mask over that into another. On a still
/// page that is nothing. Under the opening zoom, which draws the page anew on
/// every frame, it was the backdrop's two full-size layers every frame - the
/// most of what made a film page's last frames before landing stall on a
/// large window.
///
/// Here the picture is drawn as a mesh instead, its points carrying how much
/// of it shows, so the fade happens as it is drawn. The fades are straight
/// ramps either way; the corners, where two of them meet, are cut finer so
/// the mesh's straight lines follow the curve two masks make there.
class EdgeFadedImage extends StatefulWidget {
  const EdgeFadedImage({
    required this.image,
    this.fades = const EdgeFades(),
    this.alignment = Alignment.topCenter,
    this.fadeIn = Duration.zero,
    super.key,
  });

  final ImageProvider image;
  final EdgeFades fades;
  final Alignment alignment;

  /// How long a picture takes to appear once it has arrived. One already in
  /// memory is simply there.
  final Duration fadeIn;

  @override
  State<EdgeFadedImage> createState() => EdgeFadedImageState();
}

class EdgeFadedImageState extends State<EdgeFadedImage> with SingleTickerProviderStateMixin {
  @visibleForTesting
  ui.Image? get image => _info?.image;

  /// How far the picture has faded in, 0 to 1.
  @visibleForTesting
  double get shown => _appear.value;

  ImageStream? _stream;
  ImageInfo? _info;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage, onError: (_, _) {});
  late final AnimationController _appear = AnimationController(vsync: this, duration: widget.fadeIn, value: 0)
    ..addListener(_reportChange);

  /// The page's opening zoom draws from a picture of the page; this sits
  /// behind a repaint boundary that keeps it from seeing the change.
  void _reportChange() {
    if (mounted) ZoomOpening.contentChanged(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(EdgeFadedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _appear.duration = widget.fadeIn;
    if (oldWidget.image != widget.image) _resolve();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    // The picture already showing stays until the next one is here.
    final first = _info == null;
    _info?.dispose();
    setState(() => _info = info);
    _reportChange();
    if (!first) return;
    if (synchronousCall || widget.fadeIn == Duration.zero) {
      _appear.value = 1;
    } else {
      _appear.forward();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    return CustomPaint(
      size: Size.infinite,
      painter: image == null
          ? null
          : _EdgeFadedPainter(
              image: image,
              fades: widget.fades,
              alignment: widget.alignment,
              opacity: _appear,
            ),
    );
  }
}

class _EdgeFadedPainter extends CustomPainter {
  _EdgeFadedPainter({required this.image, required this.fades, required this.alignment, required this.opacity})
      : super(repaint: opacity);

  final ui.Image image;
  final EdgeFades fades;
  final Alignment alignment;
  final Animation<double> opacity;

  /// Cuts across each corner ramp: enough that the mesh's straight edges and
  /// the masks' curve differ by less than a step of colour.
  static const int _cornerSteps = 8;

  static List<double> _stops(double start, double end) {
    final stops = <double>[0];
    if (start > 0) {
      for (var i = 1; i <= _cornerSteps; i++) {
        stops.add(start * i / _cornerSteps);
      }
    }
    if (end > 0) {
      for (var i = 0; i < _cornerSteps; i++) {
        stops.add(1 - end + end * i / _cornerSteps);
      }
    }
    stops.add(1);
    final unique = <double>[];
    for (final stop in stops) {
      if (unique.isEmpty || stop > unique.last) unique.add(stop);
    }
    return unique;
  }

  static double _ramp(double t, double start, double end) {
    if (start > 0 && t < start) return t / start;
    if (end > 0 && t > 1 - end) return (1 - t) / end;
    return 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final alpha = Curves.easeOut.transform(opacity.value);
    if (alpha <= 0) return;

    // Cover-fit, as [BoxFit.cover] with [alignment] would.
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, imageSize, size);
    final source = alignment.inscribe(fitted.source, Offset.zero & imageSize);

    if (!fades.any) {
      canvas.drawImageRect(
        image,
        source,
        Offset.zero & size,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, alpha),
      );
      return;
    }

    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..shader = ImageShader(image, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage,
          filterQuality: FilterQuality.medium);

    final xs = _stops(fades.left, fades.right);
    final ys = _stops(fades.top, fades.bottom);
    final positions = <Offset>[];
    final coordinates = <Offset>[];
    final colors = <Color>[];
    for (final y in ys) {
      for (final x in xs) {
        positions.add(Offset(x * size.width, y * size.height));
        coordinates.add(Offset(source.left + x * source.width, source.top + y * source.height));
        final a = _ramp(x, fades.left, fades.right) * _ramp(y, fades.top, fades.bottom) * alpha;
        // Premultiplied white: modulating the picture by it fades it.
        colors.add(Color.fromRGBO(255, 255, 255, a));
      }
    }
    final indices = <int>[];
    final columns = xs.length;
    for (var row = 0; row < ys.length - 1; row++) {
      for (var column = 0; column < columns - 1; column++) {
        final a = row * columns + column;
        final b = a + 1;
        final c = a + columns;
        final d = c + 1;
        indices.addAll([a, b, c, b, d, c]);
      }
    }
    final vertices = ui.Vertices(
      VertexMode.triangles,
      positions,
      textureCoordinates: coordinates,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
    vertices.dispose();
  }

  @override
  bool shouldRepaint(_EdgeFadedPainter old) =>
      old.image != image || old.fades != fades || old.alignment != alignment || old.opacity != opacity;
}
