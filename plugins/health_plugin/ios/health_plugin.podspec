Pod::Spec.new do |s|
  s.name             = 'health_plugin'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin.'
  s.description      = 'Health SDK Plugin'
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # 🔥 Framework 在 plugin 目錄內的 Frameworks 資料夾
  # 相對於這個 .podspec 檔案的位置：Frameworks/ITRIHRBR.framework
  s.vendored_frameworks = 'plugins/health_plugin/ios/Frameworks/ITRIHRBR.framework'
  
  # 🔥 設定 Framework 搜尋路徑（相對於 podspec 所在位置）
  s.xcconfig = {
    'FRAMEWORK_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Frameworks"'
  }
  
  # 確保資源被包含
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-framework ITRIHRBR'
  }
  s.swift_version = '5.0'
end