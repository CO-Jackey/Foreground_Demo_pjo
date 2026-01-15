// lib/presentation/page/mqtt_test_page.dart

import 'dart:isolate';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:foreground_demo_pjo/helper/devLog.dart';
import 'package:http/http.dart' as http;

/// MQTT 測試頁面
/// 驗證前景服務可以拉取和解析 MQTT 數據
class MqttTestPage extends StatefulWidget {
  const MqttTestPage({super.key});

  @override
  State<MqttTestPage> createState() => _MqttTestPageState();
}

class _MqttTestPageState extends State<MqttTestPage> {
  bool _isServiceRunning = false;
  bool _isProcessing = false;
  List<String> _logs = [];
  int _dataCount = 0;
  Map<String, dynamic>? _latestData;

  static int _serviceIdCounter = 20000;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    super.dispose();
  }

  void _onReceiveTaskData(dynamic data) {
    if (data is Map) {
      setState(() {
        final type = data['type'] as String?;

        switch (type) {
          case 'serviceReady':
            _isServiceRunning = true;
            _addLog('✅ 服務已就緒');
            break;

          case 'mqttData':
            _dataCount++;
            _latestData = data as Map<String, dynamic>?;
            _addLog('📥 收到數據 #$_dataCount: ${data['summary']}');
            break;

          case 'error':
            _addLog('❌ 錯誤: ${data['message']}');
            break;
        }
      });
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs.insert(
        0,
        '[${DateTime.now().toString().substring(11, 19)}] $message',
      );
      if (_logs.length > 50) {
        _logs.removeLast();
      }
    });
  }

  Future<void> _startService() async {
    setState(() => _isProcessing = true);

    try {
      await FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(seconds: 1));

      _serviceIdCounter++;

      final started = await FlutterForegroundTask.startService(
        serviceId: _serviceIdCounter,
        notificationTitle: '🔄 MQTT 監聽中',
        notificationText: '正在拉取數據...',
        callback: mqttStartCallback,
      );

      if (started != null) {
        setState(() {
          _isServiceRunning = true;
          _logs.clear();
        });
        _addLog('🚀 服務已啟動 #$_serviceIdCounter');
      }
    } catch (e) {
      _addLog('❌ 啟動失敗: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _stopService() async {
    setState(() => _isProcessing = true);

    try {
      await FlutterForegroundTask.stopService();
      setState(() {
        _isServiceRunning = false;
        _dataCount = 0;
        _latestData = null;
      });
      _addLog('🛑 服務已停止');
    } catch (e) {
      _addLog('❌ 停止失敗: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: SafeArea(
        top: false,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('MQTT 測試'),
            backgroundColor: Colors.purple,
          ),
          body: Column(
            children: [
              // 控制區
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.purple[50],
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing || _isServiceRunning
                                ? null
                                : _startService,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('啟動服務'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing || !_isServiceRunning
                                ? null
                                : _stopService,
                            icon: const Icon(Icons.stop),
                            label: const Text('停止服務'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 狀態顯示
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isServiceRunning
                            ? Colors.green[100]
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isServiceRunning ? '🟢 運行中' : '⚫ 已停止',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '收到 $_dataCount 筆數據',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 最新數據顯示
              if (_latestData != null) ...[
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📊 最新數據',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      Text('原始數據長度: ${_latestData!['dataLength']}'),
                      Text('時間戳: ${_latestData!['timestamp']}'),
                      if (_latestData!['hexPreview'] != null)
                        Text('前16字節: ${_latestData!['hexPreview']}'),
                    ],
                  ),
                ),
              ],

              // 日誌區
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '📝 運行日誌',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _logs.clear()),
                              child: const Text('清除'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _logs.isEmpty
                            ? const Center(child: Text('暫無日誌'))
                            : ListView.builder(
                                itemCount: _logs.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey[300]!,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      _logs[index],
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 背景任務入口 ====================

@pragma('vm:entry-point')
void mqttStartCallback() {
  print('🎬 MQTT 背景服務啟動');
  FlutterForegroundTask.setTaskHandler(MqttTaskHandler());
}

// ==================== 背景任務處理器 ====================

class MqttTaskHandler extends TaskHandler {
  static const String _apiBaseUrl = 'http://172.24.101.88:9998';
  int _pollCount = 0;
  int _currentPoll = 0;
  bool _isProcessing = false;
  Map<String, dynamic>? _latestData;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🚀 MQTT 監聽服務啟動');

    FlutterForegroundTask.sendDataToMain({
      'type': 'serviceReady',
    });
  }

  @override
  void onReceiveData(Object data) {
    // 目前不需要處理 UI 傳來的指令
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 每秒執行一次拉取
    if (!_isProcessing) {
      _fetchMqttData();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeOut) async {
    print('🛑 MQTT 監聽服務停止');
  }

  // ==================== 核心功能 ====================

  /// 拉取 MQTT 數據
  Future<void> _fetchMqttData() async {
    _isProcessing = true;
    _pollCount++;

    String? responseCode;

    try {
      final url = '$_apiBaseUrl/api/ipetdata/mqtt-message';
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      responseCode = response.statusCode.toString();

      if (response.statusCode == 200) {
        _currentPoll++;
        final json = jsonDecode(response.body);

        if (json['Success'] == true && json['Data'] != null) {
          // ✅ 解析 packet 中的 msg
          String? msg;
          try {
            final packetStr = _latestData?['packet'] as String?;
            if (packetStr != null) {
              final packetJson = jsonDecode(packetStr) as Map<String, dynamic>;
              msg = packetJson['msg'] as String?;

              // 把 msg 存到 _latestData 方便使用
              _latestData!['msg'] = msg;

              devLog('MQTT Message', 'msg: $msg');
            }
          } catch (e) {
            devLog('Parse Error', 'Failed to parse packet: $e');
          }
          await _parseAndSendData(json['Data']);
        }
      }

      // 更新通知
      FlutterForegroundTask.updateService(
        notificationTitle: '🔄 MQTT 監聽中',
        notificationText:
            '資料:${_latestData?['msg']} 已拉取 $_pollCount 次, 本次有效 $_currentPoll 筆',
      );
    } catch (e) {
      print('❌ 拉取失敗: $e');

      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'message': e.toString(),
        'status code': responseCode,
      });
    } finally {
      _isProcessing = false;
    }
  }

  /// 解析數據並發送給 UI
  Future<void> _parseAndSendData(Map<String, dynamic> data) async {
    try {
      var packetStr = data['packet'] as String?;
      if (packetStr == null) return;

      // 修復 JSON 格式
      packetStr = packetStr.replaceAllMapped(
        RegExp(r'"data":([a-fA-F0-9]+)'),
        (match) => '"data":"${match.group(1)}"',
      );

      final packetJson = jsonDecode(packetStr);
      final innerPackets = packetJson['packet'] as List<dynamic>?;

      if (innerPackets != null && innerPackets.isNotEmpty) {
        for (final item in innerPackets) {
          final hexData = item['data'] as String?;
          if (hexData != null) {
            final rawBytes = _hexToBytes(hexData);

            print('✅ 解析成功: ${rawBytes.length} bytes');

            // 發送給 UI
            FlutterForegroundTask.sendDataToMain({
              'type': 'mqttData',
              'dataLength': rawBytes.length,
              'hexPreview': hexData.substring(
                0,
                hexData.length > 32 ? 32 : hexData.length,
              ),
              'timestamp': DateTime.now().toIso8601String(),
              'summary': 'Hex: ${hexData.length ~/ 2} bytes',
            });
          }
        }
      }
    } catch (e) {
      print('❌ 解析失敗: $e');
    }
  }

  /// Hex String 轉 Uint8List
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      final num = hex.substring(i, i + 2);
      final byte = int.parse(num, radix: 16);
      result[i ~/ 2] = byte;
    }
    return result;
  }
}
