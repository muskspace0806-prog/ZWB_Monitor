import Foundation
import UIKit

/// SDK 可开启的监控模块。默认会开启全部模块，也可以在 `ZWBMonitorConfig.enabledModules` 中按需裁剪。
public enum ZWBMonitorModule: String, CaseIterable, Codable, Hashable {
    case cpu
    case memory
    case fps
    case battery
    case thermal
    case network
    case traffic
    case disk
    case page
    case events
}

/// 预警触发后生成的报告格式。
public enum ZWBMonitorReportFormat: String, CaseIterable, Codable, Hashable {
    case json
    case txt
    case xml
}

/// 告警等级。SDK 内置规则会自动分配，业务也可以在手动快照时指定。
public enum ZWBMonitorEventLevel: String, Codable {
    case info
    case warning
    case critical
}

/// 流量分类，用于后台按业务接口、资源、上传、七牛等维度聚合。
public enum ZWBMonitorTrafficCategory: String, Codable, Hashable {
    case unclassified
    case api
    case resource
    case upload
    case qiniu
    case custom
}

public enum ZWBMonitorTrafficDirection: String, Codable, Hashable {
    case upload
    case download
    case both
}

public enum ZWBMonitorTrafficSource: String, Codable, Hashable {
    case automatic
    case manual
}

/// 图片资源缓存来源。普通接入可不传，默认 `.unknown`。
public enum ZWBMonitorResourceCacheType: String, Codable, Hashable {
    case none
    case memory
    case disk
    case unknown
}

public enum ZWBMonitorFileCategory: String, Codable, Hashable {
    case image
    case video
    case audio
    case document
    case archive
    case svga
    case file
    case unknown

    public static func infer(fromExtension fileExtension: String?) -> ZWBMonitorFileCategory {
        let value = (fileExtension ?? "").lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp"].contains(value) {
            return .image
        }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(value) {
            return .video
        }
        if ["mp3", "aac", "m4a", "wav", "flac", "amr", "ogg"].contains(value) {
            return .audio
        }
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv"].contains(value) {
            return .document
        }
        if ["zip", "rar", "7z", "tar", "gz"].contains(value) {
            return .archive
        }
        if value == "svga" {
            return .svga
        }
        return value.isEmpty ? .unknown : .file
    }
}

/// 按域名统计流量的规则。
/// 例如业务接口域名填 `.api`，七牛 CDN 域名填 `.resource`，七牛上传域名填 `.qiniu`。
public struct ZWBMonitorTrafficRule: Codable, Hashable {
    /// 后台展示的分组名称，例如“业务接口”“七牛上传”。
    public var name: String
    /// 需要匹配的域名列表，例如 `["api.example.com", "upload.qiniup.com"]`。
    public var hosts: [String]
    /// 该分组的流量分类。
    public var category: ZWBMonitorTrafficCategory

    /// 创建一条域名分组规则。
    public init(name: String, hosts: [String], category: ZWBMonitorTrafficCategory) {
        self.name = name
        self.hosts = hosts
        self.category = category
    }
}

/// 预警阈值配置。达到阈值后会生成报告，并按配置上传/通知。
public struct ZWBMonitorThresholds {
    /// 内存占用阈值，单位 MB。
    public var memoryMB: Double
    /// CPU 占用阈值，单位百分比。
    public var cpuPercent: Double
    /// CPU 持续超过阈值多久才触发，单位秒。
    public var cpuDuration: TimeInterval
    /// FPS 低于该值时开始计时。
    public var fps: Int
    /// FPS 持续低于阈值多久才触发，单位秒。
    public var fpsDuration: TimeInterval
    /// 磁盘剩余空间阈值，单位 GB。
    public var diskFreeGB: Double
    /// Socket 重连次数阈值，需要业务手动调用 `recordSocketReconnect()`。
    public var socketReconnectCount: Int
    /// 上传失败次数阈值，需要业务手动调用 `recordUploadFailure()`。
    public var uploadFailureCount: Int
    /// API 失败次数阈值，需要业务手动调用 `recordAPIFailure()`。
    public var apiFailureCount: Int
    /// 同一类告警的冷却时间，避免短时间重复刷屏，单位秒。
    public var triggerCooldown: TimeInterval

