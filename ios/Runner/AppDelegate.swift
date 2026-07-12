import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      NotificationLaunchManager.shared.capture(userInfo: userInfo)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NotificationLaunchManager.shared.capture(
      userInfo: response.notification.request.content.userInfo
    )
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

final class NotificationLaunchManager {
  static let shared = NotificationLaunchManager()

  private static let channelName = "world_notes/notification_launch"
  private static let launchPlaceIdKey = "world_notes.notification_launch_place_id"
  private static let launchReadOnlyKey = "world_notes.notification_launch_read_only"
  private static let supportedTypes: Set<String> = ["my_note_message"]

  private var channel: FlutterMethodChannel?
  private var isDartReady = false

  private init() {}

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    debugLog("Configuring notification launch channel.")
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "takeInitialPlaceId":
        result(self.takeLaunchPlaceId())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func capture(userInfo: [AnyHashable: Any]) {
    guard
      let type = userInfo["type"] as? String,
      Self.supportedTypes.contains(type),
      let placeId = userInfo["placeId"] as? String,
      !placeId.isEmpty
    else {
      debugLog("Ignoring notification launch payload without supported type/placeId.")
      return
    }
    let arguments: [String: Any] = [
      "placeId": placeId,
      "readOnly": true,
    ]
    debugLog("Captured notification launch placeId: \(placeId)")
    if let channel, isDartReady {
      channel.invokeMethod("notificationLaunchPlaceId", arguments: arguments)
    } else {
      UserDefaults.standard.set(placeId, forKey: Self.launchPlaceIdKey)
      UserDefaults.standard.set(true, forKey: Self.launchReadOnlyKey)
    }
  }

  private func takeLaunchPlaceId() -> [String: Any]? {
    isDartReady = true
    let defaults = UserDefaults.standard
    let placeId = defaults.string(forKey: Self.launchPlaceIdKey)
    let readOnly = defaults.bool(forKey: Self.launchReadOnlyKey)
    defaults.removeObject(forKey: Self.launchPlaceIdKey)
    defaults.removeObject(forKey: Self.launchReadOnlyKey)
    guard let placeId else {
      debugLog("No notification launch placeId to take.")
      return nil
    }
    return [
      "placeId": placeId,
      "readOnly": readOnly,
    ]
  }

  private func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    NSLog("[NotificationLaunch] %@", message())
#endif
  }
}
