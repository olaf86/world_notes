import CoreLocation
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
    NativeGeofenceManager.shared.start()
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
  private static let supportedTypes: Set<String> = [
    "my_note_message",
    "nearby_note_message",
  ]

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
    debugLog("Captured notification launch placeId: \(placeId)")
    if let channel, isDartReady {
      debugLog("Sending notification launch placeId to Dart: \(placeId)")
      channel.invokeMethod("notificationLaunchPlaceId", arguments: placeId)
    } else {
      debugLog("Saving notification launch placeId until Dart is ready: \(placeId)")
      UserDefaults.standard.set(placeId, forKey: Self.launchPlaceIdKey)
    }
  }

  private func takeLaunchPlaceId() -> String? {
    isDartReady = true
    let defaults = UserDefaults.standard
    let placeId = defaults.string(forKey: Self.launchPlaceIdKey)
    defaults.removeObject(forKey: Self.launchPlaceIdKey)
    if let placeId {
      debugLog("Dart took notification launch placeId: \(placeId)")
    } else {
      debugLog("No notification launch placeId to take.")
    }
    return placeId
  }

  private func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    NSLog("[NotificationLaunch] %@", message())
#endif
  }
}

final class NativeGeofenceManager: NSObject, CLLocationManagerDelegate {
  static let shared = NativeGeofenceManager()

  private static let channelName = "world_notes/geofence"
  private static let identifierPrefix = "world_notes_"
  private static let pendingEventsKey = "world_notes.pending_geofence_events"

  private let locationManager = CLLocationManager()
  private var channel: FlutterMethodChannel?
  private var isDartReady = false

  private override init() {
    super.init()
    locationManager.delegate = self
  }

  func start() {
    locationManager.delegate = self
    log("Manager started (authorization=\(locationManager.authorizationStatus.rawValue)).")
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    log("Configuring Flutter geofence channel.")
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.channel = channel
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    isDartReady = true
    switch call.method {
    case "syncGeofences":
      guard
        let arguments = call.arguments as? [String: Any],
        let geofences = arguments["geofences"] as? [[String: Any]]
      else {
        result(FlutterError(code: "invalid_arguments", message: "Missing geofences.", details: nil))
        return
      }
      syncGeofences(geofences, result: result)
    case "clearGeofences":
      clearGeofences()
      result(nil)
    case "takePendingEvents":
      result(takePendingEvents())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func syncGeofences(_ geofences: [[String: Any]], result: @escaping FlutterResult) {
    log("Sync requested for \(geofences.count) geofence(s).")
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      log("Sync failed: region monitoring is unavailable.")
      result(FlutterError(code: "unavailable", message: "Geofencing is not available.", details: nil))
      return
    }
    guard locationManager.authorizationStatus == .authorizedAlways else {
      log("Sync rejected: Always location permission is unavailable.")
      clearGeofences()
      result(FlutterError(code: "permission_denied", message: "Always location permission is required.", details: nil))
      return
    }

    clearGeofences()
    var submitted = 0
    for geofence in geofences {
      guard
        let placeId = geofence["placeId"] as? String,
        let latitudeValue = geofence["latitude"] as? NSNumber,
        let longitudeValue = geofence["longitude"] as? NSNumber,
        let radiusValue = geofence["radiusMeters"] as? NSNumber,
        !placeId.isEmpty,
        radiusValue.doubleValue > 0
      else {
        continue
      }

      let maximumRadius = locationManager.maximumRegionMonitoringDistance
      let latitude = latitudeValue.doubleValue
      let longitude = longitudeValue.doubleValue
      let radiusMeters = radiusValue.doubleValue
      let radius = maximumRadius > 0 ? min(radiusMeters, maximumRadius) : radiusMeters
      let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      let region = CLCircularRegion(
        center: center,
        radius: radius,
        identifier: Self.identifierPrefix + placeId
      )
      region.notifyOnEntry = true
      region.notifyOnExit = true
      locationManager.startMonitoring(for: region)
      locationManager.requestState(for: region)
      submitted += 1
    }
    log("Submitted \(submitted) monitored region(s).")
    result(nil)
  }

  private func clearGeofences() {
    var cleared = 0
    for region in locationManager.monitoredRegions {
      guard region.identifier.hasPrefix(Self.identifierPrefix) else { continue }
      locationManager.stopMonitoring(for: region)
      cleared += 1
    }
    log("Cleared \(cleared) monitored region(s).")
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    log("Received enter transition.")
    emit(region: region, transition: "enter")
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    log("Received exit transition.")
    emit(region: region, transition: "exit")
  }

  func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    log("Determined region state \(state.rawValue).")
    if state == .inside {
      emit(region: region, transition: "enter")
    }
  }

  func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    log("Region monitoring started.")
  }

  func locationManager(
    _ manager: CLLocationManager,
    monitoringDidFailFor region: CLRegion?,
    withError error: Error
  ) {
    log("Region monitoring failed: \(error.localizedDescription)")
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    log("Location manager failed: \(error.localizedDescription)")
  }

  private func emit(region: CLRegion, transition: String) {
    guard region.identifier.hasPrefix(Self.identifierPrefix) else { return }
    let placeId = String(region.identifier.dropFirst(Self.identifierPrefix.count))
    let event: [String: Any] = [
      "placeId": placeId,
      "transition": transition,
      "timestampMillis": Int(Date().timeIntervalSince1970 * 1000),
    ]
    if let channel, isDartReady {
      log("Delivering \(transition) event to Dart.")
      channel.invokeMethod("geofenceEvent", arguments: event)
    } else {
      log("Queueing \(transition) event until Dart is ready.")
      appendPendingEvent(event)
    }
  }

  private func takePendingEvents() -> [[String: Any]] {
    let defaults = UserDefaults.standard
    let events = defaults.array(forKey: Self.pendingEventsKey) as? [[String: Any]] ?? []
    defaults.removeObject(forKey: Self.pendingEventsKey)
    log("Returning \(events.count) pending event(s) to Dart.")
    return events
  }

  private func appendPendingEvent(_ event: [String: Any]) {
    let defaults = UserDefaults.standard
    var events = defaults.array(forKey: Self.pendingEventsKey) as? [[String: Any]] ?? []
    events.append(event)
    defaults.set(events, forKey: Self.pendingEventsKey)
  }

  private func log(_ message: @autoclosure () -> String) {
    NSLog("[NearbyGeofence] %@", message())
  }
}
