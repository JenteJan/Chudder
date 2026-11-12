import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/arguments_provider.dart';
import 'package:chudder/widgets/full_screen_helpers/full_screen_helper_desktop.dart'
    if (dart.library.html) 'package:chudder/widgets/full_screen_helpers/full_screen_helper_web.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

final FullScreenHelper fullScreenHelper = FullScreenHelper.instantiate();

/// What the window is doing, as last read from the window itself.
enum WindowMode {
  normal,
  maximized,
  fullScreen,
  minimized,
}

/// The one place the app learns what the window is doing.
///
/// Every surface that shows the window's state - the player's full-screen
/// button, the title bar's maximise button, the drag strip - reads this, and
/// only [fullScreenHelper] writes it, after reading the window back. They used
/// to keep copies of their own, fed by `window_manager`'s events, and the copies
/// drifted: that plugin stops reporting maximise and unmaximise for good after
/// a round trip through full screen from a maximised window, and full screen
/// of our own making it never reports at all.
final windowModeProvider = Provider<WindowMode>((ref) {
  final mode = fullScreenHelper.mode;
  void update() => ref.state = mode.value;
  mode.addListener(update);
  ref.onDispose(() => mode.removeListener(update));
  return mode.value;
});

/// Every change to the window's mode goes through here.
///
/// Implementations run one change at a time, each to completion, and publish
/// the window's real state after it. Two changes that overlapped used to race:
/// leaving full screen and maximising at once brought the window back
/// maximised with the full-screen frame, its title bar off the top of the
/// screen.
abstract class FullScreenWrapper {
  /// The window's mode, kept current from the window itself.
  ValueListenable<WindowMode> get mode;

  /// Leaves full screen if the window is in it, and says whether it was.
  Future<bool> closeFullScreen(WidgetRef ref);
  Future<void> toggleFullScreen(WidgetRef ref);

  /// The title bar's maximise button and a double click on the caption. In
  /// full screen it only leaves full screen.
  Future<void> toggleMaximized();

  /// The title bar's minimise button. Leaves full screen first.
  Future<void> minimize();
}

class FullScreenButton extends ConsumerWidget {
  const FullScreenButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(argumentsStateProvider.select((value) => value.htpcMode))) return const SizedBox.shrink();
    final fullScreen = ref.watch(windowModeProvider) == WindowMode.fullScreen;
    return IconButton(
      onPressed: () => fullScreenHelper.toggleFullScreen(ref),
      icon: Icon(
        fullScreen ? IconsaxPlusLinear.screenmirroring : IconsaxPlusLinear.maximize_4,
      ),
    );
  }
}
