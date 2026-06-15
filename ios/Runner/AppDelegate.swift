import UIKit
import Flutter
import workmanager_apple
import GoogleCast

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Holds custom-namespace Cast channels keyed by namespace, so we don't
  // double-register and can route incoming messages back to Flutter.
  private var castChannels: [String: FladderCastChannel] = [:]
  private var castMethodChannel: FlutterMethodChannel?
  private var airPlayController: AirPlayController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      granted, error in
      if granted {
        print("Notification permission granted for debug handler")
      } else if let error = error {
        print("Error requesting notification permission: \(error)")
      }
    }

    WorkmanagerDebug.setCurrent(NotificationDebugHandler())

    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "nl.jknaapen.fladder.update_notifications_check_debug")
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "nl.jknaapen.fladder.update_notifications_check",
      frequency: NSNumber(value: 20 * 60))

    registerCastBridges()
    registerAirPlay()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - AirPlay

  /// Wires the AirPlay picker bridge: Flutter shows a single AirPlay row and
  /// calls `present` to open the system device sheet (see `AirPlayController`).
  private func registerAirPlay() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    airPlayController = AirPlayController(messenger: controller.binaryMessenger)
  }

  // MARK: - Cast bridges

  /// Mirrors the Android MainActivity bridges:
  /// - `nl.jknaapen.fladder/cast` for custom-namespace receiver messaging on the
  ///   active Cast session managed by `flutter_chrome_cast`.
  /// - `nl.jknaapen.fladder/multicast` as a no-op (iOS has no Wi-Fi multicast
  ///   lock concept). Registered anyway so the DLNA discovery code's invokes
  ///   don't surface `MissingPluginException`s in logs.
  private func registerCastBridges() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let messenger = controller.binaryMessenger

    castMethodChannel = FlutterMethodChannel(
      name: "nl.jknaapen.fladder/cast",
      binaryMessenger: messenger
    )
    castMethodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession
      switch call.method {
      case "sendMessage":
        let args = call.arguments as? [String: Any]
        let namespace = args?["namespace"] as? String
        let message = args?["message"] as? String
        guard let session = session, let namespace = namespace, let message = message else {
          NSLog("FladderCast: sendMessage no session (session=\(session != nil))")
          result(FlutterError(code: "NO_SESSION", message: "No active cast session", details: nil))
          return
        }
        // iOS sends custom-namespace text through a GCKCastChannel (the session
        // has no sendTextMessage). Reuse a registered channel for this namespace
        // or lazily create and attach one.
        let channel: FladderCastChannel
        if let existing = self.castChannels[namespace] {
          channel = existing
        } else {
          let created = FladderCastChannel(namespace: namespace) { [weak self] ns, msg in
            self?.castMethodChannel?.invokeMethod(
              "onCastMessage",
              arguments: ["namespace": ns, "message": msg]
            )
          }
          if !session.add(created) {
            NSLog("FladderCast: GCKCastSession.add returned false for \(namespace)")
          }
          self.castChannels[namespace] = created
          channel = created
        }
        var error: GCKError?
        channel.sendTextMessage(message, error: &error)
        if let error = error {
          NSLog("FladderCast: sendMessage failed: \(error.localizedDescription)")
          result(FlutterError(code: "SEND_FAILED", message: error.localizedDescription, details: nil))
        } else {
          result(true)
        }
      case "registerNamespace":
        let args = call.arguments as? [String: Any]
        let namespace = args?["namespace"] as? String
        guard let session = session, let namespace = namespace else {
          NSLog("FladderCast: registerNamespace no session")
          result(FlutterError(code: "NO_SESSION", message: "No active cast session", details: nil))
          return
        }
        if self.castChannels[namespace] != nil {
          // Already registered for this namespace — no-op.
          result(true)
          return
        }
        let channel = FladderCastChannel(namespace: namespace) { [weak self] ns, message in
          self?.castMethodChannel?.invokeMethod(
            "onCastMessage",
            arguments: ["namespace": ns, "message": message]
          )
        }
        let added = session.add(channel)
        if !added {
          NSLog("FladderCast: GCKCastSession.add returned false for \(namespace)")
        }
        self.castChannels[namespace] = channel
        result(added)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let multicastChannel = FlutterMethodChannel(
      name: "nl.jknaapen.fladder/multicast",
      binaryMessenger: messenger
    )
    // iOS has no Wi-Fi multicast lock to acquire; ack so the Dart side's
    // best-effort invoke doesn't log MissingPluginException. Outgoing
    // multicast requires the `com.apple.developer.networking.multicast`
    // entitlement (configured in Runner.entitlements).
    multicastChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "acquire", "release":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// `GCKCastChannel` subclass that forwards every received text message to a
/// callback. iOS's Cast SDK requires a channel object per namespace (unlike
/// Android's `MessageReceivedCallback` registered against the session).
private final class FladderCastChannel: GCKCastChannel {
  private let onMessage: (String, String) -> Void

  init(namespace: String, onMessage: @escaping (String, String) -> Void) {
    self.onMessage = onMessage
    super.init(namespace: namespace)
  }

  override func didReceiveTextMessage(_ message: String) {
    onMessage(protocolNamespace, message)
  }
}
