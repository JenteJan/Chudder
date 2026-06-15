import AVFoundation
import AVKit
import Flutter
import UIKit

/// Renders the system AirPlay button (`AVRoutePickerView`) as a Flutter platform
/// view. Tapping it opens Apple's AirPlay device sheet. We watch the audio
/// session's route and report to Dart whether an AirPlay device is currently
/// selected (`onAirPlayRouteChanged`), so the app can swap to the AVPlayer-backed
/// player only once a device is actually picked — and tear it down if the user
/// cancels or deselects. Video then follows because that player has external
/// playback enabled.
final class AirPlayRouteViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return AirPlayRouteView(frame: frame, arguments: args, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class AirPlayRouteView: NSObject, FlutterPlatformView {
  private let routePickerView: AVRoutePickerView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, arguments args: Any?, messenger: FlutterBinaryMessenger) {
    let picker = AVRoutePickerView(frame: frame)
    // We want video-capable targets (Apple TV) first, not audio-only receivers.
    picker.prioritizesVideoDevices = true
    if let dict = args as? [String: Any] {
      if let r = dict["tintR"] as? CGFloat, let g = dict["tintG"] as? CGFloat,
         let b = dict["tintB"] as? CGFloat, let a = dict["tintA"] as? CGFloat {
        picker.tintColor = UIColor(red: r, green: g, blue: b, alpha: a)
      }
      if let r = dict["activeR"] as? CGFloat, let g = dict["activeG"] as? CGFloat,
         let b = dict["activeB"] as? CGFloat, let a = dict["activeA"] as? CGFloat {
        picker.activeTintColor = UIColor(red: r, green: g, blue: b, alpha: a)
      }
    }
    self.routePickerView = picker
    self.channel = FlutterMethodChannel(name: "nl.jknaapen.fladder/airplay", binaryMessenger: messenger)
    super.init()

    NotificationCenter.default.addObserver(
      self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
    // Report the current state so the app reflects an already-active route.
    reportRoute()
  }

  @objc private func routeChanged(_ notification: Notification) {
    reportRoute()
  }

  private func reportRoute() {
    let active = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    channel.invokeMethod("onAirPlayRouteChanged", arguments: ["active": active])
  }

  func view() -> UIView {
    return routePickerView
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
