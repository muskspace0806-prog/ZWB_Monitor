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

CocoaPods installs `Qiniu` automatically for automatic alert report uploads. If `qiniuUpload` is not configured, no Qiniu upload is performed.

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

By default, the SDK injects `URLSessionConfiguration.default` and `.ephemeral` at runtime to cover:

- `URLSession.shared`
- Custom `URLSession(configuration: .default)`
- Alamofire default `Session`
- Moya providers based on Alamofire

You usually do not need to add code at every API call site. Start the SDK as early as possible:

```swift
ZWBMonitor.start(config: .default)
```

If your app uses a special custom `URLSessionConfiguration`, or if `enableNetworkURLProtocol` is disabled, wrap the configuration manually:

```swift
let configuration = ZWBMonitor.makeMonitoredURLSessionConfiguration(.default)
let session = URLSession(configuration: configuration)
```

The SDK records URL, method, status code, duration, request size, response size, and error message.

Note: sessions created before SDK startup cannot be modified retroactively. Start the SDK before initializing your network layer whenever possible.

## Traffic Grouping

By default, if no rules are configured, all captured HTTP traffic is grouped into a single bucket: `All Traffic`.

To split API traffic, resource downloads, Qiniu uploads, or other domains, configure host rules:

```swift
let config = ZWBMonitorConfig(
    trafficRules: [
        ZWBMonitorTrafficRule(
            name: "Business API",
            hosts: ["123.com", "api.123.com"],
            category: .api
        ),
        ZWBMonitorTrafficRule(
            name: "Qiniu Resource Download",
            hosts: ["456.com", "cdn.456.com"],
            category: .resource
        ),
        ZWBMonitorTrafficRule(
            name: "Qiniu File Upload",
            hosts: ["upload.qiniup.com", "up.qiniup.com"],
            category: .qiniu
        )
    ]
)

ZWBMonitor.start(config: config)
```

The SDK matches each request by URL host and tracks:

- Upload bytes
- Download bytes
- Request count
- Failure count
- Recent request records

If no rule matches, traffic goes into `Unclassified Traffic`.

### Qiniu Upload

Qiniu SDKs may hide their internal network stack, so automatic interception may not fully capture multipart upload, retry behavior, or real file size. For accurate upload traffic, record it in the Qiniu upload callback.

Uploads are tracked as one unified file upload type. The SDK does not require you to split image, audio, video, or document uploads. For diagnostics, the more useful fields are scene, bytes, duration, and success/failure.

```swift
let start = Date()

uploadManager.put(data, key: key, token: token, complete: { info, key, resp in
    ZWBMonitor.recordQiniuUpload(
        scene: "chat_attachment",
        data: data,
        startedAt: start,
        success: info?.isOK == true,
        error: info?.error?.localizedDescription
    )
}, option: option)
```

For local file uploads:

```swift
let start = Date()

uploadManager.putFile(fileURL.path, key: key, token: token, complete: { info, key, resp in
    ZWBMonitor.recordQiniuUpload(
        scene: "chat_attachment",
        fileURL: fileURL,
        startedAt: start,
        success: info?.isOK == true,
        error: info?.error?.localizedDescription
    )
}, option: option)
```

If you already know the upload size, pass bytes directly:

```swift
ZWBMonitor.recordQiniuUpload(
    scene: "chat_attachment",
    bytes: fileSize,
    duration: uploadDuration,
    success: true
)
```

`scene` is a business label, not a Qiniu parameter. It helps the dashboard group and diagnose uploads, for example:

- `chat_attachment`: chat attachment upload
- `avatar_upload`: avatar upload
- `feedback_file`: feedback file upload
- `moment_media`: post media upload

Parameter reference:

| Parameter | Meaning | Required |
| --- | --- | --- |
| `scene` | Business scene label for dashboard grouping | No |
| `data` / `fileURL` / `bytes` | Choose one; the SDK uses it to calculate upload bytes | Yes |
| `startedAt` / `duration` | Upload duration; `startedAt` is converted automatically | No |
| `success` | Whether the Qiniu callback succeeded | Yes |
| `error` | Failure reason; omit for success | No |
| `host` | Qiniu upload host, defaults to `upload.qiniup.com` | No |

### Image Loading And Cache Hits

Image loading stats and real network traffic are different metrics:

