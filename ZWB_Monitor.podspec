Pod::Spec.new do |s|
  s.name             = 'ZWB_Monitor'
  s.version          = '0.1.0'
  s.summary          = 'A lightweight iOS performance monitor SDK with snapshots, upload hooks, DingTalk alerts, and a static dashboard.'
  s.description      = <<-DESC
ZWB_Monitor is a general purpose iOS performance monitoring SDK. It can collect app runtime metrics,
device state, page transitions, network traces, event breadcrumbs, and generate JSON/TXT/XML snapshots
when custom thresholds are triggered.
  DESC
  s.homepage         = 'https://github.com/muskspace0806-prog/ZWB_Monitor'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ZWB' => 'zwb@example.com' }
  s.source           = { :git => 'https://github.com/muskspace0806-prog/ZWB_Monitor.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.swift_version    = '5.0'
  s.source_files     = 'ZWB_Monitor/ZWBMonitorSDK/**/*.swift'
  s.frameworks       = 'UIKit', 'Foundation', 'Network', 'CryptoKit'
  s.dependency       'Qiniu'
end
