# ZWB_Monitor

**Language: [简体中文](README.md) | English**

ZWB_Monitor is a general-purpose iOS performance monitoring SDK with CocoaPods and Swift Package Manager support. It focuses on performance diagnostics, alert snapshots, custom server upload, optional DingTalk notifications, and a static HTML dashboard.

## Features

- Full monitoring by default, with module-level opt-in/opt-out.
- CPU, memory, FPS, battery, thermal state, network type, disk, page tracking, and event breadcrumbs.
- URLSession request tracing.
- Custom thresholds.
- Automatic `json`, `txt`, and `xml` report generation when thresholds are triggered.
- Upload reports to a custom server directory.
- Pluggable uploader for OSS, S3, private APIs, or custom logging systems.
- Optional DingTalk alert notification.
- Static HTML dashboard grouped by App.
- Demo App that displays the current collected snapshot.

## Installation

### Swift Package Manager

Add this repository in Xcode and use product `ZWBMonitor`.

```text
https://github.com/muskspace0806-prog/ZWB_Monitor.git
```

### CocoaPods

```ruby
pod 'ZWB_Monitor', :git => 'https://github.com/muskspace0806-prog/ZWB_Monitor.git'
```

For local development:

```ruby
pod 'ZWB_Monitor', :path => '../ZWB_Monitor'
```

## Quick Start

Start with all default modules enabled:

```swift
import ZWBMonitor

ZWBMonitor.start(config: .default)
```

Enable selected modules only:

```swift
let config = ZWBMonitorConfig(
    enabledModules: [
        .cpu,
        .memory,
        .fps,
        .battery,
        .thermal,
        .network,
        .disk,
        .page,
        .events
    ]
)

ZWBMonitor.start(config: config)
```

## Custom Thresholds

```swift
let config = ZWBMonitorConfig(
    thresholds: ZWBMonitorThresholds(
        memoryMB: 800,
        cpuPercent: 80,
        cpuDuration: 30,
        fps: 20,
        fpsDuration: 10,
        diskFreeGB: 2,
        socketReconnectCount: 5,
        uploadFailureCount: 10,
        apiFailureCount: 20,
        triggerCooldown: 60
    )
)

ZWBMonitor.start(config: config)
```

Default rules:

| Type | Rule | Level |
| --- | --- | --- |
| Memory | Memory > 800 MB | Warning |
| CPU | CPU > 80% for 30 seconds | Warning |
| FPS | FPS < 20 for 10 seconds | Warning |
| Thermal | serious / critical | Critical |
| Disk | Free space < 2 GB | Warning |
| Socket | Reconnects >= 5 | Warning |
| Upload | Failures >= 10 | Warning |
| API | Failures >= 20 | Warning |

## Business Counters

CPU, memory, FPS, battery, thermal state, disk, network type, and page tracking can be collected automatically.

Socket reconnects, upload failures, and API failures are business-level signals. The SDK cannot infer their semantics automatically, so call these APIs in your business code:

```swift
ZWBMonitor.recordSocketReconnect()
ZWBMonitor.recordUploadFailure()
ZWBMonitor.recordAPIFailure()
```

You can also record breadcrumbs:

```swift
ZWBMonitor.record(
    event: "SendMessage",
    attributes: [
        "type": "text"
    ]
)
```

## Network Monitoring

For URLSession-based requests:

```swift
let configuration = ZWBMonitor.makeMonitoredURLSessionConfiguration(.default)
let session = URLSession(configuration: configuration)
```

The SDK records URL, method, status code, duration, request size, response size, and error message.

## Report Upload

### Default HTTP Uploader

```swift
let config = ZWBMonitorConfig(
    reportFormats: [.json, .txt, .xml],
    upload: ZWBMonitorHTTPUploadConfig(
        endpoint: URL(string: "https://your-domain.com/monitor-upload")!,
        directory: "monitor-reports/reports",
        headers: [
            "Authorization": "Bearer token"
        ]
    )
)

ZWBMonitor.start(config: config)
```

The default uploader sends report content, file name, format, app metadata, event type, and timestamp to your server. Your server can store the file and update `index.json`.

### Custom Uploader

Implement `ZWBMonitorUploading` to upload to your own logging system, object storage, or private API:

```swift
final class MyUploader: ZWBMonitorUploading {
    func upload(
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void
    ) {
        // Upload report.content to your server or object storage.
        completion(.success(ZWBMonitorUploadResult(reportId: snapshot.id)))
    }
}

var config = ZWBMonitorConfig.default
config.customUploader = MyUploader()
ZWBMonitor.start(config: config)
```

## DingTalk Notification

```swift
let config = ZWBMonitorConfig(
    dingTalk: ZWBDingTalkConfig(
        webhook: URL(string: "https://oapi.dingtalk.com/robot/send?access_token=xxx")!,
        secret: nil
    )
)

ZWBMonitor.start(config: config)
```

If your DingTalk bot requires a signature, pass the `secret` value.

## HTML Dashboard

`Dashboard/` is the static dashboard template. `html/` is a local preview directory with mock data.

Recommended server structure:

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

Dashboard flow:

```text
Load index.json
↓
Get report list
↓
Load reports/*.json
↓
Group by App
↓
Click an App to inspect report list and detail
```

Local preview:

```bash
cd html
python3 -m http.server 8097 --bind 127.0.0.1
```

Open:

```text
http://127.0.0.1:8097/index.html
```

## Demo App

The repository includes a UIKit demo:

- Starts the SDK on launch.
- Tap "Refresh Snapshot" to inspect current collected data.
- Tap "Record Event" to simulate breadcrumb recording.

## Structure

```text
ZWB_Monitor
├── Package.swift
├── ZWB_Monitor.podspec
├── README.md
├── README.en.md
├── Dashboard/
├── html/
└── ZWB_Monitor/
    ├── ZWBMonitorSDK/
    ├── AppDelegate.swift
    └── ViewController.swift
```

## Design Principles

- Keep the SDK generic and independent from any business project.
- Use protocols for upload and notification integrations.
- Prefer low-intrusion integration by default.
- Keep report field names stable in English; localize only presentation layers.
