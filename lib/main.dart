import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:foreground_demo_pjo/home_page.dart';

void main() {
  // ⭐ 1. 先初始化前景任務配置 (只執行一次)
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service',
      channelName: '前景服務',
      channelDescription: 'APP 背景運行',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(1000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );

  // ⭐ 新增:註冊全局回調測試
  FlutterForegroundTask.addTaskDataCallback((data) {
    print('🌍 [全局回調] 收到背景資料: $data');
  });
  
  // ⭐ 新增:初始化通訊端口
  FlutterForegroundTask.initCommunicationPort();
  // ⭐ 2. 啟動 APP
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Material App',
        home: HomePage(),
      ),
    );
  }
}
