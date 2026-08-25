import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the player's controls are on screen.
///
/// Shared because more than one thing needs to know. The seek indicator binds
/// the arrow keys through a raw keyboard handler, which runs before focus is
/// consulted at all - so while the controls are up and being navigated with a
/// remote, it would take the left and right presses meant for moving between
/// them and seek instead. Seeking by arrow belongs to the player with nothing
/// on top of it.
final playerControlsVisibleProvider = StateProvider<bool>((ref) => false);

/// Whether the next-episode card is on screen.
///
/// The card arrives after the controls have timed out, so from the player's
/// point of view nothing is up and every remote press is spent waking its own
/// controls back up - which also drags focus off the card and onto play/pause.
/// The arrow keys are meanwhile still bound to seeking through the same raw
/// handler described above. Between them the card's buttons could never be
/// reached at all, so while it is up the player stands down entirely and the
/// pad belongs to the card.
final nextUpVisibleProvider = StateProvider<bool>((ref) => false);

/// Seconds of seek that have been asked for but not yet committed.
///
/// The arrow keys accumulate: each press adds to a running total and a single
/// seek is issued once the pressing stops, so holding one down does not ask the
/// player to reopen the stream a dozen times on the way. That total lived
/// inside the seek indicator, which draws its own floating "30 seconds" box -
/// so the scrubber and the clock sat still while it counted, and the only thing
/// that moved was a number in the middle of the screen.
///
/// Published here so the controls can show the same travel a remote gets: the
/// bar moving and the time counting toward where you are going.
final pendingSeekSecondsProvider = StateProvider<int>((ref) => 0);