    /// 创建预警阈值配置。未传的参数使用 SDK 默认值。
    public init(
        memoryMB: Double = 800,
        cpuPercent: Double = 80,
        cpuDuration: TimeInterval = 30,
        fps: Int = 20,
        fpsDuration: TimeInterval = 10,
        diskFreeGB: Double = 2,
        socketReconnectCount: Int = 5,
        uploadFailureCount: Int = 10,
        apiFailureCount: Int = 20,
        triggerCooldown: TimeInterval = 60
    ) {
        self.memoryMB = memoryMB
        self.cpuPercent = cpuPercent
        self.cpuDuration = cpuDuration
        self.fps = fps
        self.fpsDuration = fpsDuration
        self.diskFreeGB = diskFreeGB
        self.socketReconnectCount = socketReconnectCount
        self.uploadFailureCount = uploadFailureCount
        self.apiFailureCount = apiFailureCount
        self.triggerCooldown = triggerCooldown
    }
}

/// 默认 HTTP 报告上传配置。适合上传到你自己的服务器接口。
public struct ZWBMonitorHTTPUploadConfig {
    /// 业务服务器接收报告的接口地址。
    public var endpoint: URL
    /// 服务端保存目录标识，可为空，由服务端自行决定存储位置。
    public var directory: String?
    /// 上传请求头，例如鉴权 token。
    public var headers: [String: String]

    /// 创建默认 HTTP 上传配置。
    public init(endpoint: URL, directory: String? = nil, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.directory = directory
        self.headers = headers
    }
}

/// 钉钉机器人告警配置。
public struct ZWBDingTalkConfig {
    /// 钉钉机器人 webhook。
    public var webhook: URL
    /// 钉钉加签密钥；机器人未开启加签时传 nil。
    public var secret: String?

    /// 创建钉钉机器人配置。
    public init(webhook: URL, secret: String? = nil) {
        self.webhook = webhook
        self.secret = secret
    }
}

/// 七牛上传凭证提供方。
/// SDK 不保存七牛 AK/SK；每次上传前通过该协议向业务服务器获取 upload token。
public protocol ZWBMonitorQiniuTokenProviding: AnyObject {
    /// 请求七牛 upload token。
    /// - Parameters:
    ///   - report: 本次要上传的报告文件。
    ///   - snapshot: 触发预警时的性能快照。
    ///   - objectKey: SDK 生成的七牛对象路径，服务端签 token 时应使用同一个 key。
    ///   - completion: 返回七牛 upload token 或错误。
    func requestUploadToken(
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        objectKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    )
}

/// 七牛上传成功后的索引回调配置。
/// 用于通知业务服务器更新 `index.json`，让 HTML 后台能看到新报告。
public struct ZWBMonitorQiniuIndexCallbackConfig {
    /// 业务服务器索引回调接口。
    public var endpoint: URL
    /// 回调请求头，例如鉴权 token。
    public var headers: [String: String]

    /// 创建索引回调配置。
    public init(endpoint: URL, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.headers = headers
    }
}

/// 七牛自动上传报告配置。
/// 配置后，达到预警阈值时 SDK 会自动生成报告并上传到七牛。
public struct ZWBMonitorQiniuUploadConfig {
    /// 七牛上传凭证提供方，通常使用 `ZWBMonitorQiniuHTTPTokenProvider`。
    public var tokenProvider: ZWBMonitorQiniuTokenProviding
    /// 七牛对象路径前缀，例如 `monitor-reports`。
    public var keyPrefix: String
    /// 七牛上传域名，用于上传和流量统计，默认 `upload.qiniup.com`。
    public var uploadHost: String
    /// CDN 域名。配置后上传结果会返回可访问 URL。
    public var cdnBaseURL: URL?
    /// 上传成功后的服务端索引回调；不需要 HTML 后台自动更新时可传 nil。
    public var indexCallback: ZWBMonitorQiniuIndexCallbackConfig?

