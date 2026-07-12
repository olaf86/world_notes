import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    NotificationLaunchManager.shared.configure(binaryMessenger: controller.binaryMessenger)
    if let userInfo = connectionOptions.notificationResponse?.notification.request.content.userInfo {
      NotificationLaunchManager.shared.capture(userInfo: userInfo)
    }
  }
}
