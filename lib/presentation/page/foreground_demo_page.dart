import 'dart:isolate'; // 👈 新增這行
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 前景服務示範頁面
/// 展示如何使用長駐服務模式實現穩定的背景計數功能
class ForegroundDemoPage extends StatefulWidget {
  const ForegroundDemoPage({super.key});

  @override
  State<ForegroundDemoPage> createState() => _ForegroundDemoPageState();
}

class _ForegroundDemoPageState extends State<ForegroundDemoPage> {
  // ==================== 狀態變數 ==================== 

  /// 背景服務是否正在運行 (長駐狀態)
  bool _isServiceRunning = false;

  /// 是否正在計數 (可暫停/恢復)
  bool _isCounting = false;

  /// 當前計數值
  int _currentCount = 0;

  /// 目標計數值
  int _targetCount = 10;

  /// 是否正在處理操作 (防止重複點擊)
  bool _isProcessing = false;

  static int _serviceIdCounter = 11111;

  // ==================== 生命週期方法 ====================

  @override
  void initState() {
    super.initState();

    // 1. 初始化本地推播
    _initNotifications();

    // ⭐ 2. 立即註冊回調 (不要延遲)
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    print('✅ 已註冊 TaskDataCallback');
  }

  @override
  void dispose() {
    // 清理回調
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    print('🧹 已移除 TaskDataCallback');
    super.dispose();
  }

  // ==================== 初始化方法 ====================

  /// 初始化前景任務配置
  /// 這裡設定了 Android 和 iOS 的通知選項,以及任務執行參數
  // void _initForegroundTask() {
  //   FlutterForegroundTask.init(
  //     // Android 通知配置
  //     androidNotificationOptions: AndroidNotificationOptions(
  //       channelId: 'foreground_service', // 通知頻道 ID
  //       channelName: '前景服務', // 通知頻道名稱
  //       channelDescription: 'APP 背景運行', // 通知頻道描述
  //       channelImportance: NotificationChannelImportance.LOW, // 低重要性,不會發出聲音
  //       priority: NotificationPriority.LOW, // 低優先級
  //     ),
  //     // iOS 通知配置 (本範例不顯示通知)
  //     iosNotificationOptions: const IOSNotificationOptions(
  //       showNotification: false,
  //     ),
  //     // 前景任務選項
  //     foregroundTaskOptions: ForegroundTaskOptions(
  //       eventAction: ForegroundTaskEventAction.repeat(
  //         1000,
  //       ), // 每 1 秒觸發一次 onRepeatEvent
  //       autoRunOnBoot: false, // 不在開機時自動啟動
  //       autoRunOnMyPackageReplaced: false, // APP 更新後不自動重啟服務
  //       allowWakeLock: true, // 允許喚醒鎖 (防止 CPU 休眠)
  //       allowWifiLock: false, // 不需要 WiFi 鎖
  //     ),
  //   );
  // }

  /// 初始化本地推播通知系統
  /// 用於在達成目標時發送推播通知
  void _initNotifications() async {
    final plugin = FlutterLocalNotificationsPlugin();

    // Android 初始化設定
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher', // 使用 APP 圖示作為通知圖示
    );

    // iOS 初始化設定
    const iosSettings = DarwinInitializationSettings();

