import 'package:flutter/material.dart';

import 'package:chudder/screens/video_player/components/minimized_video_surfaces.dart';
import 'package:chudder/screens/video_player/video_player.dart';

/// The route the full-screen player opens on.
///
/// It draws no transition of its own: the player inside animates itself off
/// the route's animation - the picture growing out of the minimized surface it
/// was opened from (see [from]) or fading in when there is none, the black
/// behind it fading up over the page, the controls arriving once the picture
/// has landed. A page transition on top of that would zoom or fade the flying
/// picture along with everything else, which is exactly the jump this exists
/// to avoid.
///
/// The page underneath stays still as well: the player dims it itself, so the
/// zoom the desktop pages play under one another would only fight with that.
class VideoPlayerRoute extends PageRoute<void> {
  VideoPlayerRoute({this.from, this.builder, super.settings});

  /// The picture this route opens out of, in global coordinates. Null opens
  /// with a fade instead - starting a film from its page, say.
  final VideoSurfaceFrame? from;

  /// The page to build; the player unless a test says otherwise.
  final WidgetBuilder? builder;

  /// This route, from anywhere inside it.
  static VideoPlayerRoute? of(BuildContext context) {
    final route = ModalRoute.of(context);
    return route is VideoPlayerRoute ? route : null;
  }

  /// Long enough to read as a window settling into place rather than
  /// snapping there; the way back is a little quicker, as it always is.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder?.call(context) ?? const VideoPlayer();

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
