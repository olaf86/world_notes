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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

final class NotificationLaunchManager {
  static let shared = NotificationLaunchManager()

  private static let channelName = "world_notes/notification_launch"
  private static let pendingPlaceIdKey = "world_notes.pending_notification_place_id"
  private static let supportedTypes: Set<String> = [
    "my_note_message",
    "nearby_note_message",
  ]

  private var channel: FlutterMethodChannel?

  private init() {}

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "takeInitialPlaceId":
        result(self.takePendingPlaceId())
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
      return
    }
    UserDefaults.standard.set(placeId, forKey: Self.pendingPlaceIdKey)
  }

  private func takePendingPlaceId() -> String? {
    let defaults = UserDefaults.standard
    let placeId = defaults.string(forKey: Self.pendingPlaceIdKey)
    defaults.removeObject(forKey: Self.pendingPlaceIdKey)
    return placeId
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
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
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
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      result(FlutterError(code: "unavailable", message: "Geofencing is not available.", details: nil))
      return
    }
    guard locationManager.authorizationStatus == .authorizedAlways else {
      clearGeofences()
      result(FlutterError(code: "permission_denied", message: "Always location permission is required.", details: nil))
      return
    }

    clearGeofences()
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
    }
    result(nil)
  }

  private func clearGeofences() {
    for region in locationManager.monitoredRegions {
      guard region.identifier.hasPrefix(Self.identifierPrefix) else { continue }
      locationManager.stopMonitoring(for: region)
    }
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    emit(region: region, transition: "enter")
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    emit(region: region, transition: "exit")
  }

  func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    if state == .inside {
      emit(region: region, transition: "enter")
    }
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
      channel.invokeMethod("geofenceEvent", arguments: event)
    } else {
      appendPendingEvent(event)
    }
  }

  private func takePendingEvents() -> [[String: Any]] {
    let defaults = UserDefaults.standard
    let events = defaults.array(forKey: Self.pendingEventsKey) as? [[String: Any]] ?? []
    defaults.removeObject(forKey: Self.pendingEventsKey)
    return events
  }

  private func appendPendingEvent(_ event: [String: Any]) {
    let defaults = UserDefaults.standard
    var events = defaults.array(forKey: Self.pendingEventsKey) as? [[String: Any]] ?? []
    events.append(event)
    defaults.set(events, forKey: Self.pendingEventsKey)
  }
}
