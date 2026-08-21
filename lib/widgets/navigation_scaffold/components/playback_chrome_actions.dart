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
    // Two round buttons with nothing between them read as one lozenge.
    const gap = 8.0;
    return axis == Axis.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: buttons)
        : Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: buttons);
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
