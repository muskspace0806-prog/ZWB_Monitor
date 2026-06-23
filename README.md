# ZWB_Monitor

**语言：简体中文 | [English](README.en.md)**

ZWB_Monitor 是一个通用 iOS 性能监控 SDK，支持 CocoaPods 和 Swift Package Manager 接入。它适合用于 App 性能异常排查、预警快照生成、服务器上报、钉钉通知，以及静态 HTML 后台查看。

## 能力概览

- 默认全量监控，也可以按需开启部分模块。
- 支持 CPU、内存、FPS、电量、温度、网络类型、磁盘、页面追踪、事件记录。
- 支持 URLSession 网络请求记录。
- 支持自定义阈值。
- 触发阈值后自动生成 `json`、`txt`、`xml` 报告。
- 支持上传到业务方自定义服务器目录。
- 支持自定义上传器，方便接入 OSS、S3、私有 API、日志平台。
- 支持可选钉钉机器人告警。
- 提供静态 HTML 后台，可按 App 聚合查看告警。
- Demo App 内可点击查看当前采集快照。

## 安装

### Swift Package Manager

在 Xcode 中添加本仓库地址，然后选择产品 `ZWBMonitor`。

```text
https://github.com/muskspace0806-prog/ZWB_Monitor.git
```

### CocoaPods

```ruby
pod 'ZWB_Monitor', :git => 'https://github.com/muskspace0806-prog/ZWB_Monitor.git'
```

CocoaPods 接入会自动拉取 `Qiniu`，用于预警报告自动上传七牛。如果你暂时不配置 `qiniuUpload`，不会产生七牛上传行为。

本地调试时也可以使用：

```ruby
pod 'ZWB_Monitor', :path => '../ZWB_Monitor'
```

## 快速开始

默认全量开启：

```swift
import ZWBMonitor

// 最小接入：启动后自动采集 CPU、内存、FPS、网络、页面等默认模块。
// 不配置上传时，只会在本地生成报告，不会主动请求你的服务器。
ZWBMonitor.start(config: .default)
```

按需开启模块：

```swift
let config = ZWBMonitorConfig(
    // 只开启你关心的模块；不传时默认开启全部模块。
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

// 建议在 AppDelegate 或应用启动入口调用一次。
ZWBMonitor.start(config: config)
```

## 自定义阈值

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

当前内置触发规则：

| 类型 | 默认规则 | 等级 |
| --- | --- | --- |
| 内存 | 内存 > 800 MB | 警告 |
| CPU | CPU > 80% 持续 30 秒 | 警告 |
| FPS | FPS < 20 持续 10 秒 | 警告 |
| 温度 | serious / critical | 严重 |
| 磁盘 | 剩余空间 < 2 GB | 警告 |
| Socket | 连续重连 >= 5 次 | 警告 |
| 上传 | 连续上传失败 >= 10 次 | 警告 |
| API | 连续 API 失败 >= 20 次 | 警告 |

## 业务计数器

CPU、内存、FPS、电量、温度、磁盘、网络类型、页面追踪可以自动采集。

Socket 重连、上传失败、API 失败属于业务语义，SDK 无法自动知道你的业务定义，需要在业务代码里手动记录：

```swift
ZWBMonitor.recordSocketReconnect()
ZWBMonitor.recordUploadFailure()
ZWBMonitor.recordAPIFailure()
```

也可以记录普通事件：

```swift
ZWBMonitor.record(
    event: "SendMessage",
    attributes: [
        "type": "text"
    ]
)
```

## 网络监控

如果使用 URLSession，可以使用 SDK 提供的配置生成方法：

```swift
let configuration = ZWBMonitor.makeMonitoredURLSessionConfiguration(.default)
let session = URLSession(configuration: configuration)
```

SDK 会记录请求 URL、Method、状态码、耗时、请求大小、响应大小和错误信息。

## 流量分组统计

默认情况下，如果不配置任何规则，SDK 只会把可捕获的 HTTP 流量归为一个总分组：`All Traffic`，不会按域名拆分。

如果你希望把业务接口、资源下载、七牛上传等流量拆开，可以配置域名规则：

```swift
let config = ZWBMonitorConfig(
    trafficRules: [
        ZWBMonitorTrafficRule(
            name: "业务接口",
            hosts: ["123.com", "api.123.com"],
            category: .api
        ),
        ZWBMonitorTrafficRule(
            name: "七牛资源下载",
            hosts: ["456.com", "cdn.456.com"],
            category: .resource
        ),
        ZWBMonitorTrafficRule(
            name: "七牛文件上传",
            hosts: ["upload.qiniup.com", "up.qiniup.com"],
            category: .qiniu
        )
    ]
)

ZWBMonitor.start(config: config)
```

