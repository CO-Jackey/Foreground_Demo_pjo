import UIKit
import Flutter
import flutter_foreground_task // 保持這個，因為背景服務套件需要它

// 這個函數是用來給背景任務註冊用的，保留它
func registerPlugins(registry: FlutterPluginRegistry) {
  GeneratedPluginRegistrant.register(with: registry)
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 🔴 刪除這行！現在 GeneratedPluginRegistrant 會幫你做這件事
    // HealthCalculatePlugin.register(with: self.registrar(forPlugin: "HealthCalculatePlugin")!)

    // ✅ 保留這行：確保背景 isolate 啟動時會註冊所有 Plugin (包含你的 health_plugin)
    FlutterForegroundTaskPlugin.setPluginRegistrantCallback(registerPlugins)

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}