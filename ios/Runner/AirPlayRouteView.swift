import AVFoundation
import AVKit
import Flutter
import UIKit

/// Opens the system AirPlay picker on demand. `AVRoutePickerView` is the only
/// way to present Apple's AirPlay device sheet, but it has no public
/// "present()" API — so we keep one offscreen in the key window and trigger its
/// internal button when Flutter asks (method channel `present`). The active
/// `AVPlayer` (AirPlayVideoPlayer, external playback enabled) then follows the
/// chosen route, handing video to the Apple TV.
///
/// This replaces the earlier embedded platform-view button: the Flutter UI now
/// shows a single normal AirPlay row, and tapping it both starts the AVPlayer
/// and calls `present` here.
final class AirPlayController: NSObject {
  private let channel: FlutterMethodChannel
  private let routePicker: AVRoutePickerView

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "nl.jknaapen.fladder/airplay", binaryMessenger: messenger)
    // Tiny and offscreen — never shown, only triggered programmatically.
    routePicker = AVRoutePickerView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    routePicker.prioritizesVideoDevices = true
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "present":
        result(self?.present() ?? false)
      case "stop":
        result(self?.stop() ?? false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Releases the AirPlay route. Disposing the AVPlayer alone leaves the audio
  /// session pointed at the Apple TV, so resumed local playback keeps casting
  /// its audio; deactivating the session drops the route back to the device.
  @discardableResult
  private func stop() -> Bool {
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      return true
    } catch {
      NSLog("AirPlay: failed to deactivate audio session: \(error.localizedDescription)")
      return false
    }
  }

  /// Opens the system AirPlay sheet by triggering the (hidden) picker's button.
  @discardableResult
  private func present() -> Bool {
    guard let window = Self.keyWindow() else { return false }
    if routePicker.superview == nil {
      window.addSubview(routePicker)
    }
    for subview in routePicker.subviews {
      if let button = subview as? UIButton {
        button.sendActions(for: .touchUpInside)
        return true
      }
    }
    return false
  }

  private static func keyWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }
}
