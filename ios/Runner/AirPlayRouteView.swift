import Flutter
import UIKit
import AVKit

/// Renders the system AirPlay button (`AVRoutePickerView`) as a Flutter
/// platform view. Tapping it opens Apple's AirPlay device sheet; the picker
/// also reflects connected-state colouring automatically. Audio routing is
/// transparent — once the user picks a target, the OS routes the active
/// `AVAudioSession` out via AirPlay. Video AirPlay is not wired (would
/// require switching the player off media-kit/mpv).
final class AirPlayRouteViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return AirPlayRouteView(frame: frame, viewIdentifier: viewId, arguments: args, binaryMessenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class AirPlayRouteView: NSObject, FlutterPlatformView {
  private let routePickerView: AVRoutePickerView

  init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger: FlutterBinaryMessenger?) {
    let picker = AVRoutePickerView(frame: frame)
    picker.prioritizesVideoDevices = false
    if let dict = args as? [String: Any] {
      if let r = dict["tintR"] as? CGFloat,
         let g = dict["tintG"] as? CGFloat,
         let b = dict["tintB"] as? CGFloat,
         let a = dict["tintA"] as? CGFloat {
        picker.tintColor = UIColor(red: r, green: g, blue: b, alpha: a)
      }
      if let r = dict["activeR"] as? CGFloat,
         let g = dict["activeG"] as? CGFloat,
         let b = dict["activeB"] as? CGFloat,
         let a = dict["activeA"] as? CGFloat {
        picker.activeTintColor = UIColor(red: r, green: g, blue: b, alpha: a)
      }
    }
    self.routePickerView = picker
    super.init()
  }

  func view() -> UIView {
    return routePickerView
  }
}
