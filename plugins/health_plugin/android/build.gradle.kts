// 檔案位置: plugins/health_plugin/android/build.gradle.kts

group = "com.example.health_plugin"
version = "1.0-SNAPSHOT"

plugins {
    // 使用 Android Library 插件 (因為這是 Plugin，不是 Application)
    id("com.android.library")
    // 使用 Kotlin Android 插件
    id("org.jetbrains.kotlin.android")
}

android {
    // 🔥 重要：新版 Gradle 強制要求 namespace，請對應你的 plugin package
    namespace = "com.example.health_plugin"
    
    // SDK 版本設定 (建議跟隨主專案或設為常用的版本)
    compileSdk = 34 

    defaultConfig {
        minSdk = 21 // Flutter 預設通常是 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }
}

dependencies {
    // 引入標準 Kotlin 庫
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:1.8.0"))
    
    // 🔥 關鍵：引入 libs 資料夾底下的所有 .jar 檔案
    // 這樣你的 SdkManager.kt 才能讀取到那個 .jar 裡面的 class
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    
    // 這裡不需要加 flutter embedding 的依賴，
    // 因為 Flutter 在編譯時會自動把這個 library 掛載到環境中
}