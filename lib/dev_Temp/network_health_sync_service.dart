import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:foreground_demo_pjo/helper/devLog.dart';
import 'package:http/http.dart' as http;


/// 網路健康數據同步服務
///
/// 職責：
/// 1. 透過 API 輪詢取得 MQTT 原始數據 (GET)
/// 2. 解析數據並透過 SDK 處理
/// 3. 將處理後的健康數據上傳至後端 (POST)
class NetworkHealthSyncService {
  final Ref _ref;
  Timer? _timer;
  bool _isPolling = false;

  // String get _baseUrl => _ref.read(appConfigProvider).apiBaseUrl;
  String get _baseUrl => 'http://172.24.101.88:9998';

  Duration get _pollInterval {
    final seconds = _ref.read(appConfigProvider).rawSyncInterval;
    return Duration(seconds: seconds);
  }

  NetworkHealthSyncService(this._ref) {
    start();
  }

  /// 開始同步
  void start() {
    if (_isPolling) return;
    _isPolling = true;
    devLog(
      'NetworkHealthSyncService',
      'Starting network sync with interval: ${_pollInterval.inSeconds}s',
    );

    // 立即執行一次
    _fetchAndProcessData();

    // 啟動定時器
    _timer = Timer.periodic(_pollInterval, (_) => _fetchAndProcessData());
  }

  /// 停止同步
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isPolling = false;
    devLog('NetworkHealthSyncService', 'Stopped network sync');
  }

  /// 銷毀資源
  void dispose() {
    stop();
  }

  /// 1. 取得 MQTT 訊息
  Future<void> _fetchAndProcessData() async {
    try {
      final url = '$_baseUrl/api/ipetdata/mqtt-message';
      // devLog('NetworkHealthSyncService', 'Fetching from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['Success'] == true && json['Data'] != null) {
          await _processMqttData(json['Data']);
        } else {
          // devLog('NetworkHealthSyncService', 'API returned success=false or no data');
        }
      } else {
        devLog(
          'NetworkHealthSyncService',
          'API Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      devLog('NetworkHealthSyncService', 'Fetch Error: $e');
    }
  }

  /// 2. 解析 MQTT 數據
  Future<void> _processMqttData(Map<String, dynamic> data) async {
    try {
      var packetStr = data['packet'] as String?;
      if (packetStr == null) return;

      // 嘗試修復無效的 JSON 格式 (針對 data 欄位沒有引號的問題)
      // 範例: "data":ff967a... -> "data":"ff967a..."
      // 這是因為 API 回傳的 JSON 字串中，data 的值可能沒有被引號包圍
      packetStr = packetStr.replaceAllMapped(
        RegExp(r'"data":([a-fA-F0-9]+)'),
        (match) => '"data":"${match.group(1)}"',
      );

      // packet 欄位是一個 JSON 字串，需要再次解析
      final packetJson = jsonDecode(packetStr);
      final innerPackets = packetJson['packet'] as List<dynamic>?;

      if (innerPackets == null) return;

      for (final item in innerPackets) {
        final hexData = item['data'] as String?;
        if (hexData != null) {
          devLog('NetworkHealthSyncService', 'hexData: $hexData');
          final rawBytes = _hexToBytes(hexData);
          devLog('NetworkHealthSyncService', 'rawBytes: $rawBytes');
          await _processRawData(rawBytes);
        }
      }
    } catch (e) {
      devLog('NetworkHealthSyncService', 'Parse Error: $e');
    }
  }

  /// Hex String 轉 Uint8List
  Uint8List _hexToBytes(String hex) {
    var result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      var num = hex.substring(i, i + 2);
      var byte = int.parse(num, radix: 16);
      result[i ~/ 2] = byte;
    }
    return result;
  }

  /// 3. 透過 SDK 處理原始數據
  Future<void> _processRawData(Uint8List rawData) async {
    // 檢查 SDK 是否已初始化
    final sdkInitialized =
        _ref.read(sdkInitializationProvider).valueOrNull ?? false;
    if (!sdkInitialized) {
      // devLog('NetworkHealthSyncService', 'SDK not initialized, skipping');
      return;
    }

    final useCase = _ref.read(processSensorDataUseCaseProvider);
    final pet = _ref.read(selectedPetProvider).valueOrNull;
    final processingPetId = pet?.id;

    final result = await useCase.execute(rawData, pet: pet);

    // 再次檢查當前寵物是否與處理開始時一致
    final currentPet = _ref.read(selectedPetProvider).valueOrNull;
    if (currentPet?.id != processingPetId) {
      // devLog('NetworkHealthSyncService', 'Pet changed during processing, skipping');
      return;
    }

    result.when(
      success: (data) async {
        // 更新本地 UI
        _ref.read(healthDataControllerProvider.notifier).updateData(data);

        // 4. 上傳健康數據
        await _uploadHealthData(data);
      },
      failure: (error) {
        // devLog('NetworkHealthSyncService', 'Process Error: $error');
      },
    );
  }

  /// 4. 上傳健康數據
  Future<void> _uploadHealthData(SensorDataEntity data) async {
    final user = _ref.read(authProvider).valueOrNull;
    final pet = _ref.read(selectedPetProvider).valueOrNull;

    if (user == null || pet == null) {
      // devLog('NetworkHealthSyncService', 'Upload skipped: User or Pet is null');
      return;
    }

    // 根據 API 規格建構 Payload
    final payload = {
      "DeviceID": "iPet", // 固定或從設定讀取
      "Account_ID": user.accountId,
      "Pet_ID": pet.id,
      "Battery": data.batteryLevel,
      "envHumidity": data.humidity,
      "envTemp": data.temperature.toInt(),
      "sensorTemp": data.temperature.toInt(),
      "heartRate": data.heartRate,
      "heartRateMax": 0, // 目前 Entity 無此欄位
      "heartRateMin": 0, // 目前 Entity 無此欄位
      "breathRate": data.breathRate,
      "breathRateMax": 0, // 目前 Entity 無此欄位
      "breathRateMin": 0, // 目前 Entity 無此欄位
      "rri": 0, // 目前 Entity 無此欄位
      "step": data.stepCount,
    };

    try {
      final url = '$_baseUrl/api/ipetdata/health-data';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        devLog(
          'NetworkHealthSyncService',
          'Upload Failed: ${response.statusCode} - ${response.body}',
        );
      } else {
        // devLog('NetworkHealthSyncService', 'Upload Success');
      }
    } catch (e) {
      devLog('NetworkHealthSyncService', 'Upload Error: $e');
    }
  }
}

final networkHealthSyncServiceProvider = Provider<NetworkHealthSyncService>((
  ref,
) {
  final service = NetworkHealthSyncService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
