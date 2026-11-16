// Browser-only: follows the browser's own history so its back and forward can
// be answered the way the app answers its own. The real implementation only
// loads on the web build; every other platform gets the no-op stub.
export 'web_navigation_guard_stub.dart' if (dart.library.js_interop) 'web_navigation_guard_web.dart';
