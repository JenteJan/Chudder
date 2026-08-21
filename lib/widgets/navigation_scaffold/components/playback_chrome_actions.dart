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
class PlaybackChromeActions extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final buttons = [
      SyncPlayButton(background: background, extended: extended),
      CastButton(background: background, extended: extended),
    ];
    return axis == Axis.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: buttons)
        : Column(mainAxisSize: MainAxisSize.min, children: buttons);
  }
}

/// The faint surface fill the app bar's buttons share, so anything that opts
/// into [PlaybackChromeActions.background] matches them exactly.
ButtonStyle chromeButtonStyle(BuildContext context) {
  return IconButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
  );
}
