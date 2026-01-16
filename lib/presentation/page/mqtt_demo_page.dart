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

          case 'fetchStart':
            _addLog('🔄 開始拉取數據 #${data['pollCount']}');
            break;

          case 'fetchSuccess':
            _addLog(
              '✅ 拉取成功 (${data['statusCode']}) - 耗時: ${data['duration']}ms',
            );
            break;

          case 'fetchEmpty':
            _addLog('⚠️ 拉取成功但無數據 (${data['statusCode']})');
            break;

          case 'mqttData':
            _dataCount++;
            _latestData = data as Map<String, dynamic>?;
            
            final packetType = data['packetType'] ?? 'unknown';
            String logMessage = '📥 解析數據 #$_dataCount: GUID=${data['guid']}';
            
            switch (packetType) {
              case 'simple':
                logMessage += ', Message="${data['message']}"';
                break;
              case 'hex':
                logMessage += ', ${data['bytesCount']} bytes';
                break;
              case 'json':
                logMessage += ', JSON 數據';
                break;
            }
            
            _addLog(logMessage);
            break;

          case 'parseError':
            _addLog('❌ 解析失敗: ${data['message']}');
            break;

          case 'error':
            _addLog('❌ 拉取錯誤 (${data['statusCode']}): ${data['message']}');
            break;

          case 'timeout':
            _addLog('⏱️ 請求超時 #${data['pollCount']}');
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

  Future<void> _reloadService() async {
    setState(() => _isProcessing = true);
    _addLog('🔄 正在重整服務...');

    try {
      // 移除舊的 callback
      FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
      await Future.delayed(const Duration(milliseconds: 300));

      // 重新註冊 callback
      FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
      await Future.delayed(const Duration(milliseconds: 300));

      _addLog('✅ 服務重整完成');
    } catch (e) {
      _addLog('❌ 重整失敗: $e');
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
            actions: [
              // 重整按鈕
              IconButton(
                onPressed: _isProcessing ? null : _reloadService,
                icon: const Icon(Icons.refresh),
                tooltip: '重整服務',
              ),
            ],
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
                    // 重整按鈕（大按鈕版本）
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _reloadService,
                        icon: const Icon(Icons.refresh),
                        label: const Text('🔄 重新載入服務'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
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
                      Text('GUID: ${_latestData!['guid']}'),
                      Text('類型: ${_latestData!['packetType']}'),
                      Text('時間戳: ${_latestData!['timestamp']}'),
                      if (_latestData!['message'] != null)
                        Text('訊息: ${_latestData!['message']}'),
                      if (_latestData!['hexPreview'] != null)
                        Text('Hex 預覽: ${_latestData!['hexPreview']}'),
                      if (_latestData!['content'] != null)
                        Text('內容: ${_latestData!['content']}'),
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

    final startTime = DateTime.now();
    String? responseCode;

    // 通知開始拉取
    FlutterForegroundTask.sendDataToMain({
      'type': 'fetchStart',
      'pollCount': _pollCount,
    });

    try {
      final url = '$_apiBaseUrl/api/ipetdata/mqtt-message';
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'Accept': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              FlutterForegroundTask.sendDataToMain({
                'type': 'timeout',
                'pollCount': _pollCount,
              });
              throw Exception('請求超時');
            },
          );

      responseCode = response.statusCode.toString();
      final duration = DateTime.now().difference(startTime).inMilliseconds;

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['Success'] == true && json['Data'] != null) {
          _currentPoll++;

          // 通知拉取成功
          FlutterForegroundTask.sendDataToMain({
            'type': 'fetchSuccess',
            'statusCode': responseCode,
            'duration': duration,
            'pollCount': _pollCount,
          });

          devLog('response', response.body);

          // 解析數據
          await _parseAndSendData(json['Data']);
        } else {
          // 拉取成功但無數據
          FlutterForegroundTask.sendDataToMain({
            'type': 'fetchEmpty',
            'statusCode': responseCode,
            'pollCount': _pollCount,
          });
        }
      } else {
        // HTTP 錯誤狀態碼
        FlutterForegroundTask.sendDataToMain({
          'type': 'error',
          'message': 'HTTP ${response.statusCode}',
          'statusCode': responseCode,
          'pollCount': _pollCount,
        });
      }

      // 更新通知
      FlutterForegroundTask.updateService(
        notificationTitle: '🔄 MQTT 監聽中',
        notificationText: '已拉取 $_pollCount 次, 有效 $_currentPoll 筆',
      );
    } catch (e) {
      print('❌ 拉取失敗: $e');

      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'message': e.toString(),
        'statusCode': responseCode ?? 'N/A',
        'pollCount': _pollCount,
      });
    } finally {
      _isProcessing = false;
    }
  }

  /// 解析數據並發送給 UI
  Future<void> _parseAndSendData(Map<String, dynamic> data) async {
    try {
      final guid = data['GUID'] as String? ?? 'Unknown';
      final packetStr = data['packet'] as String?;

      if (packetStr == null || packetStr.isEmpty) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'parseError',
          'message': 'packet 為空',
        });
        return;
      }

      // 嘗試解析 packet JSON
      final packetJson = jsonDecode(packetStr);
      
      print('✅ 解析成功 - GUID: $guid');
      print('📦 Packet 內容: $packetJson');

      // 判斷 packet 內容類型
      if (packetJson is Map) {
        // 情況1: 簡單的 JSON 物件 (如 {"msg": "hello"})
        if (packetJson.containsKey('msg')) {
          FlutterForegroundTask.sendDataToMain({
            'type': 'mqttData',
            'guid': guid,
            'packetType': 'simple',
            'message': packetJson['msg'],
            'timestamp': DateTime.now().toIso8601String(),
            'summary': 'Message: ${packetJson['msg']}',
          });
        }
        // 情況2: 包含 hex data 的複雜結構
        else if (packetJson.containsKey('packet')) {
          final innerPackets = packetJson['packet'] as List<dynamic>?;
          
          if (innerPackets != null && innerPackets.isNotEmpty) {
            for (final item in innerPackets) {
              final hexData = item['data'] as String?;
              if (hexData != null) {
                final rawBytes = _hexToBytes(hexData);

                FlutterForegroundTask.sendDataToMain({
                  'type': 'mqttData',
                  'guid': guid,
                  'packetType': 'hex',
                  'bytesCount': rawBytes.length,
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
        }
        // 情況3: 其他 JSON 結構
        else {
          FlutterForegroundTask.sendDataToMain({
            'type': 'mqttData',
            'guid': guid,
            'packetType': 'json',
            'content': packetJson.toString(),
            'timestamp': DateTime.now().toIso8601String(),
            'summary': 'JSON 數據: ${packetJson.keys.join(", ")}',
          });
        }
      }
    } catch (e) {
      print('❌ 解析失敗: $e');

      FlutterForegroundTask.sendDataToMain({
        'type': 'parseError',
        'message': e.toString(),
      });
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