SDK 会根据请求 URL 的 host 自动匹配规则，并统计：

- 上行流量
- 下载流量
- 请求次数
- 失败次数
- 最近请求记录

如果没有匹配到任何规则，会进入 `Unclassified Traffic`。

### 七牛云上传

七牛云 SDK 可能内部封装网络层，自动拦截不一定能完整捕获分片、重试和真实文件大小。建议在七牛上传回调里手动补充记录。

上传统一按“文件上传”处理，不再区分图片、音频、视频或文档。业务排查时更重要的是：哪个场景上传、上传了多少、耗时多少、是否成功。

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

如果上传的是本地文件：

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

如果你已经自己算好了大小，也可以直接传字节数：

```swift
ZWBMonitor.recordQiniuUpload(
    scene: "chat_attachment",
    bytes: fileSize,
    duration: uploadDuration,
    success: true
)
```

`scene` 是业务场景标识，不是七牛参数。它用于后台聚合和问题排查，例如：

- `chat_attachment`：聊天附件上传
- `avatar_upload`：头像上传
- `feedback_file`：意见反馈文件上传
- `moment_media`：动态媒体上传

参数说明：

| 参数 | 含义 | 是否必填 |
| --- | --- | --- |
| `scene` | 业务场景标识，用来在后台区分上传来源 | 否 |
| `data` / `fileURL` / `bytes` | 三选一，SDK 用它计算上传字节数 | 是 |
| `startedAt` / `duration` | 上传耗时，传 `startedAt` 会自动计算 | 否 |
| `success` | 七牛回调结果是否成功 | 是 |
| `error` | 失败原因，成功时可不传 | 否 |
| `host` | 七牛上传域名，默认 `upload.qiniup.com` | 否 |

### 图片加载和缓存命中

图片加载统计和真实网络流量是两件事：

- 图片真实下载流量：由网络层按域名统计。
- 图片展示成功、失败、业务场景：由 Kingfisher / SDWebImage 回调记录。

普通接入不需要关心缓存类型，图片加载完成后记录成功或失败即可。

Kingfisher 示例：

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

SDWebImage 示例：

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

`scene` 是业务场景标识，不是图片框架参数。它用于后台聚合和排查，例如：

- `chat_image`：聊天图片
- `avatar`：头像
- `feed_image`：动态图片
- `banner`：运营 Banner

参数说明：

| 参数 | 含义 | 是否必填 |
| --- | --- | --- |
| `url` | 图片 URL，用来定位具体资源和 host | 否 |
| `scene` | 业务场景标识，用来在后台区分图片来源 | 否 |
| `success` | 图片是否加载成功 | 是 |
| `error` | 失败原因，成功时可不传 | 否 |
| `cacheType` | 高级参数，用于细分内存/磁盘缓存命中，默认 `.unknown` | 否 |

如果你确实需要统计内存缓存、磁盘缓存、真实网络加载次数，可以额外传 `cacheType`：

```swift
ZWBMonitor.recordImageLoad(
    url: url,
    scene: "chat_image",
    cacheType: .memory,
    success: true
)
```

业务侧可以按需写一个很薄的映射扩展：

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

### 声网 RTC

声网实时音视频流量暂不处理。它通常不走普通 URLSession 请求，后续如果需要支持，应基于声网 SDK 的 stats 回调单独接入。

## 上传报告

### 默认 HTTP 上传

```swift
let config = ZWBMonitorConfig(
    // 预警触发后要生成的报告格式。HTML 后台主要读取 json。
    reportFormats: [.json, .txt, .xml],
    upload: ZWBMonitorHTTPUploadConfig(
        // 你的业务服务器接收报告的接口。
        endpoint: URL(string: "https://your-domain.com/monitor-upload")!,
        // 服务端保存目录标识；也可以由服务端忽略，自行决定存储位置。
        directory: "monitor-reports/reports",
        // 业务鉴权头，可不传。
        headers: [
            "Authorization": "Bearer token"
        ]
    )
)

ZWBMonitor.start(config: config)
```

默认上传会把报告内容、文件名、格式、App 信息、事件类型等一起发送给服务器。服务器可以保存到指定目录，并维护 `index.json`。

### 七牛自动上传监控报告

