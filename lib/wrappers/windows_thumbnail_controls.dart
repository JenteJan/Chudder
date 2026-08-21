import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:logging/logging.dart';
import 'package:windows_taskbar/windows_taskbar.dart'
    if (dart.library.html) 'package:fladder/stubs/web/windows_taskbar_web.dart';

final _log = Logger('WindowsThumbnailControls');

/// Transport buttons in the taskbar thumbnail preview — the row that appears
/// under the window preview when you hover Fladder's taskbar icon, the way
/// Spotify shows its own.
///
/// Windows doesn't derive these from the SMTC session (that only feeds the
/// media keys and the volume flyout), so they have to be published separately.
/// The button *count* is fixed for the lifetime of the window, so this always
/// publishes the same two and only swaps the play/pause icon.
class WindowsThumbnailControls {
  WindowsThumbnailControls({required this.onPlayPause, required this.onStop});

  /// Called for the first button; it shows a pause glyph while playing.
  final void Function() onPlayPause;
  final void Function() onStop;

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// Last published playing state, or null while no buttons are shown.
  bool? _playing;

  /// Publishes the buttons, or just swaps the play/pause glyph if they are
  /// already up. Cheap to call on every state change — repeats are dropped.
  Future<void> show({required bool playing}) async {
    if (!supported || _playing == playing) return;
    _playing = playing;
    await _guard(() => WindowsTaskbar.setThumbnailToolbar([
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon(playing ? 'assets/thumbbar/pause.ico' : 'assets/thumbbar/play.ico'),
            playing ? 'Pause' : 'Play',
            onPlayPause,
          ),
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon('assets/thumbbar/stop.ico'),
            'Stop',
            onStop,
          ),
        ]));
  }

  Future<void> hide() async {
    if (!supported || _playing == null) return;
    _playing = null;
    await _guard(WindowsTaskbar.resetThumbnailToolbar);
  }

  /// The native side refuses while the window is hidden and throws if the
  /// icons can't be loaded; neither is worth breaking playback over.
  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (error, stack) {
      // Back to unknown, so the next state change tries again.
      _playing = null;
      _log.fine('Taskbar thumbnail buttons could not be updated', error, stack);
    }
  }
}
