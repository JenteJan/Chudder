import 'package:flutter/widgets.dart';

/// Where a minimized surface shows the video: the picture's rect on screen and
/// how round its corners are, so the full-screen player can grow out of it and
/// shrink back into it.
class VideoSurfaceFrame {
  const VideoSurfaceFrame({required this.rect, required this.radius});

  /// In global coordinates.
  final Rect rect;
  final double radius;
}

/// The minimized surfaces on screen right now - the floating window, the bar's
/// thumbnail - so the full-screen player knows where to fly from and to.
///
/// A registry rather than a Hero: the surfaces can sit above the router (over
/// a details page, where Home's own copy is covered), and a Hero there has no
/// route to be found in. Each surface signs in with a key on the box that
/// holds its picture; the one signed in last is the one on top.
class MinimizedVideoSurfaces {
  MinimizedVideoSurfaces._();

  static final List<_Surface> _surfaces = [];

  static void register(GlobalKey key, {required double radius}) {
    _surfaces.removeWhere((surface) => surface.key == key);
    _surfaces.add(_Surface(key, radius));
  }

  static void unregister(GlobalKey key) => _surfaces.removeWhere((surface) => surface.key == key);

  /// The picture on the surface on top, once it has been laid out - null in the
  /// frame a surface is mounted in, when its box exists but has no size yet.
  static VideoSurfaceFrame? get top {
    for (final surface in _surfaces.reversed) {
      final box = surface.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      return VideoSurfaceFrame(rect: box.localToGlobal(Offset.zero) & box.size, radius: surface.radius);
    }
    return null;
  }

  @visibleForTesting
  static void clear() => _surfaces.clear();
}

class _Surface {
  const _Surface(this.key, this.radius);

  final GlobalKey key;
  final double radius;
}
