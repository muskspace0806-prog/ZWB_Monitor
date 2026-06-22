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

本地调试时也可以使用：

```ruby
pod 'ZWB_Monitor', :path => '../ZWB_Monitor'
```

## 快速开始

默认全量开启：

```swift
import ZWBMonitor

ZWBMonitor.start(config: .default)
```

按需开启模块：

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

## 上传报告

### 默认 HTTP 上传

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

默认上传会把报告内容、文件名、格式、App 信息、事件类型等一起发送给服务器。服务器可以保存到指定目录，并维护 `index.json`。

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

