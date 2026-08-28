import 'package:flutter/material.dart';

import 'package:fladder/screens/video_player/components/cast_button.dart';
import 'package:fladder/widgets/syncplay/syncplay_button.dart';

/// SyncPlay and Cast, side by side, for the app's chrome.
///
/// Both start sessions that outlive whatever screen you happen to be on — you
/// can join a group or connect to a device before choosing anything to play —
/// so they belong in the chrome rather than on the one screen that thought to
/// offer them. Inside the video player the two buttons are used bare instead:
/// the controls provide their own backdrop there.
/// The chrome pair currently on screen, for [GlobalFallbackTraversalPolicy].
///
/// The corner pair floats over the content rather than sitting above it in any
/// list, so pressing up from the top of a page has no reading order leading to
/// it and the selection simply stops. The policy asks here instead.
///
/// A plain node and deliberately not a [FocusScopeNode]: directional traversal
/// only ever considers the nearest enclosing scope, so putting these two
/// buttons in one of their own trapped the selection on them with nothing to
/// move to. This one holds nothing and is skipped by traversal - it exists only
/// so the buttons beneath it can be found.
/// Whichever pair is up, newest first. Pages stack: an actor's page pushed over
/// a show brings its own row, and when it pops the show's must be the one
/// found again. One variable could not do that - the actor page's dispose
/// cleared it, and back on the show nothing went up to SyncPlay and Cast.
final List<FocusNode> _chromeAnchors = [];
FocusNode? get chromeActionsAnchor => _chromeAnchors.isEmpty ? null : _chromeAnchors.last;

class PlaybackChromeActions extends StatefulWidget {
  const PlaybackChromeActions({
    super.key,
    this.background = true,
    this.axis = Axis.horizontal,
    this.extended = false,
  });

  /// Gives each button the same faint surface fill the app bar's other icon
  /// buttons have, so they read as chrome over artwork.
  final bool background;

  /// Stacked for a navigation rail, which is 90px wide collapsed: two icon
  /// buttons side by side do not fit in it.
  final Axis axis;

  /// Labelled rows, for an expanded rail where every other entry is one.
  final bool extended;

  @override
  State<PlaybackChromeActions> createState() => _PlaybackChromeActionsState();
}

class _PlaybackChromeActionsState extends State<PlaybackChromeActions> {
  final FocusNode _anchor = FocusNode(debugLabel: 'chromeActions', skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    _chromeAnchors.add(_anchor);
  }

  @override
  void dispose() {
    _chromeAnchors.remove(_anchor);
    _anchor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.background;
    final extended = widget.extended;
    final axis = widget.axis;
    final buttons = [
      SyncPlayButton(background: background, extended: extended),
      CastButton(background: background, extended: extended),
    ];
    // Two round buttons with nothing between them read as one lozenge.
    const gap = 8.0;
    return Focus(
      focusNode: _anchor,
      canRequestFocus: false,
      skipTraversal: true,
      child: axis == Axis.horizontal
          ? Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: buttons)
          : Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: buttons),
    );
  }
}

/// The app bar's own button: the same faint surface fill, and the same 50px
/// square its menu button occupies, so the row reads as one set rather than
/// three sizes.
ButtonStyle chromeButtonStyle(BuildContext context) {
  return IconButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
    fixedSize: const Size.square(50),
  );
}
