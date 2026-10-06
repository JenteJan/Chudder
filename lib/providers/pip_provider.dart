import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/wrappers/pip_manager.dart';

final pipManagerProvider = Provider<PipManager>((ref) {
  final manager = PipManager();
  ref.onDispose(manager.dispose);
  return manager;
});

/// Set from the moment the person leaves the app with a minimized video until
/// PiP has either begun or turned out not to: the video already fills the
/// app by then, so the window shrinks out of the picture rather than out of
/// whatever page was open.
final pipLeavingProvider = StateProvider<bool>((ref) => false);

final pipStateProvider = StreamProvider<bool>((ref) {
  final manager = ref.watch(pipManagerProvider);
  return manager.isInPip;
});
