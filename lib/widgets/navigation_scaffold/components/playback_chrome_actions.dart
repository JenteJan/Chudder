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
  const PlaybackChromeActions({super.key, this.background = true});

  /// Gives each button the same faint surface fill the app bar's other icon
  /// buttons have, so they read as chrome over artwork.
  final bool background;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SyncPlayButton(background: background),
        CastButton(background: background),
      ],
    );
  }
}

/// The faint surface fill the app bar's buttons share, so anything that opts
/// into [PlaybackChromeActions.background] matches them exactly.
ButtonStyle chromeButtonStyle(BuildContext context) {
  return IconButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
  );
}
