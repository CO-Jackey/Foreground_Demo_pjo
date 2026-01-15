import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/dev_log.dart';
import '../../bluetooth/export.dart';
import '../domain/entities/sensor_data_entity.dart';
import '../presentation/providers/health_data_controller.dart';
import '../presentation/providers/health_records_providers.dart';
import '../presentation/providers/sdk_initialization_provider.dart';
import '../../pets/presentation/providers/selected_pet_provider.dart';

/// 藍牙轉網路健康數據同步服務
///
/// 職責：
/// 1. 監聽藍牙原始數據並上傳至 Server
/// 2. 定期從 Server 拉取原始數據
/// 3. 呼叫 SDK 進行計算
/// 4. 更新 HealthDataController 並將處理後的數據回傳 Server
class BluetoothToNetworkHealthSyncService {
  final Ref _ref;
  Timer? _pollingTimer;
  bool _isProcessing = false;

  BluetoothToNetworkHealthSyncService(this._ref) {
    _initialize();
  }

  void _initialize() {
    devLog('BluetoothToNetworkHealthSyncService', '初始化服務');

    // 1. 監聽藍牙狀態與數據，並上傳
    _ref.listen<Uint8List?>(bluetoothDataStreamProvider, (
      previous,
      next,
    ) async {
      if (next == null) return;
      await _uploadRawData(next);
    });

    // 2. 啟動定期拉取
    final config = _ref.read(appConfigProvider);
    final interval = config.rawSyncInterval;

    devLog('BluetoothToNetworkHealthSyncService', '啟動定期拉取，間隔: $interval 秒');

    _pollingTimer = Timer.periodic(Duration(seconds: interval), (_) {
      _fetchAndProcessRawData();
    });
  }

