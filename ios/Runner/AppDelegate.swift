import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    APNsRegistrationDiagnostics.shared.markPending()
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

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    APNsRegistrationDiagnostics.shared.markSucceeded()
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    APNsRegistrationDiagnostics.shared.markFailed(error: error)
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

final class APNsRegistrationDiagnostics {
  static let shared = APNsRegistrationDiagnostics()

  private static let statusKey = "world_notes.apns_registration.status"
  private static let messageKey = "world_notes.apns_registration.message"
  private static let updatedAtKey = "world_notes.apns_registration.updated_at"

  private init() {}

  func markPending() {
    save(status: "pending", message: nil)
  }

  func markSucceeded() {
    save(status: "succeeded", message: nil)
  }

  func markFailed(error: Error) {
    save(status: "failed", message: error.localizedDescription)
  }

  func currentStatus() -> [String: Any] {
    let defaults = UserDefaults.standard
    var result: [String: Any] = [
      "status": defaults.string(forKey: Self.statusKey) ?? "unknown"
    ]
    if let message = defaults.string(forKey: Self.messageKey) {
      result["message"] = message
    }
    if let updatedAt = defaults.object(forKey: Self.updatedAtKey) as? Date {
      result["updatedAtMillis"] = Int(updatedAt.timeIntervalSince1970 * 1000)
    }
    return result
  }

  private func save(status: String, message: String?) {
    let defaults = UserDefaults.standard
    defaults.set(status, forKey: Self.statusKey)
    defaults.set(Date(), forKey: Self.updatedAtKey)
    if let message {
      defaults.set(message, forKey: Self.messageKey)
    } else {
      defaults.removeObject(forKey: Self.messageKey)
    }
  }
}

final class NotificationLaunchManager {
  static let shared = NotificationLaunchManager()

  private static let channelName = "world_notes/notification_launch"
  private static let launchPlaceIdKey = "world_notes.notification_launch_place_id"
  private static let launchReadOnlyKey = "world_notes.notification_launch_read_only"
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
      case "apnsRegistrationStatus":
        result(APNsRegistrationDiagnostics.shared.currentStatus())
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
    let readOnly = type == "my_note_message"
    let arguments: [String: Any] = [
      "placeId": placeId,
      "readOnly": readOnly,
    ]
    debugLog("Captured notification launch placeId: \(placeId), readOnly: \(readOnly)")
    if let channel, isDartReady {
      debugLog("Sending notification launch placeId to Dart: \(placeId)")
      channel.invokeMethod("notificationLaunchPlaceId", arguments: arguments)
    } else {
      debugLog("Saving notification launch placeId until Dart is ready: \(placeId)")
      UserDefaults.standard.set(placeId, forKey: Self.launchPlaceIdKey)
      UserDefaults.standard.set(readOnly, forKey: Self.launchReadOnlyKey)
    }
  }

  private func takeLaunchPlaceId() -> [String: Any]? {
    isDartReady = true
    let defaults = UserDefaults.standard
    let placeId = defaults.string(forKey: Self.launchPlaceIdKey)
    let readOnly = defaults.bool(forKey: Self.launchReadOnlyKey)
    defaults.removeObject(forKey: Self.launchPlaceIdKey)
    defaults.removeObject(forKey: Self.launchReadOnlyKey)
    if let placeId {
      debugLog("Dart took notification launch placeId: \(placeId)")
      return [
        "placeId": placeId,
        "readOnly": readOnly,
      ]
    } else {
      debugLog("No notification launch placeId to take.")
      return nil
    }
  }

  private func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    NSLog("[NotificationLaunch] %@", message())
#endif
  }
}

final class NativeGeofenceManager: NSObject, CLLocationManagerDelegate {
  private struct GeofenceSpec {
    let placeId: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
  }

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

    let maximumRadius = locationManager.maximumRegionMonitoringDistance
    var requested: [String: GeofenceSpec] = [:]
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

      let radiusMeters = radiusValue.doubleValue
      let radius = maximumRadius > 0 ? min(radiusMeters, maximumRadius) : radiusMeters
      requested[placeId] = GeofenceSpec(
        placeId: placeId,
        latitude: latitudeValue.doubleValue,
        longitude: longitudeValue.doubleValue,
        radiusMeters: radius
      )
    }

    let existing = locationManager.monitoredRegions.compactMap { region -> CLCircularRegion? in
      guard
        region.identifier.hasPrefix(Self.identifierPrefix),
        let circularRegion = region as? CLCircularRegion
      else {
        return nil
      }
      return circularRegion
    }
    var unchangedPlaceIds = Set<String>()
    var removed = 0
    for region in existing {
      let placeId = String(region.identifier.dropFirst(Self.identifierPrefix.count))
      if let spec = requested[placeId], matches(region: region, spec: spec) {
        unchangedPlaceIds.insert(placeId)
      } else {
        locationManager.stopMonitoring(for: region)
        removed += 1
      }
    }

    var added = 0
    for spec in requested.values where !unchangedPlaceIds.contains(spec.placeId) {
      let center = CLLocationCoordinate2D(
        latitude: spec.latitude,
        longitude: spec.longitude
      )
      let region = CLCircularRegion(
        center: center,
        radius: spec.radiusMeters,
        identifier: Self.identifierPrefix + spec.placeId
      )
      region.notifyOnEntry = true
      region.notifyOnExit = true
      locationManager.startMonitoring(for: region)
      locationManager.requestState(for: region)
      added += 1
    }
    log(
      "Applied geofence diff: unchanged=\(unchangedPlaceIds.count), " +
        "removed=\(removed), added=\(added)."
    )
    result(nil)
  }

  private func matches(region: CLCircularRegion, spec: GeofenceSpec) -> Bool {
    let coordinateTolerance = 0.0000001
    let radiusToleranceMeters = 0.1
    return abs(region.center.latitude - spec.latitude) <= coordinateTolerance &&
      abs(region.center.longitude - spec.longitude) <= coordinateTolerance &&
      abs(region.radius - spec.radiusMeters) <= radiusToleranceMeters &&
      region.notifyOnEntry &&
      region.notifyOnExit
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
