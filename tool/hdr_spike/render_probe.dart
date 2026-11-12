// A fixed scene for comparing engine builds pixel for pixel: gradients, text,
// blur, shadows, clipping, translucency and a decoded image. Nothing animates
// and nothing loads from the network. Build with
// `flutter build windows -t tool/hdr_spike/render_probe.dart`.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Rubik', useMaterial3: true, colorSchemeSeed: Colors.deepOrange),
      home: const Scaffold(body: _Scene()),
    );
  }
}

class _Scene extends StatelessWidget {
  const _Scene();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Backdrop: a smooth gradient (banding shows up here first).
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B1026), Color(0xFF3A1C71), Color(0xFFD76D77), Color(0xFFFFAF7B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      Positioned.fill(child: CustomPaint(painter: _Pattern())),
      // A poster-like card with a shadow and rounded clip.
      Positioned(
        left: 60,
        top: 60,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 300,
            height: 420,
            child: Stack(children: [
              Positioned.fill(child: Image(image: _CheckerImage(), fit: BoxFit.cover)),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 60, 16, 16),
                    child: Text('Sprite Fright', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      // Frosted panel over the pattern.
      Positioned(
        left: 420,
        top: 80,
        width: 520,
        height: 300,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: Colors.white.withValues(alpha: 0.12),
              padding: const EdgeInsets.all(24),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Continue watching', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600)),
                SizedBox(height: 12),
                Text(
                  'The quick brown fox jumps over the lazy dog. 0123456789 — äöü ß é ñ',
                  style: TextStyle(color: Colors.white70, fontSize: 17),
                ),
                SizedBox(height: 18),
                LinearProgressIndicator(value: 0.62, minHeight: 6),
              ]),
            ),
          ),
        ),
      ),
      // Buttons, chips and an icon row at fixed positions.
      Positioned(
        left: 420,
        top: 420,
        child: Row(children: [
          FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.play_arrow), label: const Text('Play')),
          const SizedBox(width: 16),
          OutlinedButton(onPressed: () {}, child: const Text('Trailer')),
          const SizedBox(width: 16),
          const Chip(label: Text('4K HDR')),
          const SizedBox(width: 16),
          Opacity(opacity: 0.5, child: Icon(Icons.favorite, color: Colors.pink.shade200, size: 40)),
        ]),
      ),
      // HDR test: a patch at 4x SDR white in extended sRGB, and a ramp from
      // 1x to 4x. An SDR engine clips both to plain white.
      Positioned(
        right: 40,
        bottom: 40,
        child: Row(children: [
          Container(
            width: 120,
            height: 100,
            color: const Color.from(alpha: 1, red: 4, green: 4, blue: 4, colorSpace: ui.ColorSpace.extendedSRGB),
          ),
          const SizedBox(width: 20),
          Container(
            width: 240,
            height: 100,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
                Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ui.ColorSpace.extendedSRGB),
                Color.from(alpha: 1, red: 4, green: 4, blue: 4, colorSpace: ui.ColorSpace.extendedSRGB),
              ]),
            ),
          ),
        ]),
      ),
      // Thin lines and small text: anti-aliasing differences show here.
      Positioned(
        left: 60,
        top: 520,
        child: CustomPaint(size: const Size(880, 120), painter: _Lines()),
      ),
    ]);
  }
}

class _Pattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(Offset((i * 97) % size.width, (i * 53) % size.height), 20.0 + (i % 7) * 9, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Lines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 30; i++) {
      final a = i / 30 * math.pi;
      canvas.drawLine(Offset(60, 60), Offset(60 + 55 * math.cos(a), 60 - 55 * math.sin(a)), paint);
    }
    canvas.drawArc(const Rect.fromLTWH(160, 10, 100, 100), 0.3, 4.5, false, paint..strokeWidth = 3);
    final tp = TextPainter(
      text: const TextSpan(text: 'small 11px text at the edge of legibility', style: TextStyle(color: Colors.white, fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(300, 50));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A decoded image without assets or network: a 64x64 pattern scaled up.
class _CheckerImage extends ImageProvider<_CheckerImage> {
  @override
  Future<_CheckerImage> obtainKey(ImageConfiguration configuration) async => this;

  @override
  ImageStreamCompleter loadImage(_CheckerImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_make());

  static Future<ImageInfo> _make() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()..color = HSVColor.fromAHSV(1, (x * 5.6) % 360, 0.6, 0.3 + y / 128).toColor(),
        );
      }
    }
    final image = await recorder.endRecording().toImage(64, 64);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) => other is _CheckerImage;

  @override
  int get hashCode => 1;
}