    /// 创建七牛自动上传配置。
    public init(
        tokenProvider: ZWBMonitorQiniuTokenProviding,
        keyPrefix: String = "monitor-reports",
        uploadHost: String = "upload.qiniup.com",
        cdnBaseURL: URL? = nil,
        indexCallback: ZWBMonitorQiniuIndexCallbackConfig? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.keyPrefix = keyPrefix
        self.uploadHost = uploadHost
        self.cdnBaseURL = cdnBaseURL
        self.indexCallback = indexCallback
    }
}

/// SDK 启动配置。最小接入可直接使用 `.default`。
public struct ZWBMonitorConfig {
    /// 启用的监控模块，默认全部启用。
    public var enabledModules: Set<ZWBMonitorModule>
    /// 告警阈值配置。
    public var thresholds: ZWBMonitorThresholds
    /// 采样间隔，单位秒。建议保持默认值。
    public var sampleInterval: TimeInterval
    /// 预警报告生成格式，默认 `.json` 和 `.txt`。
    public var reportFormats: Set<ZWBMonitorReportFormat>
    /// 本地报告保存目录；为空时使用 SDK 默认目录。
    public var localReportDirectory: URL?
    /// 默认 HTTP 上传配置。
    public var upload: ZWBMonitorHTTPUploadConfig?
    /// 七牛自动上传配置。配置后达到预警会自动上传报告。
    public var qiniuUpload: ZWBMonitorQiniuUploadConfig?
    /// 钉钉机器人告警配置。
    public var dingTalk: ZWBDingTalkConfig?
    /// 自定义上传器，适合接入自有日志平台或其它对象存储。
    public var customUploader: ZWBMonitorUploading?
    /// 自定义通知器。
    public var customNotifier: ZWBMonitorNotifying?
    /// 流量域名分组规则。
    public var trafficRules: [ZWBMonitorTrafficRule]
    /// 是否自动记录页面展示，默认开启。
    public var enablePageAutoTrack: Bool
    /// 是否通过 runtime 注入 URLProtocol 自动采集 URLSession 流量，默认开启。
    /// 开启后会尽量覆盖 URLSession.shared、Alamofire、Moya 等基于 URLSession 的请求。
    public var enableNetworkURLProtocol: Bool

    /// 默认配置：开启全部模块，使用默认阈值，不自动上传。
    public static var `default`: ZWBMonitorConfig {
        ZWBMonitorConfig()
    }

    /// 创建 SDK 启动配置。参数较多时建议先 `var config = ZWBMonitorConfig.default` 再逐项修改。
    public init(
        enabledModules: Set<ZWBMonitorModule> = Set(ZWBMonitorModule.allCases),
        thresholds: ZWBMonitorThresholds = ZWBMonitorThresholds(),
        sampleInterval: TimeInterval = 1,
        reportFormats: Set<ZWBMonitorReportFormat> = [.json, .txt],
        localReportDirectory: URL? = nil,
        upload: ZWBMonitorHTTPUploadConfig? = nil,
        qiniuUpload: ZWBMonitorQiniuUploadConfig? = nil,
        dingTalk: ZWBDingTalkConfig? = nil,
        customUploader: ZWBMonitorUploading? = nil,
        customNotifier: ZWBMonitorNotifying? = nil,
        trafficRules: [ZWBMonitorTrafficRule] = [],
        enablePageAutoTrack: Bool = true,
        enableNetworkURLProtocol: Bool = true
    ) {
        self.enabledModules = enabledModules
        self.thresholds = thresholds
        self.sampleInterval = sampleInterval
        self.reportFormats = reportFormats
        self.localReportDirectory = localReportDirectory
        self.upload = upload
        self.qiniuUpload = qiniuUpload
        self.dingTalk = dingTalk
        self.customUploader = customUploader
        self.customNotifier = customNotifier
        self.trafficRules = trafficRules
        self.enablePageAutoTrack = enablePageAutoTrack
        self.enableNetworkURLProtocol = enableNetworkURLProtocol
    }
}

/// 报告上传结果。
public struct ZWBMonitorUploadResult {
    /// 业务服务器或 SDK 生成的报告 ID。
    public var reportId: String?
    /// 上传后的远程访问地址，例如 CDN URL。
    public var remoteURL: URL?
    /// 对象存储路径，例如七牛 object key。
    public var objectKey: String?

