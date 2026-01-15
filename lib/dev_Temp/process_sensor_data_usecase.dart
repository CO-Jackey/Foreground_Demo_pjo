// lib/features/bluetooth/domain/usecases/process_sensor_data_usecase.dart

import 'dart:typed_data';

import '../../../../core/utils/dev_log.dart';
import '../../../pets/domain/entities/pet.dart';
import '../entities/sensor_data_entity.dart';
import '../repositories/health_records_repository.dart';
import 'result.dart';

/// 處理感測器數據 UseCase
///
/// 職責：執行處理感測器數據的業務流程
///
/// 流程：
/// 1. 驗證數據有效性
/// 2. 透過 SDK 處理數據
/// 3. 驗證處理結果
/// 4. 返回感測器實體
class ProcessSensorDataUseCase {
  final HealthRecordsRepository _repository;

  ProcessSensorDataUseCase(this._repository);

  /// 執行處理感測器數據
  ///
  /// 參數：
  /// - rawData: 原始藍牙數據
  /// - pet: 當前寵物（用於計算情緒等）
  ///
  /// 返回：
  /// - Success: 處理後的感測器數據
  /// - Failure: 處理失敗，包含錯誤訊息
  Future<Result<SensorDataEntity>> execute(
    Uint8List rawData, {
    Pet? pet,
  }) async {
    try {
      // 1. 驗證數據長度
      if (rawData.isEmpty) {
        return const Result.failure('數據為空');
      }

      // if (rawData.length < 17) {
      //   devLog(
      //     'ProcessSensorDataUseCase',
      //     '⚠️ 數據長度不足: ${rawData.length} < 17',
      //   );
      //   return Result.failure('數據長度不足: ${rawData.length}');
      // }

      // 2. 透過 Repository 處理數據（呼叫 SDK）
      final sensorData = await _repository.processSensorData(rawData, pet: pet);

      devLog('sensorData資料', sensorData.toString());

      // 3. 驗證處理結果
      // SDK 可能返回 -1 表示尚未就緒或數據不完整
      if (sensorData.heartRate < 0 && sensorData.breathRate < 0) {
        devLog('ProcessSensorDataUseCase', '⚠️ SDK 尚未就緒或數據不完整');
        return const Result.failure('SDK 尚未就緒');
      }

      // 4. 驗證數據合理性（可選）
      if (sensorData.heartRate > 300 || sensorData.breathRate > 100) {
        devLog(
          'ProcessSensorDataUseCase',
          '⚠️ 數據異常: HR=${sensorData.heartRate}, BR=${sensorData.breathRate}',
        );
        // 註：這裡選擇返回數據而不是失敗，因為可能是真實的異常情況
        // 如果要嚴格驗證，可以改為 return Result.failure('數據異常');
      }

      // devLog(
      //   'ProcessSensorDataUseCase',
      //   '✅ 數據處理成功: HR=${sensorData.heartRate}, BR=${sensorData.breathRate}',
      // );

      return Result.success(sensorData);
    } catch (e) {
      devLog('ProcessSensorDataUseCase', '❌ 處理數據失敗: $e');
      return Result.failure('處理數據失敗: $e');
    }
  }
}
