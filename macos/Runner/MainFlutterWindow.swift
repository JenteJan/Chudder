import Cocoa
import FlutterMacOS
import desktop_multi_window
import macos_window_utils

class MainFlutterWindow: NSWindow {
  // Trackpad page swipes, forwarded to Dart as back and forward; the other
  // half is TrackpadNavigation in lib/util/trackpad_navigation.dart.
  private var trackpadChannel: FlutterMethodChannel?
  private var swipeTracking = false
  private var swipeDeltaX: CGFloat = 0
  private var swipeDeltaY: CGFloat = 0

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(registry: flutterViewController)
    trackpadChannel = FlutterMethodChannel(
      name: "uk.jentejan.chudder/trackpad",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      MainFlutterWindowManipulator.start(mainFlutterWindow: controller.view.window)
        // Register the plugin which you want access from other isolate.
        RegisterGeneratedPlugins(registry: controller)
    }
      

    super.awakeFromNib()
  }

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .swipe:
      // The three-finger "swipe between pages" setting sends one whole event.
      // deltaX is positive for a swipe to the right, which is back.
      if event.deltaX != 0, abs(event.deltaX) > abs(event.deltaY) {
        sendSwipe("swipe", event, back: event.deltaX > 0)
      }
    case .scrollWheel:
      trackScrollSwipe(event)
    default:
      break
    }
    if event.type == .leftMouseDown, event.clickCount == 2, !styleMask.contains(.fullScreen) {
      let titleBarHeight: CGFloat = 35
      if event.locationInWindow.y >= frame.height - titleBarHeight {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
          performMiniaturize(nil)
          return
        case "None":
          break
        default:
          performZoom(nil)
          return
        }
      }
    }
    super.sendEvent(event)
  }

  // With the two-finger "swipe between pages" setting a page swipe is an
  // ordinary scroll: the system sends no swipe event for it. So the
  // finger-driven part of every scroll is watched and judged at lift-off,
  // while the scroll itself still goes to Flutter untouched. scrollingDeltaX
  // is already turned for natural scrolling: positive means the content moves
  // right, the previous page sliding in from the left, which is back.
  private func trackScrollSwipe(_ event: NSEvent) {
    guard NSEvent.isSwipeTrackingFromScrollEventsEnabled else { return }
    switch event.phase {
    case .began:
      swipeTracking = true
      swipeDeltaX = 0
      swipeDeltaY = 0
      sendSwipe("swipeBegan", event, back: nil)
    case .changed:
      guard swipeTracking else { return }
      swipeDeltaX += event.scrollingDeltaX
      swipeDeltaY += event.scrollingDeltaY
    case .ended:
      guard swipeTracking else { return }
      swipeTracking = false
      if abs(swipeDeltaX) >= 60, abs(swipeDeltaX) > 2 * abs(swipeDeltaY) {
        sendSwipe("swipeEnded", event, back: swipeDeltaX > 0)
      }
    case .cancelled:
      swipeTracking = false
    default:
      break
    }
  }

  private func sendSwipe(_ method: String, _ event: NSEvent, back: Bool?) {
    guard let content = contentView else { return }
    // Flutter's origin is the top left; AppKit's is the bottom left.
    let point = content.convert(event.locationInWindow, from: nil)
    var arguments: [String: Any] = ["x": point.x, "y": content.bounds.height - point.y]
    if let back = back {
      arguments["back"] = back
    }
    trackpadChannel?.invokeMethod(method, arguments: arguments)
  }
}
