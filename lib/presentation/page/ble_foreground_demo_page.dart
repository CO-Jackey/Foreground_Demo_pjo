// lib/presentation/page/ble_foreground_demo_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

/// ✅ 完全背景化的藍牙前景服務
/// SDK 在背景 isolate 中直接呼叫
class BleForegroundPage extends StatefulWidget {
  const BleForegroundPage({super.key});

  @override
  State<BleForegroundPage> createState() => _BleForegroundPageState();
}

class _BleForegroundPageState extends State<BleForegroundPage> {
  bool _isServiceRunning = false;
  bool _isProcessing = false;
  String? _connectedDeviceName;

  // 即時數據
  int _hr = 0;
  int _br = 0;
  double _temp = 0;
  int _power = 0;
  bool _isWearing = false;
  int _dataCount = 0;

  List<String> _logs = [];
  static int _serviceIdCounter = 30000;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }
  }

  void _onReceiveTaskData(dynamic data) {
    if (data is Map) {
      final type = data['type'] as String?;

      switch (type) {
        case 'serviceReady':
          setState(() => _isServiceRunning = true);
          _addLog('✅ 背景服務已就緒');
          break;

        case 'bleConnected':
          final deviceName = data['deviceName'] as String;
          setState(() {
            _connectedDeviceName = deviceName;
            _dataCount = 0;
          });
          _addLog('✅ 已連接: $_connectedDeviceName');
          break;

        case 'bleDisconnected':
          setState(() {
            _connectedDeviceName = null;
            _dataCount = 0;
          });
          _addLog('⚠️ 設備已斷線');
          break;

        case 'healthData':
          // ✅ 接收背景處理完成的健康數據
          setState(() {
            _hr = data['hr'] ?? 0;
            _br = data['br'] ?? 0;
            _temp = (data['temp'] ?? 0).toDouble();
            _power = data['power'] ?? 0;
            _isWearing = data['isWearing'] ?? false;
            _dataCount++;
          });
          break;

        case 'log':
          _addLog(data['message'] ?? '');
          break;

        case 'error':
          _addLog('❌ ${data['message']}');
          break;
      }
    }
  }

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _logs.insert(
          0,
          '[${DateTime.now().toString().substring(11, 19)}] $message',
        );
        if (_logs.length > 50) _logs.removeLast();
      });
    }
  }

  Future<void> _startService() async {
    setState(() => _isProcessing = true);

    try {
      await FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(seconds: 1));

      _serviceIdCounter++;

      final started = await FlutterForegroundTask.startService(
        serviceId: _serviceIdCounter,
        notificationTitle: '🔵 藍牙服務',
        notificationText: '待命中...',
        callback: bleStartCallback,
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
        _connectedDeviceName = null;
        _dataCount = 0;
      });
      _addLog('🛑 服務已停止');
    } catch (e) {
      _addLog('❌ 停止失敗: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _scanAndConnect() {
    if (!_isServiceRunning) {
      _addLog('⚠️ 請先啟動服務');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BleQuickScanDialog(
        onDeviceSelected: (deviceId, deviceName) {
          Navigator.pop(context);
          FlutterForegroundTask.sendDataToTask({
            'action': 'connectDevice',
            'deviceId': deviceId,
            'deviceName': deviceName,
          });
          _addLog('🔗 正在連接 $deviceName...');
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  void _disconnectDevice() {
    FlutterForegroundTask.sendDataToTask({
      'action': 'disconnect',
    });
    _addLog('🔌 發送斷線指令');
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: SafeArea(
        top: false,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('藍牙前景服務 (全背景化)'),
            backgroundColor: Colors.indigo,
          ),
          body: Column(
            children: [
              // 控制區
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.indigo[50],
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: !_isServiceRunning && !_isProcessing
                                ? _startService
                                : null,
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
                            onPressed: _isServiceRunning && !_isProcessing
                                ? _stopService
                                : null,
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
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _isServiceRunning &&
                                    _connectedDeviceName == null
                                ? _scanAndConnect
                                : null,
                            icon: const Icon(Icons.bluetooth_searching),
                            label: const Text('掃描連接'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _connectedDeviceName != null
                                ? _disconnectDevice
                                : null,
                            icon: const Icon(Icons.bluetooth_disabled),
                            label: const Text('斷開藍牙'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isServiceRunning
                            ? Colors.green[100]
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _isServiceRunning
                                    ? '🟢 服務運行中 (全背景)'
                                    : '⚫ 服務已停止',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '收到 $_dataCount 筆',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (_connectedDeviceName != null) ...[
                            const Divider(height: 16),
                            Text(
                              '📱 $_connectedDeviceName',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 數據顯示區 (與原來相同)
              if (_connectedDeviceName != null) ...[
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '📊 即時數據 (完全背景處理)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildDataCard('💓 心率', '$_hr', 'bpm'),
                          _buildDataCard('🫁 呼吸', '$_br', 'bpm'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildDataCard(
                            '🌡️ 溫度',
                            _temp.toStringAsFixed(1),
                            '°C',
                          ),
                          _buildDataCard('🔋 電量', '$_power', '%'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isWearing
                              ? Colors.green[100]
                              : Colors.red[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isWearing ? Icons.check_circle : Icons.cancel,
                              color: _isWearing ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isWearing ? '✅ 已佩戴' : '❌ 未佩戴',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 日誌區 (與原來相同)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
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

  Widget _buildDataCard(String label, String value, String unit) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          Text(
            unit,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ==================== 掃描 Dialog (保持不變) ====================

class _BleQuickScanDialog extends StatefulWidget {
  final Function(String deviceId, String deviceName) onDeviceSelected;
  final VoidCallback onCancel;

  const _BleQuickScanDialog({
    required this.onDeviceSelected,
    required this.onCancel,
  });

  @override
  State<_BleQuickScanDialog> createState() => _BleQuickScanDialogState();
}

class _BleQuickScanDialogState extends State<_BleQuickScanDialog> {
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });
      }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10)).then((_) {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('選擇設備'),
          const Spacer(),
          if (_isScanning)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: _scanResults.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _isScanning ? '正在掃描...' : '未發現設備',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final result = _scanResults[index];
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(
                      result.device.platformName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(result.device.remoteId.toString()),
                    trailing: Text('${result.rssi} dBm'),
                    onTap: () {
                      widget.onDeviceSelected(
                        result.device.remoteId.str,
                        result.device.platformName,
                      );
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消'),
        ),
      ],
    );
  }
}

// ==================== 背景任務入口 ====================

@pragma('vm:entry-point')
void bleStartCallback() {
  print('🎬 藍牙背景服務啟動 (全背景化架構)');
  FlutterForegroundTask.setTaskHandler(BleTaskHandler());
}

// ==================== 背景任務處理器 ====================

class BleTaskHandler extends TaskHandler {
  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  // ✅ 儲存最新的健康數據 (用於更新通知)
  int _hr = 0;
  int _br = 0;
  double _temp = 0;
  int _power = 0;
  bool _isWearing = false;
  int _dataCount = 0;

  // ✅ 新增：SDK 包裝器 (在背景 isolate 中)
  _BackgroundSDKWrapper? _sdkWrapper;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🚀 藍牙背景服務已啟動 (全背景化)');

    // ✅ 初始化背景 SDK 包裝器
    _sdkWrapper = _BackgroundSDKWrapper();
    await _sdkWrapper!.initialize(3);

    FlutterForegroundTask.sendDataToMain({
      'type': 'serviceReady',
    });

    FlutterForegroundTask.updateService(
      notificationTitle: '🔵 藍牙服務',
      notificationText: '待命中 (未連接)',
    );
  }

  @override
  void onReceiveData(Object data) async {
    if (data is Map) {
      final action = data['action'] as String?;

      switch (action) {
        case 'connectDevice':
          await _connectDevice(
            data['deviceId'] as String,
            data['deviceName'] as String,
          );
          break;

        case 'disconnect':
          await _disconnectDevice();
          break;
      }
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 定時更新通知
    if (_connectedDevice != null) {
      FlutterForegroundTask.updateService(
        notificationTitle: '📱 ${_connectedDevice!.platformName}',
        notificationText:
            '💓 $_hr | 🫁 $_br | 🌡️ ${_temp.toStringAsFixed(1)}°C | 🔋 $_power% | ${_isWearing ? "✅" : "❌"}',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeOut) async {
    print('🛑 藍牙背景服務停止');
    await _disconnectDevice();
    _sdkWrapper?.dispose();
  }

  // ==================== 藍牙操作 ====================

  Future<void> _connectDevice(String deviceId, String deviceName) async {
    try {
      print('🔗 嘗試連接: $deviceName');

      final device = BluetoothDevice.fromId(deviceId);

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print('⚠️ 設備斷線');
          _handleDisconnection();
        }
      });

      await device.connect(timeout: const Duration(seconds: 15));
      print('✅ 連接成功');

      _connectedDevice = device;

      FlutterForegroundTask.sendDataToMain({
        'type': 'bleConnected',
        'deviceId': deviceId,
        'deviceName': deviceName,
      });

      final services = await device.discoverServices();
      print('🔍 發現 ${services.length} 個服務');

      await _subscribeToFFF4(services, deviceId);
      await _sendTimestamp(services);

      FlutterForegroundTask.updateService(
        notificationTitle: '📱 $deviceName',
        notificationText: '已連接,監測中...',
      );
    } catch (e) {
      print('❌ 連接失敗: $e');
      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'message': '連接失敗: $e',
      });
    }
  }

  Future<void> _subscribeToFFF4(
    List<BluetoothService> services,
    String deviceId,
  ) async {
    try {
      BluetoothCharacteristic? fff4;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toUpperCase().contains('FFF4')) {
            fff4 = characteristic;
            break;
          }
        }
        if (fff4 != null) break;
      }

      if (fff4 == null) {
        print('❌ 找不到 FFF4');
        return;
      }

      print('✅ 找到 FFF4');

      await fff4.setNotifyValue(true);
      _notifySubscription = fff4.lastValueStream.listen((value) async {
        _dataCount++;

        if (value.isNotEmpty && _sdkWrapper != null) {
          // ✅ 直接在背景 isolate 處理 SDK
          final result = await _sdkWrapper!.splitPackage(
            Uint8List.fromList(value),
            deviceId,
          );

          if (result != null) {
            // 更新本地數據
            _hr = result['HRValue'] ?? 0;
            _br = result['BRValue'] ?? 0;
            _temp = (result['TempValue'] ?? 0).toDouble();
            _power = result['PowerValue'] ?? 0;
            _isWearing = result['IsWearing'] ?? false;

            // 發送給主 isolate (UI 更新)
            FlutterForegroundTask.sendDataToMain({
              'type': 'healthData',
              'hr': _hr,
              'br': _br,
              'temp': _temp,
              'power': _power,
              'isWearing': _isWearing,
            });

            print('📊 背景處理 #$_dataCount: HR=$_hr BR=$_br');
          }
        }
      });

      print('✅ 已訂閱 FFF4');

      FlutterForegroundTask.sendDataToMain({
        'type': 'log',
        'message': '✅ 已訂閱 FFF4 通知',
      });
    } catch (e) {
      print('❌ 訂閱失敗: $e');
    }
  }

  Future<void> _sendTimestamp(List<BluetoothService> services) async {
    BluetoothCharacteristic? char;
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.toString().toUpperCase().contains('FFF5')) {
          char = characteristic;
          break;
        }
      }
      if (char != null) break;
    }

    if (char == null || !char.properties.write) {
      print('⚠️ 找不到 FFF5 或不支持寫入');
      return;
    }

    try {
      await char.write(_getTimestamp1Command(), withoutResponse: false);
      print('✅ 已發送 Timestamp1');
      await Future.delayed(const Duration(milliseconds: 100));

      await char.write(_getTimestamp2Command(), withoutResponse: false);
      print('✅ 已發送 Timestamp2');
    } catch (e) {
      print('❌ 時間同步失敗: $e');
    }
  }

  Uint8List _getTimestamp1Command() {
    final now = DateTime.now();
    int timestamp = now.millisecondsSinceEpoch;
    timestamp += now.timeZoneOffset.inMilliseconds;
    timestamp = timestamp ~/ 10;

    final command = Uint8List(4);
    command[0] = 0xEA;
    command[1] = (timestamp >> 0) & 0xFF;
    command[2] = (timestamp >> 8) & 0xFF;
    command[3] = (timestamp >> 16) & 0xFF;
    return command;
  }

  Uint8List _getTimestamp2Command() {
    final now = DateTime.now();
    int timestamp = now.millisecondsSinceEpoch;
    timestamp += now.timeZoneOffset.inMilliseconds;
    timestamp = timestamp ~/ 10;

    final command = Uint8List(3);
    command[0] = 0xEB;
    command[1] = (timestamp >> 24) & 0xFF;
    command[2] = (timestamp >> 32) & 0xFF;
    return command;
  }

  Future<void> _disconnectDevice() async {
    _connectionSubscription?.cancel();
    _notifySubscription?.cancel();

    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      print('❌ 斷線錯誤: $e');
    }

    _connectedDevice = null;
    _dataCount = 0;

    FlutterForegroundTask.sendDataToMain({
      'type': 'bleDisconnected',
    });

    FlutterForegroundTask.updateService(
      notificationTitle: '🔵 藍牙服務',
      notificationText: '待命中 (未連接)',
    );

    print('🔌 已斷線');
  }

  void _handleDisconnection() {
    _connectedDevice = null;
    _dataCount = 0;

    FlutterForegroundTask.sendDataToMain({
      'type': 'bleDisconnected',
    });

    FlutterForegroundTask.updateService(
      notificationTitle: '🔵 藍牙服務',
      notificationText: '設備已斷線',
    );
  }
}

// ==================== ✅ 背景 SDK 包裝器 ====================

class _BackgroundSDKWrapper {
  static const _channel = MethodChannel(
    'com.example.foreground_demo_pjo/health_calculate',
  );

  Future<void> initialize(int type) async {
    try {
      await _channel.invokeMethod('initialize', {'type': type});
      print('[背景SDK] 已初始化 (type: $type)');
    } catch (e) {
      print('[背景SDK] 初始化失敗: $e');
    }
  }

  Future<Map<String, dynamic>?> splitPackage(
    Uint8List data,
    String deviceId,
  ) async {
    try {
      final result = await _channel.invokeMethod<Map>('splitPackage', {
        'data': data,
        'deviceId': deviceId,
      });

      return result?.cast<String, dynamic>();
    } catch (e) {
      print('[背景SDK] 處理失敗: $e');
      return null;
    }
  }

  Future<void> dispose([String? deviceId]) async {
    try {
      await _channel.invokeMethod('dispose', {
        if (deviceId != null) 'deviceId': deviceId,
      });
      print('[背景SDK] 已清理${deviceId != null ? " $deviceId" : "所有實例"}');
    } catch (e) {
      print('[背景SDK] 清理失敗: $e');
    }
  }
}
