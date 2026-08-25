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

  const DeferUntilSettled({
    required this.child,
    this.placeholder = const SizedBox.shrink(),
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
    if (_settled) return;

    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted || animation.isDismissed) {
      _settled = true;
      return;
    }

    if (identical(animation, _animation)) return;
    _animation?.removeStatusListener(_onStatus);
    _animation = animation..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _settled || !mounted) return;
    setState(() => _settled = true);
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _settled ? widget.child : widget.placeholder;
}
