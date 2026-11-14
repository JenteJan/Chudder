import 'package:flutter/material.dart';

/// Holds a subtree back until the route it belongs to has finished animating in.
///
/// A detail page used to build all of itself on the frame it was pushed — every
/// row of posters, and the forty-odd image requests that come with them — which
/// is the most expensive thing that can happen while a transition is trying to
/// run. Nothing below the fold is worth that: it cannot be seen during the
/// animation, and building it is what stops the part that can be seen from
/// arriving in time.
///
/// Held back, the first frame is only the header and the row under it, which is
/// cheap enough to be on screen for the whole transition, and the images those
/// need are no longer queued behind images for rows nobody is looking at.
///
/// A page opened where there is no transition to wait for — restored on launch,
/// or reached with animations off — builds everything at once, as it should.
class DeferUntilSettled extends StatefulWidget {
  /// What to hold the space with meanwhile. Nothing, by default: below the fold
  /// there is no space to hold, and reserving it would only lengthen the
  /// scrollbar for content that is not there yet.
  final Widget placeholder;

  final Widget child;

  /// How many frames after the route has settled to wait still. Rows given
  /// 0, 1, 2... arrive one a frame from the top, rather than all of them -
  /// every poster, name and picture under a header - in one frame that
  /// takes several.
  final int order;

  const DeferUntilSettled({
    required this.child,
    this.placeholder = const SizedBox.shrink(),
    this.order = 0,
    super.key,
  });

  @override
  State<DeferUntilSettled> createState() => _DeferUntilSettledState();
}

class _DeferUntilSettledState extends State<DeferUntilSettled> {
  bool _settled = false;
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _check();
  }

  void _check() {
    if (_settled || !mounted) return;
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (route == null || animation == null) return _settle();

    // A pushed page is built once offstage first, for its heroes to find
    // where they land, and its animation reads as complete on that frame -
    // which once let everything through on the very frame this is here to
    // keep it off. Asked again on the next, once the page is on its way in.
    if (route.offstage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
      return;
    }

    if (animation.isCompleted || animation.isDismissed) return _settle();

    if (identical(animation, _animation)) return;
    _animation?.removeStatusListener(_onStatus);
    _animation = animation..addStatusListener(_onStatus);
  }

  void _settle() {
    if (_settled || _waiting) return;
    if (widget.order > 0) {
      _waiting = true;
      _afterFrames(widget.order);
      return;
    }
    if (_built) {
      setState(() => _settled = true);
    } else {
      _settled = true;
    }
  }

  /// Settling, [order] frames on.
  bool _waiting = false;

  void _afterFrames(int frames) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (frames > 1) {
        // Nothing else may be asking for frames once the route has settled.
        WidgetsBinding.instance.scheduleFrame();
        return _afterFrames(frames - 1);
      }
      setState(() => _settled = true);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Whether [build] has run, after which settling needs a rebuild.
  bool _built = false;

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _settled || !mounted) return;
    _settle();
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    return _settled ? widget.child : widget.placeholder;
  }
}
