package com.example.health_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * ✅ 簡化的 Plugin - 只負責轉發呼叫到 SdkManager
 */
class HealthCalculatePlugin : FlutterPlugin {
    
    companion object {
        private const val CHANNEL = "com.example.foreground_demo_pjo/health_calculate"
    }
    
    private var channel: MethodChannel? = null
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val engineId = System.identityHashCode(binding.flutterEngine)
        val threadName = Thread.currentThread().name
        
        println("[HealthCalculatePlugin] ⭐ Plugin 附加到引擎 #$engineId")
        println("[HealthCalculatePlugin] 🧵 執行緒: $threadName")
        
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
        
        println("[HealthCalculatePlugin] ✅ MethodChannel 已註冊完成")
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        println("[HealthCalculatePlugin] 🛑 Plugin 從引擎分離")
        
        channel?.setMethodCallHandler(null)
        channel = null
    }
    
    private fun handleMethodCall(
        call: io.flutter.plugin.common.MethodCall,
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        val threadName = Thread.currentThread().name
        println("[HealthCalculatePlugin] ⭐ 收到方法呼叫: ${call.method} (執行緒: $threadName)")
        
        try {
            when (call.method) {
                "initialize" -> {
                    val type: Int? = call.argument("type")
                    if (type != null) {
                        println("[HealthCalculatePlugin] ✅ Initialize with type: $type")
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Type is required.", null)
                    }
                }
                
                "splitPackage" -> {
                    val data = call.argument<ByteArray>("data")
                    val deviceId = call.argument<String>("deviceId")
                    
                    if (data == null) {
                        result.error("INVALID_ARGUMENT", "Data is required.", null)
                        return
                    }
                    
                    if (deviceId == null) {
                        result.error("INVALID_ARGUMENT", "DeviceId is required.", null)
                        return
                    }
                    
                    // ✅ 呼叫 SdkManager 處理
                    val healthData = SdkManager.processSplitPackage(deviceId, data)
                    result.success(healthData)
                }
                
                "getStatus" -> {
                    val deviceId: String? = call.argument("deviceId")
                    val status = SdkManager.getStatus(deviceId)
                    result.success(status)
                }
                
                "dispose" -> {
                    val deviceId: String? = call.argument("deviceId")
                    
                    if (deviceId != null) {
                        SdkManager.disposeDevice(deviceId)
                    } else {
                        SdkManager.disposeAll()
                    }
                    
                    result.success(null)
                }
                
                else -> {
                    println("[HealthCalculatePlugin] ❌ 未知方法: ${call.method}")
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            println("[HealthCalculatePlugin] ❌ 錯誤: ${e.message}")
            e.printStackTrace()
            result.error("SDK_ERROR", e.message, null)
        }
    }
}