    // 組合設定
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // 初始化插件並設定點擊通知的回調
    await plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        print('📱 使用者點擊了通知');
        // 可以在這裡處理使用者點擊通知後的行為
      },
    );

    // 請求 Android 13+ 的通知權限
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  // ==================== 資料接收方法 ====================

  /// 接收來自背景任務的資料
  /// 這是 UI 與背景任務之間的主要通訊管道
  void _onReceiveTaskData(dynamic data) {
    print('📻 [TaskDataCallback] 收到資料: $data'); // 👈 加上日誌

    if (data is Map) {
      final type = data['type'] as String?;

      switch (type) {
        // 背景服務已準備完成
        case 'serviceReady':
          print('✅ 收到服務準備完成訊號');
          setState(() {
            _isServiceRunning = true;
          });
          break;

        // 計數值更新
        case 'countUpdate':
          setState(() {
            _currentCount = data['count'] as int;
          });
          print('📥 UI 收到計數更新: $_currentCount');
          break;

        // 計數已完成 (達到目標)
        case 'countingFinished':
          setState(() {
            _isCounting = false;
          });
          print('🎯 計數已完成並自動停止');
          break;
      }
    }
  }

  // ==================== 服務控制方法 ====================

  /// 啟動背景服務 (長駐模式)
  /// 這個服務會一直運行,直到手動停止
  ///
  /// 流程:
  /// 1. 檢查服務是否已在運行
  /// 2. 如果未運行,啟動服務
  /// 3. 等待服務準備完成訊號
  Future<void> _startBackgroundService() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      print('🧹 開始清理流程...');

      // 1. 先停止舊服務
      try {
        await FlutterForegroundTask.stopService();
        print('✅ stopService 已調用');
      } catch (e) {
        print('⚠️ stopService 失敗: $e');
      }

      // 2. 等待清理完成
      await Future.delayed(const Duration(milliseconds: 3000));

      // 3. 遞增 ID
      _serviceIdCounter++;
      print('🔑 使用服務 ID: $_serviceIdCounter');

      print('🚀 準備啟動新的背景服務...');

      // 4. 啟動服務
      final serviceStatus = await FlutterForegroundTask.startService(
        serviceId: _serviceIdCounter,
        notificationTitle: '⏸️ 背景服務 #$_serviceIdCounter',
        notificationText: '待命中',
        callback: startCallback,
      );

      print('🔍 startService 返回: $serviceStatus');

      if (serviceStatus != null) {
        print('✅ startService 返回成功');

        // ⭐ 直接設置服務為運行中,不等待 serviceReady
        setState(() {
          _isServiceRunning = true;
        });

        print('✅ 服務已標記為運行中');
      } else {
        print('❌ startService 返回 null');
        _showErrorDialog('背景服務啟動失敗');
      }
    } catch (e, stack) {
      print('❌ 啟動背景服務時發生錯誤: $e');
      print('❌ 堆疊: $stack');
      _showErrorDialog('發生錯誤: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// 開始計數
  /// 注意:這不是啟動服務,只是發送「開始計數」指令給已運行的服務
  ///
  /// 流程:
  /// 1. 確保服務已運行
  /// 2. 發送 'start' 指令和目標次數
  /// 3. 背景任務開始計數
  Future<void> _startCounting() async {
    // 防止重複操作
    if (_isProcessing || _isCounting) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 確保服務已運行
      if (!_isServiceRunning) {
        print('⚠️ 服務未運行,先啟動服務');
        await _startBackgroundService();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      print('▶️ 發送「開始計數」指令,目標: $_targetCount');

      // 發送指令到背景任務
      // 背景任務會在 onReceiveData 方法中接收到這個資料
      FlutterForegroundTask.sendDataToTask({
        'action': 'start', // 指令類型
        'targetCount': _targetCount, // 目標次數
      });

      // 更新 UI 狀態
      setState(() {
        _isCounting = true;
        _currentCount = 0;
      });

      print('✅ 計數已開始');
    } catch (e) {
      print('❌ 開始計數時發生錯誤: $e');
      _showErrorDialog('發生錯誤: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// 停止計數
  /// 注意:這不是停止服務,只是暫停計數,服務仍在運行
  ///
  /// 流程:
  /// 1. 發送 'stop' 指令
  /// 2. 背景任務停止計數但保持運行
  Future<void> _stopCounting() async {
    // 防止重複操作
    if (_isProcessing || !_isCounting) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      print('⏸️ 發送「停止計數」指令');

      // 發送停止指令到背景任務
      FlutterForegroundTask.sendDataToTask({
        'action': 'stop',
      });

      // 更新 UI 狀態
      setState(() {
        _isCounting = false;
      });

      print('✅ 計數已停止');
    } catch (e) {
      print('❌ 停止計數時發生錯誤: $e');
      _showErrorDialog('發生錯誤: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// 完全停止背景服務
  /// 警告:這會終止服務,通常不需要調用
  ///
  /// 流程:
  /// 1. 停止前景服務
  /// 2. 清除所有狀態
  /// 3. 通知欄的通知會消失
  Future<void> _stopBackgroundService() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      print('🛑 準備完全停止背景服務...');

      // 停止前景服務
      // 這會觸發背景任務的 onDestroy 方法
      await FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(milliseconds: 500));

      // 重置所有狀態
      setState(() {
        _isServiceRunning = false;
        _isCounting = false;
        _currentCount = 0;
      });

      print('✅ 背景服務已完全停止');
    } catch (e) {
      print('❌ 停止服務時發生錯誤: $e');
      _showErrorDialog('發生錯誤: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // ==================== UI 輔助方法 ====================

  /// 顯示錯誤對話框
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('錯誤'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  /// 建立目標次數選擇按鈕
  Widget _buildCountButton(int count) {
    final isSelected = _targetCount == count;
    return ElevatedButton(
      onPressed: (_isProcessing || _isCounting)
          ? null
          : () {
              setState(() {
                _targetCount = count;
              });
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
        foregroundColor: isSelected ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: Text(
        '$count 次',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ==================== UI 建構 ====================

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: SafeArea(
        top: false,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('背景計數 + 推播 (長駐模式)'),
            backgroundColor: Colors.blue,
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ========== 服務狀態顯示 ==========
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _isServiceRunning
                          ? Colors.green[100]
                          : Colors.red[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _isServiceRunning ? Icons.check_circle : Icons.cancel,
                          size: 60,
                          color: _isServiceRunning ? Colors.green : Colors.red,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isServiceRunning ? '背景服務運行中' : '背景服務已停止',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_isProcessing) ...[
                          const SizedBox(height: 12),
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '處理中...',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ========== 計數狀態顯示 ==========
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isCounting ? Colors.blue[50] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isCounting
                            ? Colors.blue[300]!
                            : Colors.grey[300]!,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isCounting ? Icons.play_circle : Icons.pause_circle,
                          color: _isCounting ? Colors.blue : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isCounting ? '正在計數' : '已暫停',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _isCounting ? Colors.blue : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ========== 計數顯示區 ==========
                  if (_isServiceRunning) ...[
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue[300]!, width: 3),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            '累積次數',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_currentCount',
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '目標: $_targetCount 次',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: _targetCount > 0
                                ? (_currentCount / _targetCount).clamp(0.0, 1.0)
                                : 0.0,
                            minHeight: 8,
                            backgroundColor: Colors.grey[300],
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],

                  // ========== 目標次數選擇 ==========
                  if (!_isCounting) ...[
                    const Text(
                      '設定目標次數：',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildCountButton(5),
                        const SizedBox(width: 12),
                        _buildCountButton(10),
                        const SizedBox(width: 12),
                        _buildCountButton(20),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],

                  // ========== 開始計數按鈕 ==========
                  ElevatedButton.icon(
                    onPressed: (_isCounting || _isProcessing)
                        ? null
                        : _startCounting,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isProcessing ? '處理中...' : '開始計數'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ========== 停止計數按鈕 ==========
                  ElevatedButton.icon(
                    onPressed: (!_isCounting || _isProcessing)
                        ? null
                        : _stopCounting,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.pause),
                    label: Text(_isProcessing ? '處理中...' : '停止計數'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ========== 使用說明 ==========
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.amber[700]),
                            const SizedBox(width: 8),
                            const Text(
                              '使用說明',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '• 點擊「開始計數」會自動啟動背景服務\n'
                          '• 選擇目標次數後開始計數\n'
                          '• 服務會在背景每 1 秒計數 +1\n'
                          '• 達到目標時會發送推播通知並自動停止\n'
                          '• 可隨時「停止計數」暫停\n'
                          '• 按 Home 鍵切到其他 APP 仍會計數\n'
                          '• 服務會一直運行,無需重啟\n'
                          '• 滑掉通知或點擊「完全停止」才會終止服務',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ========== 完全停止服務按鈕 ==========
                  if (_isServiceRunning) ...[
                    TextButton.icon(
                      onPressed: _isProcessing ? null : _stopBackgroundService,
                      icon: const Icon(Icons.power_settings_new, size: 18),
                      label: const Text('完全停止背景服務'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 背景任務入口 ====================

/// 背景任務的入口函數
/// 這個函數會在背景 isolate 中執行
///
/// 注意事項:
/// 1. 必須是頂層函數 (不能在 class 裡面)
/// 2. 必須加上 @pragma('vm:entry-point') 註解
/// 3. 這個函數會在獨立的 isolate 中執行,無法直接存取 UI 的變數
@pragma('vm:entry-point')
void startCallback() {
  print('═══════════════════════════════════════');
  print('🎬 startCallback 被調用!!!');
  print('🔍 當前 Isolate: ${Isolate.current.debugName}');
  print('🕐 調用時間: ${DateTime.now()}');
  print('═══════════════════════════════════════');

  try {
    FlutterForegroundTask.setTaskHandler(MyTaskHandler());
    print('✅ TaskHandler 已設置');
  } catch (e) {
    print('❌ 設置 TaskHandler 失敗: $e');
  }
}

// ==================== 背景任務處理器 ====================

/// 背景任務處理器
/// 這個 class 在背景 isolate 中執行,與 UI 隔離
///
/// 生命週期:
/// 1. onStart: 服務啟動時執行一次
/// 2. onReceiveData: 收到來自 UI 的資料時執行
/// 3. onRepeatEvent: 每 1 秒執行一次 (在 init 中設定)
/// 4. onDestroy: 服務停止時執行一次
class MyTaskHandler extends TaskHandler {
  // ==================== 狀態變數 ====================

  /// 當前計數
  int _count = 0;

  /// 目標次數
  int _targetCount = 10;

  /// 是否正在計數
  bool _isCounting = false;

  /// 本地推播插件實例
  FlutterLocalNotificationsPlugin? _notificationsPlugin;

  /// 是否已發送推播 (防止重複發送)
  bool _hasNotified = false;

  // ==================== 生命週期方法 ====================

  /// 服務啟動時執行 (只執行一次)
  ///
  /// 執行時機:
  /// - 首次調用 FlutterForegroundTask.startService() 時
  /// - APP 被系統殺掉後重啟時
  ///
  /// 流程:
  /// 1. 初始化狀態變數
  /// 2. 初始化推播系統
  /// 3. 發送「準備完成」訊號給 UI
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('═══════════════════════════════════════');
    print('🚀 背景服務啟動 (長駐模式)');
    print('📅 時間: $timestamp');
    print('📋 Starter 類型: $starter'); // 啟動來源 (user/boot/restart等)
    print('═══════════════════════════════════════');

    // 初始化狀態
    _isCounting = false; // 初始狀態:不計數,等待指令
    _count = 0;
    _hasNotified = false;

    // 初始化推播系統
    await _initializeNotifications();

    // 測試發送資料
    print('🧪 測試發送資料到 Main...');
    // 發送「準備完成」訊號給 UI
    // UI 會在 _onReceiveTaskData 中收到這個訊號
    FlutterForegroundTask.sendDataToMain({
      'type': 'serviceReady',
      'timestamp': timestamp.millisecondsSinceEpoch,
    });

    print('✅ 背景服務初始化完成,等待指令');
  }

  /// 接收來自 UI 的資料
  ///
  /// 執行時機:
  /// - UI 調用 FlutterForegroundTask.sendDataToTask() 時
  ///
  /// 流程:
  /// 1. 解析指令類型 (start/stop)
  /// 2. 根據指令執行對應操作
  /// 3. 更新通知欄的顯示
  @override
  void onReceiveData(Object data) {
    print('═══════════════════════════════════════');
    print('📥 背景任務收到資料！');
    print('📦 資料內容: $data');
    print('═══════════════════════════════════════');

    if (data is Map) {
      final action = data['action'] as String?;

      if (action == 'start') {
        // ========== 開始計數 ==========
        print('▶️ 收到「開始計數」指令');

        // 重置狀態
        _count = 0;
        _hasNotified = false;
        _targetCount = data['targetCount'] as int? ?? 10;
        _isCounting = true;

        // 更新通知欄顯示
        FlutterForegroundTask.updateService(
          notificationTitle: '🔄 背景計數中',
          notificationText: '進度: 0 / $_targetCount',
        );

        print('✅ 已開始計數, 目標: $_targetCount');
      } else if (action == 'stop') {
        // ========== 停止計數 ==========
        print('⏸️ 收到「停止計數」指令');

        // 暫停計數 (但服務仍在運行)
        _isCounting = false;

        // 更新通知欄顯示為待命狀態
        FlutterForegroundTask.updateService(
          notificationTitle: '⏸️ 背景服務',
          notificationText: '待命中 (已計數: $_count)',
        );

        print('✅ 已停止計數');
      }
    }
  }

  /// 定時執行的重複事件
  ///
  /// 執行時機:
  /// - 每 1 秒執行一次 (在 init 中設定 repeat(1000))
  /// - 只要服務在運行就會持續執行
  ///
  /// 流程:
  /// 1. 檢查是否正在計數
  /// 2. 計數 +1
  /// 3. 發送更新給 UI
  /// 4. 更新通知欄
  /// 5. 檢查是否達到目標
  @override
  void onRepeatEvent(DateTime timestamp) {
    // 如果未在計數,直接返回
    if (!_isCounting) return;

    // 計數 +1
    _count++;
    print('⏰ 背景計數: $_count / $_targetCount');

    // 發送計數更新到 UI
    // UI 會在 _onReceiveTaskData 中收到這個資料並更新畫面
    FlutterForegroundTask.sendDataToMain({
      'type': 'countUpdate',
      'count': _count,
    });

    print('📤 已發送計數更新: $_count'); // 👈 加上這行 debug

    // 更新通知欄的顯示
    FlutterForegroundTask.updateService(
      notificationTitle: '🔄 背景計數中',
      notificationText: '進度: $_count / $_targetCount',
    );

    // 檢查是否達到目標
    if (_count >= _targetCount && !_hasNotified) {
      print('═══════════════════════════════════════');
      print('🎯 達到目標次數！準備發送推播');
      print('═══════════════════════════════════════');

      _hasNotified = true;
      _isCounting = false; // 自動停止計數

      // 發送推播通知
      _sendNotification();

      // 更新通知欄為完成狀態
      FlutterForegroundTask.updateService(
        notificationTitle: '✅ 計數完成',
        notificationText: '已完成 $_count / $_targetCount',
      );

      // 通知 UI 計數已完成
      FlutterForegroundTask.sendDataToMain({
        'type': 'countingFinished',
        'count': _count,
      });

      print('✅ 已自動停止計數');
    }
  }

  /// 服務銷毀時執行
  ///
  /// 執行時機:
  /// - 調用 FlutterForegroundTask.stopService() 時
  /// - 用戶在通知欄滑掉通知時
  /// - 系統強制停止 APP 時
  ///
  /// 流程:
  /// 1. 清理資源
  /// 2. 重置狀態
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeOut) async {
    print('═══════════════════════════════════════');
    print('🛑 背景服務停止！');
    print('📊 最終計數: $_count / $_targetCount');
    print('⏱️ 時間: $timestamp');
    print('⏰ 是否超時: $isTimeOut'); // 通常是 false
    print('═══════════════════════════════════════');

    // 清理資源
    _isCounting = false;
    _notificationsPlugin = null;

    print('✅ 資源清理完成');
  }

  // ==================== 輔助方法 ====================

  /// 初始化推播通知系統
  Future<void> _initializeNotifications() async {
    try {
      _notificationsPlugin = FlutterLocalNotificationsPlugin();

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );

      await _notificationsPlugin!.initialize(settings);
      print('✅ 推播系統已初始化');
    } catch (e) {
      print('❌ 推播系統初始化失敗: $e');
    }
  }

  /// 發送達成目標的推播通知
  ///
  /// 功能:
  /// - 高優先級通知 (會顯示在最上方)
  /// - 有聲音和震動
  /// - 有 LED 燈效 (部分裝置支援)
  Future<void> _sendNotification() async {
    print('🎉 開始發送推播通知...');

    try {
      // Android 通知詳細設定
      final androidDetails = AndroidNotificationDetails(
        'achievement_channel', // 頻道 ID (與前景服務不同頻道)
        '成就通知', // 頻道名稱
        channelDescription: '達成目標時的通知',
        importance: Importance.high, // 高重要性
        priority: Priority.high, // 高優先級
        showWhen: true, // 顯示時間
        playSound: true, // 播放聲音
        enableVibration: true, // 震動
        vibrationPattern: Int64List.fromList(const [
          0,
          1000,
          500,
          1000,
        ]), // 震動模式
        color: const Color(0xFF2196F3), // 通知顏色
        ledColor: const Color(0xFF2196F3), // LED 顏色
        ledOnMs: 1000, // LED 亮 1 秒
        ledOffMs: 500, // LED 滅 0.5 秒
      );

      // iOS 通知設定
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true, // 顯示橫幅
        presentBadge: true, // 顯示角標
        presentSound: true, // 播放聲音
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // 發送通知
      // id: 999 (與前景服務的通知 ID 不同,避免衝突)
      await _notificationsPlugin?.show(
        999,
        '🎉 目標達成！',
        '已累積 $_count 次，太棒了！',
        details,
      );

      print('✅ 推播通知已發送');
    } catch (e) {
      print('❌ 發送推播失敗: $e');
    }
  }
}
