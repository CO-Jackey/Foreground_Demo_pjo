package com.example.foreground_demo_pjo

import com.itri.multible.itriuwbhr32hz.HealthCalculate

/**
 * ✅ 全局 SDK 管理器
 * 讓主執行緒和背景執行緒都能存取同一組 SDK 實例
 */
object SdkManager {
    
    // ✅ 使用 object (單例) 確保全 APP 共用
    private val healthCalculators = mutableMapOf<String, HealthCalculate>()
    private val sdkLocks = mutableMapOf<String, Any>()
    
    /**
     * 取得或建立 SDK 實例
     */
    @JvmStatic
    fun getOrCreateCalculator(deviceId: String, type: Int = 3): HealthCalculate {
        synchronized(healthCalculators) {
            return healthCalculators.getOrPut(deviceId) {
                println("[SdkManager] 🆕 為設備 $deviceId 建立新的 HealthCalculate 實例")
                HealthCalculate(type)
            }
        }
    }
    
    /**
     * 取得設備專用的鎖
     */
    @JvmStatic
    fun getSdkLock(deviceId: String): Any {
        synchronized(sdkLocks) {
            return sdkLocks.getOrPut(deviceId) { Any() }
        }
    }
    
    /**
     * 處理數據包
     */
    @JvmStatic
    fun processSplitPackage(
        deviceId: String,
        data: ByteArray,
        type: Int = 3
    ): HashMap<String, Any> {
        // 參數驗證
        if (data.isEmpty()) {
            throw IllegalArgumentException("Received empty data array")
        }
        
        if (data.size < 17) {
            throw IllegalArgumentException(
                "Data length ${data.size} is less than required 17 bytes"
            )
        }
        
        val lock = getSdkLock(deviceId)
        val calculator = getOrCreateCalculator(deviceId, type)
        
        val startTime = System.currentTimeMillis()
        
        // ✅ 同步執行 splitPackage
        val splitResult: Int = synchronized(lock) {
            calculator.splitPackage(data)
        }
        
        val elapsedTime = System.currentTimeMillis() - startTime
        
        // 收集結果
        val healthData = HashMap<String, Any>()
        healthData["deviceId"] = deviceId
        healthData["processingTime"] = elapsedTime
        healthData["splitResult"] = splitResult
        
        // 從該設備專屬的 calculator 取得數據
        healthData["BRFiltered"] = calculator.getBRFiltered().map { it.toDouble() }
        healthData["BRValue"] = calculator.getBRValue()
        healthData["FFTOut"] = calculator.getFFTOut().map { it.toDouble() }
        healthData["GyroValueX"] = calculator.getGyroValueX()
        healthData["GyroValueY"] = calculator.getGyroValueY()
        healthData["GyroValueZ"] = calculator.getGyroValueZ()
        healthData["HRFiltered"] = calculator.getHRFiltered().map { it.toDouble() }
        healthData["HRValue"] = calculator.getHRValue()
        healthData["HumValue"] = calculator.getHumValue()
        healthData["IsWearing"] = calculator.getIsWearing()
        healthData["PetPoseValue"] = calculator.getPetPoseValue()
        healthData["PowerValue"] = calculator.getPowerValue()
        healthData["RawData"] = calculator.getRawData().map { it.toInt() }
        healthData["StepValue"] = calculator.getStepValue()
        healthData["TempValue"] = calculator.getTempValue()
        healthData["TimeStamp"] = calculator.getTimeStamp()
        healthData["Type"] = calculator.getType()
        
        println("[SdkManager] ✅ 設備 $deviceId 處理完成 (${elapsedTime}ms)")
        
        return healthData
    }
    
    /**
     * 清理特定設備
     */
    @JvmStatic
    fun disposeDevice(deviceId: String) {
        synchronized(healthCalculators) {
            healthCalculators.remove(deviceId)
            println("[SdkManager] 🗑️ 已清理設備 $deviceId")
        }
        synchronized(sdkLocks) {
            sdkLocks.remove(deviceId)
        }
    }
    
    /**
     * 清理所有設備
     */
    @JvmStatic
    fun disposeAll() {
        synchronized(healthCalculators) {
            healthCalculators.clear()
            println("[SdkManager] 🗑️ 已清理所有實例")
        }
        synchronized(sdkLocks) {
            sdkLocks.clear()
        }
    }
    
    /**
     * 取得狀態
     */
    @JvmStatic
    fun getStatus(deviceId: String? = null): HashMap<String, Any> {
        val status = HashMap<String, Any>()
        
        synchronized(healthCalculators) {
            if (deviceId != null) {
                status["hasInstance"] = healthCalculators.containsKey(deviceId)
                status["deviceId"] = deviceId
            } else {
                status["totalInstances"] = healthCalculators.size
                status["deviceIds"] = healthCalculators.keys.toList()
            }
        }
        
        return status
    }
}