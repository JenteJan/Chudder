import 'package:logging/logging.dart';

final _logger = Logger('WebSocket');

/// Emit a shared-socket diagnostic.
///
/// Deliberately routed through `Logger` rather than `dart:developer`'s `log()`:
/// the latter is only observable from an attached debugger, so in a release
/// build the socket layer left no trace whatsoever. That is the layer SyncPlay
/// and Cast both sit on top of - a socket that quietly stopped reconnecting
/// surfaces as "Failed to join group" with nothing anywhere to explain it, and
/// the fault had to be reconstructed from the Jellyfin server's own log.
///
/// `CrashLogNotifier` listens on `Logger.root`, persists everything above
/// `Level.INFO` into `crash_logs.json`, and mirrors this logger's INFO records
/// into the on-disk diagnostics file alongside the Cast and SyncPlay traces.
///
/// Kept named `log` so existing call sites read unchanged.
void log(String message) {
  if (_isFailure(message)) {
    _logger.warning(message);
  } else {
    _logger.info(message);
  }
}

/// Case-insensitive on purpose: the SyncPlay copy of this heuristic matched
/// only a capitalised `Cannot`, so `"...cannot join group"` - the single most
/// diagnostic line the socket layer can emit - was filed as INFO and never
/// reached the crash log.
bool _isFailure(String message) {
  final lower = message.toLowerCase();
  return lower.contains('failed') || lower.contains('error') || lower.contains('cannot');
}
