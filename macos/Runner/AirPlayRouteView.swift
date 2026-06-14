import AVKit
import Cocoa
import FlutterMacOS

/// AppKit counterpart of the iOS `AirPlayRouteView`: renders the system AirPlay
/// picker (`AVRoutePickerView`, an `NSView` on macOS 10.15+) as a Flutter
/// platform view so the user can route the active `AVPlayer` session
/// (`AirPlayVideoPlayer`) out to an Apple TV.
///
/// NOTE: macOS, unlike iOS, has no app-wide audio session — the picker may need
/// to be bound to the specific `AVPlayer` to route it. We don't hold that
/// reference here (it lives inside the `video_player` plugin), so whether route
/// selection actually hands video to the TV needs on-device validation; if it
/// doesn't, the picker must be wired to the player's `AVPlayer` directly.
class AirPlayRouteViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    return AirPlayRouteNSView(arguments: args)
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

private class AirPlayRouteNSView: NSView {
  private let routePicker = AVRoutePickerView(frame: .zero)

  init(arguments args: Any?) {
    super.init(frame: .zero)
    routePicker.isRoutePickerButtonBordered = false

    if let dict = args as? [String: Any] {
      if let r = dict["tintR"] as? CGFloat, let g = dict["tintG"] as? CGFloat,
         let b = dict["tintB"] as? CGFloat, let a = dict["tintA"] as? CGFloat {
        routePicker.setRoutePickerButtonColor(NSColor(red: r, green: g, blue: b, alpha: a), for: .normal)
      }
      if let r = dict["activeR"] as? CGFloat, let g = dict["activeG"] as? CGFloat,
         let b = dict["activeB"] as? CGFloat, let a = dict["activeA"] as? CGFloat {
        routePicker.setRoutePickerButtonColor(NSColor(red: r, green: g, blue: b, alpha: a), for: .active)
      }
    }

    routePicker.translatesAutoresizingMaskIntoConstraints = false
    addSubview(routePicker)
    NSLayoutConstraint.activate([
      routePicker.leadingAnchor.constraint(equalTo: leadingAnchor),
      routePicker.trailingAnchor.constraint(equalTo: trailingAnchor),
      routePicker.topAnchor.constraint(equalTo: topAnchor),
      routePicker.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
