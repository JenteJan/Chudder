// Web Cast (Cast Web Sender) facade. The real implementation
// (cast_web_impl.dart) uses dart:js_interop and only loads on the web build;
// every other platform gets the no-op stub, keeping browser-only APIs out of
// mobile/desktop compilation.
export 'cast_web_unsupported.dart' if (dart.library.js_interop) 'cast_web_impl.dart';
