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