    /// 创建上传结果。
    public init(reportId: String? = nil, remoteURL: URL? = nil, objectKey: String? = nil) {
        self.reportId = reportId
        self.remoteURL = remoteURL
        self.objectKey = objectKey
    }
}

/// 自定义报告上传协议。需要上传到私有日志平台、OSS、S3 等场景时实现。
public protocol ZWBMonitorUploading: AnyObject {
    /// 上传一份报告。
    func upload(report: ZWBMonitorReportFile, snapshot: ZWBMonitorSnapshot, completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void)
}

/// 自定义告警通知协议。
public protocol ZWBMonitorNotifying: AnyObject {
    /// 发送一条告警通知。
    func notify(snapshot: ZWBMonitorSnapshot, report: ZWBMonitorReportFile?, completion: @escaping (Result<Void, Error>) -> Void)
}

/// SDK 生成的报告文件。
public struct ZWBMonitorReportFile {
    /// 报告 ID，对应 `ZWBMonitorSnapshot.id`。
    public var id: String
    /// 文件名。
    public var fileName: String
    /// 文件格式。
    public var format: ZWBMonitorReportFormat
    /// 文件内容。
    public var content: Data
    /// 本地保存地址。
    public var localURL: URL?
    /// 建议对象存储路径，七牛上传时默认使用该路径。
    public var suggestedObjectKey: String?

    /// 创建一份报告文件。
    public init(
        id: String,
        fileName: String,
        format: ZWBMonitorReportFormat,
        content: Data,
        localURL: URL? = nil,
        suggestedObjectKey: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.format = format
        self.content = content
        self.localURL = localURL
        self.suggestedObjectKey = suggestedObjectKey
    }
}

/// 业务事件记录。通过 `ZWBMonitor.record(event:attributes:)` 写入。
public struct ZWBMonitorBreadcrumb: Codable {
    /// 事件名称。
    public var name: String
    /// 事件发生时间。
    public var time: String
    /// 事件附加信息。
    public var attributes: [String: String]

    public init(name: String, time: String, attributes: [String: String] = [:]) {
        self.name = name
        self.time = time
        self.attributes = attributes
    }
}

/// 一次性能快照，也是 JSON 报告的主体结构。
public struct ZWBMonitorSnapshot: Codable {
    /// 快照 ID，每次生成唯一。
    public var id: String
    /// 触发事件，例如 `high_memory`、`low_fps`、`manual`。
    public var event: String
    /// 告警等级。
    public var level: ZWBMonitorEventLevel
    /// 采集时间，ISO8601 字符串。
    public var time: String
    /// App 信息。
    public var app: AppInfo
    /// 设备信息。
    public var device: DeviceInfo
    /// CPU、内存、FPS 等运行状态。
    public var runtime: RuntimeInfo
    /// 网络类型和总流量。
    public var network: NetworkInfo
    /// 磁盘空间。
    public var disk: DiskInfo
    /// 电量状态。
    public var battery: BatteryInfo
    /// 设备温度状态。
    public var thermal: ThermalInfo
    /// 当前页面信息。
    public var page: PageInfo
    /// 流量分组、最近请求和图片加载统计。
    public var traffic: TrafficInfo
    /// 业务计数器。
    public var counters: Counters
    /// 最近业务事件。
    public var eventHistory: [ZWBMonitorBreadcrumb]
    /// 最近网络请求。
    public var networkHistory: [NetworkTrace]

    /// App 信息。
    public struct AppInfo: Codable {
        /// Bundle ID。
        public var bundleId: String
        /// App 显示名称。
        public var name: String
        /// 版本号。
        public var version: String
        /// Build 号。
        public var build: String
    }

    /// 设备信息。
    public struct DeviceInfo: Codable {
        /// 设备型号。
        public var model: String
        /// 系统名称。
        public var systemName: String
        /// 系统版本。
        public var systemVersion: String
        /// 当前语言。
        public var language: String
        /// 当前地区。
        public var region: String
        /// 当前时区。
        public var timeZone: String
    }