  /// 上傳原始數據到 Server
  Future<void> _uploadRawData(Uint8List data) async {
    try {
      final config = _ref.read(appConfigProvider);
      final url = Uri.parse('${config.apiBaseUrl}/api/health/raw-data');

      // 獲取當前連接的裝置 MAC 與 寵物 ID
      final bleState = _ref.read(bluetoothControllerProvider);
      String? deviceMac;
      if (bleState is Connected) {
        deviceMac = bleState.device.remoteId.str;
      }

      final pet = _ref.read(selectedPetProvider).valueOrNull;
      // 優先使用 serverId
      final petId = pet?.serverId ?? pet?.id?.toString();

      if (deviceMac == null || petId == null) {
        devLog(
          'BluetoothToNetworkHealthSyncService',
          '缺少裝置 MAC 或 寵物 ID，無法上傳原始數據',
        );
        return;
      }

      // 轉換為 Base64 字串傳輸
      final base64Data = base64Encode(data);

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rawData': base64Data,
          'timestamp': DateTime.now().toIso8601String(),
          'deviceMac': deviceMac,
          'petId': petId,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        devLog(
          'BluetoothToNetworkHealthSyncService',
          '上傳原始數據失敗: ${response.statusCode}',
        );
      }
    } catch (e) {
      devLog('BluetoothToNetworkHealthSyncService', '上傳原始數據錯誤: $e');
    }
  }

  /// 從 Server 拉取原始數據並處理
  Future<void> _fetchAndProcessRawData() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final config = _ref.read(appConfigProvider);

      // 獲取當前連接的裝置 MAC 與 寵物 ID
      final bleState = _ref.read(bluetoothControllerProvider);
      String? deviceMac;
      if (bleState is Connected) {
        deviceMac = bleState.device.remoteId.str;
      }

      final pet = _ref.read(selectedPetProvider).valueOrNull;
      // 優先使用 serverId (MongoDB ObjectId)，若無則使用本地 id (但這在多裝置下會有問題)
      final petId = pet?.serverId ?? pet?.id?.toString();

      if (deviceMac == null || petId == null) {
        devLog(
          'BluetoothToNetworkHealthSyncService',
          '缺少裝置 MAC ($deviceMac) 或 寵物 ID ($petId)，無法拉取數據',
        );
        return;
      }

      if (pet?.serverId == null) {
        devLog(
          'BluetoothToNetworkHealthSyncService',
          '警告: 此寵物尚未同步至伺服器 (serverId 為空)，使用本地 ID: $petId 可能導致數據混淆',
        );
      }

      final url = Uri.parse('${config.apiBaseUrl}/api/health/raw-data').replace(
        queryParameters: {
          'deviceMac': deviceMac,
          'petId': petId,
        },
      );

      // devLog('BluetoothToNetworkHealthSyncService', '正在拉取原始數據: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['rawData'] != null) {
          devLog('BluetoothToNetworkHealthSyncService', '成功拉取原始數據，準備處理');
          final String base64Data = json['rawData'];
          final rawData = base64Decode(base64Data);

          await _processData(rawData);
        } else {
          // devLog('BluetoothToNetworkHealthSyncService', '無新數據');
        }
      } else {
        devLog(
          'BluetoothToNetworkHealthSyncService',
          '拉取原始數據失敗: ${response.statusCode}',
        );
      }
    } catch (e) {
      devLog('BluetoothToNetworkHealthSyncService', '拉取原始數據錯誤: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// 處理數據 (使用 SDK)
  Future<void> _processData(Uint8List rawData) async {
    // 檢查 SDK 是否已初始化
    final sdkInitialized =
        _ref.read(sdkInitializationProvider).valueOrNull ?? false;

    if (!sdkInitialized) {
      devLog('BluetoothToNetworkHealthSyncService', 'SDK 未初始化，無法處理數據');
      return;
    }

    try {
      final useCase = _ref.read(processSensorDataUseCaseProvider);
      final pet = _ref.read(selectedPetProvider).valueOrNull;

      devLog('BluetoothToNetworkHealthSyncService', '開始處理數據，寵物: ${pet?.name}');

      // 記錄開始處理時的寵物 ID
      final processingPetId = pet?.id;

      final result = await useCase.execute(rawData, pet: pet);

      // 再次檢查當前寵物是否與處理開始時一致
      final currentPet = _ref.read(selectedPetProvider).valueOrNull;
      if (currentPet?.id != processingPetId) {
        devLog('BluetoothToNetworkHealthSyncService', '寵物已切換，丟棄舊數據');
        return;
      }

      result.when(
        success: (data) async {
          devLog(
            'BluetoothToNetworkHealthSyncService',
            'SDK 處理成功: HR=${data.heartRate}, BR=${data.breathRate}',
          );
          // 1. 更新本地 UI 與資料庫
          _ref.read(healthDataControllerProvider.notifier).updateData(data);

          // 2. 上傳處理後的數據回 Server
          await _uploadProcessedData(data);
        },
        failure: (error) {
          devLog('BluetoothToNetworkHealthSyncService', 'SDK 處理失敗: $error');
        },
      );
    } catch (e) {
      devLog('BluetoothToNetworkHealthSyncService', '處理數據時出錯: $e');
    }
  }

  /// 上傳處理後的數據到 Server
  Future<void> _uploadProcessedData(SensorDataEntity data) async {
    try {
      final config = _ref.read(appConfigProvider);
      final url = Uri.parse('${config.apiBaseUrl}/api/health/processed-data');

      // 獲取當前連接的裝置 MAC 與 寵物 ID
      final bleState = _ref.read(bluetoothControllerProvider);
      String? deviceMac;
      if (bleState is Connected) {
        deviceMac = bleState.device.remoteId.str;
      }

      final pet = _ref.read(selectedPetProvider).valueOrNull;
      final petId = pet?.serverId ?? pet?.id?.toString();

      if (deviceMac == null || petId == null) {
        devLog(
          'BluetoothToNetworkHealthSyncService',
          '缺少裝置 MAC 或 寵物 ID，無法上傳處理後數據',
        );
        return;
      }

      final body = {
        'heartRate': data.heartRate,
        'breathRate': data.breathRate,
        'stepCount': data.stepCount,
        'temperature': data.temperature,
        'humidity': data.humidity,
        'batteryLevel': data.batteryLevel,
        'isWearing': data.isWearing,
        'petPose': data.petPose?.name,
        'petMood': data.petMood?.name,
        'timestamp': data.timestamp.toIso8601String(),
        'deviceMac': deviceMac,
        'petId': petId,
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        devLog(
          'BluetoothToNetworkHealthSyncService',
          '上傳處理後數據失敗: ${response.statusCode}',
        );
      }
    } catch (e) {
      devLog('BluetoothToNetworkHealthSyncService', '上傳處理後數據錯誤: $e');
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
  }
}

final bluetoothToNetworkHealthSyncServiceProvider =
    Provider<BluetoothToNetworkHealthSyncService>(
      (ref) {
        final service = BluetoothToNetworkHealthSyncService(ref);
        ref.onDispose(() => service.dispose());
        return service;
      },
    );