- Real image download traffic is tracked by the network layer and domain rules.
- Image display success, failure, and business scene are recorded from Kingfisher / SDWebImage callbacks.

The common integration path does not require cache type. Record success or failure when image loading completes.

Kingfisher example:

```swift
imageView.kf.setImage(with: url) { result in
    switch result {
    case .success:
        ZWBMonitor.recordImageLoad(
            url: url,
            scene: "chat_image",
            success: true
        )
    case .failure(let error):
        ZWBMonitor.recordImageLoad(
            url: url,
            scene: "chat_image",
            success: false,
            error: error.localizedDescription
        )
    }
}
```

SDWebImage example:

```swift
imageView.sd_setImage(with: url) { image, error, _, imageURL in
    ZWBMonitor.recordImageLoad(
        url: imageURL ?? url,
        scene: "chat_image",
        success: error == nil,
        error: error?.localizedDescription
    )
}
```

`scene` is a business label, not an image framework parameter. It helps the dashboard group and diagnose image loading, for example:

- `chat_image`: chat image
- `avatar`: avatar
- `feed_image`: feed image
- `banner`: campaign banner

Parameter reference:

| Parameter | Meaning | Required |
| --- | --- | --- |
| `url` | Image URL, useful for locating the resource and host | No |
| `scene` | Business scene label for dashboard grouping | No |
| `success` | Whether image loading succeeded | Yes |
| `error` | Failure reason; omit for success | No |
| `cacheType` | Advanced parameter for memory/disk cache hit breakdown, defaults to `.unknown` | No |

If you need memory cache, disk cache, and real network-load breakdowns, pass `cacheType` explicitly:

```swift
ZWBMonitor.recordImageLoad(
    url: url,
    scene: "chat_image",
    cacheType: .memory,
    success: true
)
```

Add a tiny adapter in your app if needed:

```swift
// Kingfisher
extension CacheType {
    var zwbCacheType: ZWBMonitorResourceCacheType {
        switch self {
        case .memory:
            return .memory
        case .disk:
            return .disk
        case .none:
            return .none
        @unknown default:
            return .unknown
        }
    }
}

// SDWebImage
extension SDImageCacheType {
    var zwbCacheType: ZWBMonitorResourceCacheType {
        switch self {
        case .memory:
            return .memory
        case .disk:
            return .disk
        case .none:
            return .none
        default:
            return .unknown
        }
    }
}
```

### Agora RTC

Agora real-time audio/video traffic is intentionally not handled for now. It usually does not go through normal URLSession requests. If needed later, it should be integrated through Agora SDK stats callbacks.

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

### Automatic Qiniu Report Upload

To upload alert reports to Qiniu automatically when a threshold is triggered, configure `qiniuUpload`. The SDK generates a unique object key for each report. By default it looks like:

```text
monitor-reports/reports/2026-06-23/com.example.demo/high_memory_2026-06-23T10-00-00Z_uuid.json
```

Qiniu upload tokens must be issued by your backend. Do not store Qiniu AK/SK in the client. The built-in HTTP token provider expects your backend to return a JSON object containing `token`:

```swift
let tokenProvider = ZWBMonitorQiniuHTTPTokenProvider(
    endpoint: URL(string: "https://your-domain.com/qiniu/upload-token")!,
    headers: [
        "Authorization": "Bearer token"
    ]
)

let config = ZWBMonitorConfig(
    reportFormats: [.json],
    qiniuUpload: ZWBMonitorQiniuUploadConfig(
        tokenProvider: tokenProvider,
        keyPrefix: "monitor-reports",
        uploadHost: "upload.qiniup.com",
        cdnBaseURL: URL(string: "https://cdn.your-domain.com"),
        indexCallback: ZWBMonitorQiniuIndexCallbackConfig(
            endpoint: URL(string: "https://your-domain.com/monitor/index")!
        )
    )
)

ZWBMonitor.start(config: config)
```

Token endpoint response:

```json
{
  "token": "qiniu-upload-token"
}
```

When `indexCallback` is configured, the SDK calls your backend after Qiniu upload succeeds with the report ID, app metadata, event, level, object key, and CDN URL. Your backend can update `index.json` for the static dashboard.

The report upload itself is also recorded as traffic with category `qiniu` and scene `monitor_report`.

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