如果预警触发后希望 SDK 自动把报告上传到七牛，可以配置 `qiniuUpload`。SDK 会为每份报告生成唯一对象路径，默认形如：

```text
monitor-reports/reports/2026-06-23/com.example.demo/high_memory_2026-06-23T10-00-00Z_uuid.json
```

七牛上传 token 必须由你的业务服务端签发，客户端不要保存七牛 AK/SK。最简单的方式是使用 SDK 内置的 HTTP token provider：

```swift
let tokenProvider = ZWBMonitorQiniuHTTPTokenProvider(
    // 你的业务服务器接口，不是七牛官方接口。
    // 服务端用七牛 AK/SK 签发 upload token，然后返回 { "token": "..." }。
    endpoint: URL(string: "https://your-domain.com/qiniu/upload-token")!,
    // 业务鉴权头，没有鉴权可以传空字典。
    headers: [
        "Authorization": "Bearer token"
    ]
)

let config = ZWBMonitorConfig(
    // 建议至少保留 json，HTML 后台会读取 json。
    reportFormats: [.json],
    qiniuUpload: ZWBMonitorQiniuUploadConfig(
        // SDK 达到预警时会先通过它拿七牛 upload token。
        tokenProvider: tokenProvider,
        // 七牛对象路径前缀。最终路径类似 monitor-reports/reports/日期/bundleId/文件名.json。
        keyPrefix: "monitor-reports",
        // 七牛上传域名，也会用于上传流量统计。
        uploadHost: "upload.qiniup.com",
        // 你的 CDN 域名。配置后上传结果会带可访问 URL。
        cdnBaseURL: URL(string: "https://cdn.your-domain.com"),
        // 可选：上传成功后通知你的服务器维护 index.json，HTML 后台才能自动发现新报告。
        indexCallback: ZWBMonitorQiniuIndexCallbackConfig(
            endpoint: URL(string: "https://your-domain.com/monitor/index")!
        )
    )
)

// 启动后无需手动上传；达到预警阈值时 SDK 会自动生成报告并上传七牛。
ZWBMonitor.start(config: config)
```

`/qiniu/upload-token` 需要返回：

```json
{
  "token": "七牛上传凭证"
}
```

如果配置了 `indexCallback`，七牛上传成功后 SDK 会把报告 ID、App 信息、事件、等级、对象路径和 CDN URL 回调给你的服务端，服务端可以据此维护 `index.json`，供 HTML 后台读取。

上传监控报告本身也会自动记入流量统计，分类为 `qiniu`，场景为 `monitor_report`。

### 自定义上传

如果你要上传到自己的日志系统、OSS、S3、七牛、阿里云 OSS 或私有接口，可以实现 `ZWBMonitorUploading`：

```swift
final class MyUploader: ZWBMonitorUploading {
    func upload(
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void
    ) {
        // 将 report.content 上传到你的服务器或对象存储。
        completion(.success(ZWBMonitorUploadResult(reportId: snapshot.id)))
    }
}

var config = ZWBMonitorConfig.default
config.customUploader = MyUploader()
ZWBMonitor.start(config: config)
```

## 钉钉通知

```swift
let config = ZWBMonitorConfig(
    dingTalk: ZWBDingTalkConfig(
        webhook: URL(string: "https://oapi.dingtalk.com/robot/send?access_token=xxx")!,
        secret: nil
    )
)

ZWBMonitor.start(config: config)
```

如果钉钉机器人启用了加签，可以把 `secret` 传入配置。

## HTML 后台

`Dashboard/` 是静态后台模板，`html/` 是本地预览示例目录。

推荐服务器目录结构：

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

后台读取流程：

```text
读取 index.json
↓
获取报告列表
↓
逐条读取 reports/*.json
↓
按 App 聚合展示
↓
点击 App 查看该 App 的报告列表和详情
```

本地预览：

```bash
cd html
python3 -m http.server 8097 --bind 127.0.0.1
```

打开：

```text
http://127.0.0.1:8097/index.html
```

## Demo App

项目中包含一个 UIKit Demo：

- 启动时默认开启 SDK。
- 点击“刷新快照”可以查看当前采集到的信息。
- 点击“记录一条事件”可以模拟事件写入。

## 目录说明

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

## 设计原则

- SDK 保持通用，不依赖任何业务项目。
- 上传和通知能力通过协议扩展，不绑定固定服务器。
- 默认低侵入接入，业务语义事件提供轻量手动 API。
- 报告数据结构保持英文稳定字段，展示层可以做中文映射。
