import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Pictures of the app, for checking the readiness detector by eye. Only used
/// when the run asks for screenshots; the numbers of such a run are not used.
class BenchCapture {
  BenchCapture(this.scale);

  final double scale;
  final GlobalKey boundaryKey = GlobalKey(debugLabel: 'perf-bench-capture');

  Future<ui.Image?> capture() async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.attached) return null;
    try {
      return await boundary.toImage(pixelRatio: scale);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePng(ui.Image image, String path) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  /// How different two captures are: the share of pixels whose colour moved
  /// by more than 24 in any channel.
  static Future<double?> difference(ui.Image a, ui.Image b) async {
    if (a.width != b.width || a.height != b.height) return 1;
    final ByteData? da = await a.toByteData();
    final ByteData? db = await b.toByteData();
    if (da == null || db == null) return null;
    final pa = da.buffer.asUint8List();
    final pb = db.buffer.asUint8List();
    var changed = 0;
    for (var i = 0; i + 3 < pa.length; i += 4) {
      if ((pa[i] - pb[i]).abs() > 24 || (pa[i + 1] - pb[i + 1]).abs() > 24 || (pa[i + 2] - pb[i + 2]).abs() > 24) {
        changed++;
      }
    }
    return changed / (pa.length / 4);
  }
}
