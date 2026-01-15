package com.example.foreground_demo_pjo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        println("[MainActivity] ✅ 主 FlutterEngine 已配置,Plugin 已註冊")
    }
}