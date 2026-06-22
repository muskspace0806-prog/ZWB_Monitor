# ZWB_Monitor

ZWB_Monitor is a general iOS performance monitoring SDK. It is designed for low-intrusion integration, default full monitoring, custom thresholds, snapshot reports, custom server upload, optional DingTalk alerts, and a static HTML dashboard.

## Install

### Swift Package Manager

Add this repository as a package dependency and use product `ZWBMonitor`.

### CocoaPods

```ruby
pod 'ZWB_Monitor', :path => '../ZWB_Monitor'
```

## Quick Start

```swift
import ZWBMonitor

ZWBMonitor.start(config: .default)
```

Custom modules and thresholds:

```swift
let config = ZWBMonitorConfig(
    enabledModules: [.cpu, .memory, .fps, .battery, .thermal, .network, .disk, .page, .events],
    thresholds: ZWBMonitorThresholds(
        memoryMB: 800,
        cpuPercent: 80,
        cpuDuration: 30,
        fps: 20,
        fpsDuration: 10,
        diskFreeGB: 2,
        socketReconnectCount: 5,
        uploadFailureCount: 10,
        apiFailureCount: 20
    ),
    upload: ZWBMonitorHTTPUploadConfig(
        endpoint: URL(string: "https://your-domain.com/monitor-upload")!,
        directory: "monitor-reports/reports",
        headers: ["Authorization": "Bearer token"]
    ),
    dingTalk: ZWBDingTalkConfig(
        webhook: URL(string: "https://oapi.dingtalk.com/robot/send?access_token=xxx")!,
        secret: nil
    )
)

ZWBMonitor.start(config: config)
```

## Custom Upload

```swift
final class MyUploader: ZWBMonitorUploading {
    func upload(report: ZWBMonitorReportFile, snapshot: ZWBMonitorSnapshot, completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void) {
        // Upload report.content to your own server or object storage.
    }
}

var config = ZWBMonitorConfig.default
config.customUploader = MyUploader()
ZWBMonitor.start(config: config)
```

## Network Monitoring

For URLSession-based requests, use the monitored configuration:

```swift
let configuration = ZWBMonitor.makeMonitoredURLSessionConfiguration(.default)
let session = URLSession(configuration: configuration)
```

## Dashboard

Deploy `Dashboard/` to your server. The page fetches `index.json`, then loads each report file listed in it.

Expected structure:

```text
monitor-reports/
├── index.json
├── reports/
│   └── 2026-06-22/high_memory_xxx.json
└── dashboard/
    ├── index.html
    ├── app.js
    └── style.css
```

