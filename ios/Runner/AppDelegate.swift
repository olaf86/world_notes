import Flutter
import AppTrackingTransparency
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

final class TrackingAuthorizationManager {
  static let shared = TrackingAuthorizationManager()

  private static let channelName = "world_notes/tracking_authorization"
  private var channel: FlutterMethodChannel?
  private var pendingResults: [FlutterResult] = []
  private var requestInFlight = false
  private var activationObserver: NSObjectProtocol?

  private init() {}

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "requestAuthorizationIfNeeded" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.requestAuthorizationIfNeeded(result: result)
    }
    self.channel = channel
  }

  private func requestAuthorizationIfNeeded(result: @escaping FlutterResult) {
    guard #available(iOS 14, *) else {
      result("unavailable")
      return
    }

    let status = ATTrackingManager.trackingAuthorizationStatus
    guard status == .notDetermined else {
      result(statusName(status))
      return
    }

    pendingResults.append(result)
    requestWhenApplicationIsActive()
  }

  @available(iOS 14, *)
  private func requestWhenApplicationIsActive() {
    guard !requestInFlight else { return }
    guard UIApplication.shared.applicationState == .active else {
      observeNextActivation()
      return
    }

    stopObservingActivation()
    requestInFlight = true
    ATTrackingManager.requestTrackingAuthorization { [weak self] status in
      DispatchQueue.main.async {
        guard let self else { return }
        self.requestInFlight = false
        self.finishPendingResults(with: self.statusName(status))
      }
    }
  }

  private func observeNextActivation() {
    guard activationObserver == nil else { return }
    activationObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard #available(iOS 14, *) else { return }
      self?.requestWhenApplicationIsActive()
    }
  }

  private func stopObservingActivation() {
    guard let activationObserver else { return }
    NotificationCenter.default.removeObserver(activationObserver)
    self.activationObserver = nil
  }

  private func finishPendingResults(with status: String) {
    let results = pendingResults
    pendingResults.removeAll()
    for result in results {
      result(status)
    }
  }

  @available(iOS 14, *)
  private func statusName(_ status: ATTrackingManager.AuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return "unknown"
    }
  }
}

final class NotificationLaunchManager {
  static let shared = NotificationLaunchManager()

  private static let channelName = "world_notes/notification_launch"
  private static let launchWorldIdKey = "world_notes.notification_launch_world_id"
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
      case "takeInitialWorldRoute":
        result(self.takeLaunchWorldRoute())
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
      let worldId = userInfo["worldId"] as? String,
      !worldId.isEmpty,
      let placeId = userInfo["placeId"] as? String,
      !placeId.isEmpty
    else {
      debugLog("Ignoring notification launch payload without a world note route.")
      return
    }
    let arguments: [String: Any] = [
      "worldId": worldId,
      "placeId": placeId,
      "readOnly": true,
    ]
    debugLog("Captured notification route: \(worldId):\(placeId)")
    if let channel, isDartReady {
      channel.invokeMethod("notificationLaunchWorldRoute", arguments: arguments)
    } else {
      UserDefaults.standard.set(worldId, forKey: Self.launchWorldIdKey)
      UserDefaults.standard.set(placeId, forKey: Self.launchPlaceIdKey)
      UserDefaults.standard.set(true, forKey: Self.launchReadOnlyKey)
    }
  }

  private func takeLaunchWorldRoute() -> [String: Any]? {
    isDartReady = true
    let defaults = UserDefaults.standard
    let worldId = defaults.string(forKey: Self.launchWorldIdKey)
    let placeId = defaults.string(forKey: Self.launchPlaceIdKey)
    let readOnly = defaults.bool(forKey: Self.launchReadOnlyKey)
    defaults.removeObject(forKey: Self.launchWorldIdKey)
    defaults.removeObject(forKey: Self.launchPlaceIdKey)
    defaults.removeObject(forKey: Self.launchReadOnlyKey)
    guard let worldId, let placeId else {
      debugLog("No complete notification world route to take.")
      return nil
    }
    return [
      "worldId": worldId,
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
