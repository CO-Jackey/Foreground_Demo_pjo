// lib/presentation/page/ble_demo_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:foreground_demo_pjo/data/datasources/HealthCalculate_Device_ID.dart';
import 'package:foreground_demo_pjo/helper/devLog.dart';
import 'package:permission_handler/permission_handler.dart';

/// 藍牙 SDK 測試頁面
/// 驗證藍牙連線 → 訂閱 FFF4 → SDK 解析功能
class BleTestPage extends StatefulWidget {
  const BleTestPage({super.key});

  @override
  State<BleTestPage> createState() => _BleTestPageState();
}

class _BleTestPageState extends State<BleTestPage> {
  // 狀態變數
  BluetoothDevice? _connectedDevice;
  HealthCalculateDeviceID? _healthCalculator;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  // 顯示的數據
  int _hr = 0;
  int _br = 0;
  double _temp = 0;
  int _power = 0;
  bool _isWearing = false;
  int _dataCount = 0;
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _disconnect(updateState: false);
    _notifySubscription?.cancel();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  // ==================== 權限管理 ====================

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }
  }

  // ==================== 藍牙操作 ====================

  Future<void> _startScan() async {
    // 檢查藍牙是否開啟
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      _addLog('❌ 請先開啟藍牙');
      return;
    }

    _addLog('🔍 開始掃描...');

    // ✅ 修正:使用 showDialog 的正確方式
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ScanDialog(
        onDeviceSelected: (device) async {
          Navigator.of(dialogContext).pop();
          await _connectToDevice(device);
        },
        onCancel: () {
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _addLog('🔗 正在連接 ${device.platformName}...');

    try {
      // 監聽連線狀態
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _addLog('⚠️ 設備已斷線');
          if (mounted) {
            setState(() {
              _connectedDevice = null;
              _healthCalculator = null;
            });
          }
        }
      });

      // 連接設備
      await device.connect(timeout: const Duration(seconds: 15));
      _addLog('✅ 連接成功');

      // 探索服務
      final services = await device.discoverServices();
      _addLog('🔍 發現 ${services.length} 個服務');

      // 初始化 SDK (type: 3 代表狗)
      _healthCalculator = HealthCalculateDeviceID(3);
      _addLog('✅ SDK 已初始化 (type: 3)');

      // 尋找 FFF4 特徵並訂閱
      await _subscribeToFFF4(services, device.remoteId.str);

      setState(() {
        _connectedDevice = device;
        _dataCount = 0;
      });
    } catch (e) {
      _addLog('❌ 連接失敗: $e');
      _disconnect();
    }
  }

  Future<void> _subscribeToFFF4(
    List<BluetoothService> services,
    String deviceId,
  ) async {
    try {
      // 找到 FFF4 特徵
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
        _addLog('❌ 找不到 FFF4 特徵');
        return;
      }

      _addLog('✅ 找到 FFF4 特徵');

      // 訂閱通知
      await fff4.setNotifyValue(true);
      _notifySubscription = fff4.lastValueStream.listen((value) async {
        _dataCount++;

        // 餵給 SDK
        if (_healthCalculator != null && value.isNotEmpty) {
          await _healthCalculator!.splitPackage(
            Uint8List.fromList(value),
            deviceId,
          );

          // 取得結果
          final hr = _healthCalculator!.getHRValue();
          final br = _healthCalculator!.getBRValue();
          final temp = _healthCalculator!.getTempValue();
          final power = _healthCalculator!.getPowerValue();
          final isWearing = _healthCalculator!.getIsWearing();

          if (mounted) {
            setState(() {
              _hr = hr;
              _br = br;
              _temp = temp;
              _power = power;
              _isWearing = isWearing;
            });
          }

          _addLog('📊 #$_dataCount: HR=$hr BR=$br');
        }
      });

      _addLog('✅ 已訂閱 FFF4 通知');

      // 發送時間同步
      await _sendTimeSync(services);
    } catch (e) {
      _addLog('❌ 訂閱失敗: $e');
    }
  }

  Future<void> _sendTimeSync(List<BluetoothService> services) async {
    try {
      // 找到 FFF5 特徵
      BluetoothCharacteristic? fff5;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toUpperCase().contains('FFF5')) {
            fff5 = characteristic;
            break;
          }
        }
        if (fff5 != null) break;
      }

      if (fff5 != null && fff5.properties.write) {
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 10;
        final byteData = ByteData(8)..setInt64(0, timestamp, Endian.little);

        final command = Uint8List(6)
          ..[0] = 0xfc
          ..[1] = byteData.getUint8(0)
          ..[2] = byteData.getUint8(1)
          ..[3] = byteData.getUint8(2)
          ..[4] = byteData.getUint8(3)
          ..[5] = byteData.getUint8(4);

        await fff5.write(command, withoutResponse: false);
        _addLog('⏰ 時間同步已發送');
      }
    } catch (e) {
      _addLog('⚠️ 時間同步失敗: $e');
    }
  }

  void _disconnect({bool updateState = true}) {
    _connectionStateSubscription?.cancel();
    _notifySubscription?.cancel();

    try {
      _connectedDevice?.disconnect();
    } catch (e) {
      devLog('斷線錯誤', '$e');
    }

    if (updateState && mounted) {
      setState(() {
        _connectedDevice = null;
        _healthCalculator = null;
      });
    } else {
      _connectedDevice = null;
      _healthCalculator = null;
    }

    _addLog('🔌 已斷線');
  }

  void _addLog(String message) {
    if (mounted) {
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
    devLog('BLE測試', message);
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('藍牙 SDK 測試'),
          backgroundColor: Colors.teal,
        ),
        body: Column(
          children: [
            // 控制區
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.teal[50],
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _connectedDevice == null ? _startScan : null,
                          icon: const Icon(Icons.bluetooth_searching),
                          label: const Text('掃描設備'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _connectedDevice != null ? _disconnect : null,
                          icon: const Icon(Icons.bluetooth_disabled),
                          label: const Text('斷開連線'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
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
                      color: _connectedDevice != null
                          ? Colors.green[100]
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _connectedDevice != null
                              ? '🟢 已連接: ${_connectedDevice!.platformName}'
                              : '⚫ 未連接',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '收到 $_dataCount 筆',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 數據顯示區
            if (_connectedDevice != null) ...[
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
                      '📊 即時數據',
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
                        color:
                            _isWearing ? Colors.green[100] : Colors.red[100],
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
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
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ✅ 獨立的掃描 Dialog Widget ====================

class _ScanDialog extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceSelected;
  final VoidCallback onCancel;

  const _ScanDialog({
    required this.onDeviceSelected,
    required this.onCancel,
  });

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
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

    // ✅ 訂閱掃描結果
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });
      }
    });

    // ✅ 開始掃描
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    ).then((_) {
      if (mounted) {
        setState(() => _isScanning = false);
      }
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
          const Text('藍牙設備'),
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
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getSignalColor(result.rssi),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${result.rssi} dBm',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onTap: () {
                      widget.onDeviceSelected(result.device);
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

  Color _getSignalColor(int rssi) {
    if (rssi > -60) return Colors.green;
    if (rssi > -80) return Colors.orange;
    return Colors.red;
  }
}
