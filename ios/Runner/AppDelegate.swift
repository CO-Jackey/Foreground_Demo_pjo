import Flutter
import UIKit
// ⭐ 加入這個 import
import flutter_foreground_task

// ⭐ 加入這個函數
func registerPlugins(registry: FlutterPluginRegistry) {
  GeneratedPluginRegistrant.register(with: registry)
}
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // ⭐ 加入這行:註冊背景任務 plugin
    FlutterForegroundTaskPlugin.setPluginRegistrantCallback(registerPlugins)

    // ⭐ 如果需要通知權限,加入這段
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
