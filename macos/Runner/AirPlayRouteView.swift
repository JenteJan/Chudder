import AVKit
import Cocoa
import FlutterMacOS

/// macOS counterpart of the iOS `AirPlayController`: opens the system AirPlay
/// picker on demand. `AVRoutePickerView` (an `NSView` on macOS) has no public
/// "present()" API, so we keep one offscreen and trigger its internal button
/// when Flutter calls `present`. The active `AVPlayer` (AirPlayVideoPlayer, with
/// external playback enabled) then follows the chosen route to the Apple TV.
///
/// NOTE: unlike iOS there's no app-wide audio session — routing the specific
/// `AVPlayer` (owned by the `video_player` plugin) to the picked device needs
/// on-device validation; if video stays local, the picker has to be bound to
/// that player's `AVPlayer` directly.
final class AirPlayController: NSObject {
  private let channel: FlutterMethodChannel
  private let routePicker = AVRoutePickerView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
  private weak var hostView: NSView?

  init(messenger: FlutterBinaryMessenger, hostView: NSView?) {
    channel = FlutterMethodChannel(name: "uk.jentejan.chudder/airplay", binaryMessenger: messenger)
    self.hostView = hostView
    super.init()
    routePicker.isRoutePickerButtonBordered = false
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "present":
        result(self?.present() ?? false)
      case "stop":
        // macOS has no app-wide audio session to deactivate; the AVPlayer
        // teardown (Dart side) is what ends the route here.
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Opens the system AirPlay sheet by clicking the (hidden) picker's button.
  @discardableResult
  private func present() -> Bool {
    guard let host = hostView ?? NSApp.keyWindow?.contentView else { return false }
    if routePicker.superview == nil {
      routePicker.alphaValue = 0.0
      host.addSubview(routePicker)
    }
    for subview in routePicker.subviews {
      if let button = subview as? NSButton {
        button.performClick(nil)
        return true
      }
    }
    return false
  }
}
