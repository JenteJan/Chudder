import 'package:logging/logging.dart';

final _logger = Logger('SyncPlay');

/// Whether to emit the full SyncPlay trace rather than just failures.
///
/// Verbose records go out at `Level.INFO`: they stay out of the
/// `crash_logs.json` ring buffer (WARNING+ only) but land in the persistent
/// diagnostics file next to the cast trace, so group playback oddities can
/// be diagnosed from a release build.
const bool verboseSyncPlayLogs = true;

/// Emit a SyncPlay diagnostic.
///
/// Deliberately routed through `Logger` rather than `dart:developer`'s
/// `log()`: the latter is only observable from an attached debugger, so in a
/// release build SyncPlay left no trace at all and failures had to be
/// diagnosed from the Jellyfin server's log instead. `CrashLogNotifier`
/// listens on `Logger.root` and persists everything above `Level.INFO`, so
/// logging failures at warning gets them into `crash_logs.json`.
///
/// Kept named `log` so existing call sites read unchanged.
void log(String message) {
  if (_isFailure(message)) {
    _logger.warning(message);
  } else if (verboseSyncPlayLogs) {
    _logger.info(message);
  }
}

bool _isFailure(String message) =>
    message.contains('Failed') || message.contains('Error') || message.contains('Cannot');