    /// 运行状态。
    public struct RuntimeInfo: Codable {
        /// CPU 占用百分比。
        public var cpu: Double
        /// 内存占用，单位 MB。
        public var memoryMB: Double
        /// 当前 FPS。
        public var fps: Int
        /// 平均 FPS。
        public var averageFPS: Int
        /// 最低 FPS。
        public var minimumFPS: Int
        /// 启动后时长，单位秒。
        public var launchTime: Double?
    }

    public struct NetworkInfo: Codable {
        public var type: String
        public var isExpensive: Bool
        public var isConstrained: Bool
        public var uploadMB: Double?
        public var downloadMB: Double?
    }

    public struct DiskInfo: Codable {
        public var totalGB: Double
        public var freeGB: Double
        public var usedGB: Double
    }

    public struct BatteryInfo: Codable {
        public var level: Int
        public var charging: Bool
        public var state: String
        public var lowPowerMode: Bool
    }

    public struct ThermalInfo: Codable {
        public var state: String
    }

    public struct PageInfo: Codable {
        public var current: String?
        public var previous: String?
        public var stayDuration: Double?
    }

    public struct Counters: Codable {
        public var socketReconnects: Int
        public var uploadFailures: Int
        public var apiFailures: Int
    }

    /// 流量汇总。
    public struct TrafficInfo: Codable {
        /// 总上传字节数。
        public var totalUploadBytes: Int64
        /// 总下载字节数。
        public var totalDownloadBytes: Int64
        /// 总上传 MB。
        public var totalUploadMB: Double
        /// 总下载 MB。
        public var totalDownloadMB: Double
        /// 按域名规则聚合后的分组。
        public var groups: [TrafficGroup]
        /// 最近流量记录。
        public var recentRecords: [TrafficRecord]
        /// 图片加载统计。
        public var imageLoads: ImageLoadInfo
    }

    /// 单个流量分组统计。
    public struct TrafficGroup: Codable {
        /// 分组名称，例如“业务接口”“七牛上传”。
        public var name: String
        /// 分组分类。
        public var category: String
        /// 命中的 host 列表。
        public var hosts: [String]
        public var uploadBytes: Int64
        public var downloadBytes: Int64
        public var uploadMB: Double
        public var downloadMB: Double
        public var requestCount: Int
        public var failureCount: Int
    }

    public struct TrafficRecord: Codable {
        public var source: String
        public var groupName: String
        public var category: String
        public var direction: String
        public var host: String?
        public var url: String?
        public var method: String?
        public var uploadBytes: Int64
        public var downloadBytes: Int64
        public var statusCode: Int?
        public var success: Bool
        public var durationMS: Double?
        public var scene: String?
        public var provider: String?
        public var fileCategory: String?
        public var fileExtension: String?
        public var mimeType: String?
        public var error: String?
        public var time: String
    }

    /// 图片加载汇总。
    public struct ImageLoadInfo: Codable {
        /// 图片展示成功次数。
        public var displayCount: Int
        /// 明确标记为无缓存的网络加载次数。
        public var networkLoadCount: Int
        /// 内存缓存命中次数。
        public var memoryCacheHitCount: Int
        /// 磁盘缓存命中次数。
        public var diskCacheHitCount: Int
        /// 图片加载失败次数。
        public var failureCount: Int
        /// 最近图片加载记录。
        public var records: [ImageLoadRecord]
    }

    /// 单次图片加载记录。
    public struct ImageLoadRecord: Codable {
        /// 图片 URL。
        public var url: String?
        /// 图片 host。
        public var host: String?
        /// 业务场景，例如 `chat_image`。
        public var scene: String?
        /// 缓存来源，普通接入默认为 `unknown`。
        public var cacheType: String
        /// 是否加载成功。
        public var success: Bool
        /// 失败原因。
        public var error: String?
        /// 记录时间。
        public var time: String
    }

    public struct NetworkTrace: Codable {
        public var url: String
        public var method: String
        public var statusCode: Int?
        public var durationMS: Double
        public var requestBytes: Int
        public var responseBytes: Int
        public var trafficGroup: String?
        public var trafficCategory: String?
        public var error: String?
        public var time: String
    }
}
