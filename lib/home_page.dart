import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:foreground_demo_pjo/presentation/page/ble_demo_page.dart';
import 'package:foreground_demo_pjo/presentation/page/ble_foreground_demo_page.dart';
import 'package:foreground_demo_pjo/presentation/page/foreground_demo_page.dart';
import 'package:foreground_demo_pjo/presentation/page/mqtt_demo_page.dart'; // ✅ 新增

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    _cleanupOnStartup();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });
  }

  Future<void> _cleanupOnStartup() async {
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        print('🧹 APP 啟動:發現殘留服務,清理中...');
        await FlutterForegroundTask.stopService();
        await Future.delayed(const Duration(milliseconds: 1000));
        print('✅ 殘留服務已清理');
      } else {
        print('✅ APP 啟動:無殘留服務');
      }
    } catch (e) {
      print('⚠️ 清理時發生錯誤: $e');
    }
  }

  Future<void> _requestPermissions() async {
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      if (!await FlutterForegroundTask.canScheduleExactAlarms) {
        await FlutterForegroundTask.openAlarmsAndRemindersSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foreground Demo Home'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '前景服務測試',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

              // 計數測試
              _buildMenuButton(
                context,
                icon: Icons.calculate,
                title: '計數測試',
                subtitle: '背景計數 + 推播通知',
                color: Colors.blue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => WithForegroundTask(
                        child: const ForegroundDemoPage(),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // MQTT 測試 (如果已經創建了)
              _buildMenuButton(
                context,
                icon: Icons.router,
                title: 'MQTT 測試',
                subtitle: '拉取數據 + 解析驗證',
                color: Colors.purple,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const MqttTestPage(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // ✅ 藍牙測試
              _buildMenuButton(
                context,
                icon: Icons.bluetooth,
                title: '藍牙測試',
                subtitle: '連線 + SDK 解析',
                color: Colors.teal,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BleTestPage(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // 藍芽前景測試
              _buildMenuButton(
                context,
                icon: Icons.bluetooth,
                title: '藍牙前景測試',
                subtitle: '連線 + SDK 解析',
                color: Colors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BleForegroundPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
