import Foundation
import UIKit

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

public enum ZWBMonitorReportFormat: String, CaseIterable, Codable, Hashable {
    case json
    case txt
    case xml
}

public enum ZWBMonitorEventLevel: String, Codable {
    case info
    case warning
    case critical
}

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

public struct ZWBMonitorTrafficRule: Codable, Hashable {
    public var name: String
    public var hosts: [String]
    public var category: ZWBMonitorTrafficCategory

    public init(name: String, hosts: [String], category: ZWBMonitorTrafficCategory) {
        self.name = name
        self.hosts = hosts
        self.category = category
    }
}

public struct ZWBMonitorThresholds {
    public var memoryMB: Double
    public var cpuPercent: Double
    public var cpuDuration: TimeInterval
    public var fps: Int
    public var fpsDuration: TimeInterval
    public var diskFreeGB: Double
    public var socketReconnectCount: Int
    public var uploadFailureCount: Int
    public var apiFailureCount: Int
    public var triggerCooldown: TimeInterval

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

public struct ZWBMonitorHTTPUploadConfig {
    public var endpoint: URL
    public var directory: String?
    public var headers: [String: String]

    public init(endpoint: URL, directory: String? = nil, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.directory = directory
        self.headers = headers
    }
}

public struct ZWBDingTalkConfig {
    public var webhook: URL
    public var secret: String?

    public init(webhook: URL, secret: String? = nil) {
        self.webhook = webhook
        self.secret = secret
    }
}

public struct ZWBMonitorConfig {
    public var enabledModules: Set<ZWBMonitorModule>
    public var thresholds: ZWBMonitorThresholds
    public var sampleInterval: TimeInterval
    public var reportFormats: Set<ZWBMonitorReportFormat>
    public var localReportDirectory: URL?
    public var upload: ZWBMonitorHTTPUploadConfig?
    public var dingTalk: ZWBDingTalkConfig?
    public var customUploader: ZWBMonitorUploading?
    public var customNotifier: ZWBMonitorNotifying?
    public var trafficRules: [ZWBMonitorTrafficRule]
    public var enablePageAutoTrack: Bool
    public var enableNetworkURLProtocol: Bool

    public static var `default`: ZWBMonitorConfig {
        ZWBMonitorConfig()
    }

    public init(
        enabledModules: Set<ZWBMonitorModule> = Set(ZWBMonitorModule.allCases),
        thresholds: ZWBMonitorThresholds = ZWBMonitorThresholds(),
        sampleInterval: TimeInterval = 1,
        reportFormats: Set<ZWBMonitorReportFormat> = [.json, .txt],
        localReportDirectory: URL? = nil,
        upload: ZWBMonitorHTTPUploadConfig? = nil,
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
        self.dingTalk = dingTalk
        self.customUploader = customUploader
        self.customNotifier = customNotifier
        self.trafficRules = trafficRules
        self.enablePageAutoTrack = enablePageAutoTrack
        self.enableNetworkURLProtocol = enableNetworkURLProtocol
    }
}

public struct ZWBMonitorUploadResult {
    public var reportId: String?
    public var remoteURL: URL?

    public init(reportId: String? = nil, remoteURL: URL? = nil) {
        self.reportId = reportId
        self.remoteURL = remoteURL
    }
}

public protocol ZWBMonitorUploading: AnyObject {
    func upload(report: ZWBMonitorReportFile, snapshot: ZWBMonitorSnapshot, completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void)
}

public protocol ZWBMonitorNotifying: AnyObject {
    func notify(snapshot: ZWBMonitorSnapshot, report: ZWBMonitorReportFile?, completion: @escaping (Result<Void, Error>) -> Void)
}

public struct ZWBMonitorReportFile {
    public var id: String
    public var fileName: String
    public var format: ZWBMonitorReportFormat
    public var content: Data
    public var localURL: URL?

    public init(id: String, fileName: String, format: ZWBMonitorReportFormat, content: Data, localURL: URL? = nil) {
        self.id = id
        self.fileName = fileName
        self.format = format
        self.content = content
        self.localURL = localURL
    }
}

public struct ZWBMonitorBreadcrumb: Codable {
    public var name: String
    public var time: String
    public var attributes: [String: String]

    public init(name: String, time: String, attributes: [String: String] = [:]) {
        self.name = name
        self.time = time
        self.attributes = attributes
    }
}

public struct ZWBMonitorSnapshot: Codable {
    public var id: String
    public var event: String
    public var level: ZWBMonitorEventLevel
    public var time: String
    public var app: AppInfo
    public var device: DeviceInfo
    public var runtime: RuntimeInfo
    public var network: NetworkInfo
    public var disk: DiskInfo
    public var battery: BatteryInfo
    public var thermal: ThermalInfo
    public var page: PageInfo
    public var traffic: TrafficInfo
    public var counters: Counters
    public var eventHistory: [ZWBMonitorBreadcrumb]
    public var networkHistory: [NetworkTrace]

    public struct AppInfo: Codable {
        public var bundleId: String
        public var name: String
        public var version: String
        public var build: String
    }

    public struct DeviceInfo: Codable {
        public var model: String
        public var systemName: String
        public var systemVersion: String
        public var language: String
        public var region: String
        public var timeZone: String
    }

    public struct RuntimeInfo: Codable {
        public var cpu: Double
        public var memoryMB: Double
        public var fps: Int
        public var averageFPS: Int
        public var minimumFPS: Int
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

    public struct TrafficInfo: Codable {
        public var totalUploadBytes: Int64
        public var totalDownloadBytes: Int64
        public var totalUploadMB: Double
        public var totalDownloadMB: Double
        public var groups: [TrafficGroup]
        public var recentRecords: [TrafficRecord]
        public var imageLoads: ImageLoadInfo
    }

    public struct TrafficGroup: Codable {
        public var name: String
        public var category: String
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

    public struct ImageLoadInfo: Codable {
        public var displayCount: Int
        public var networkLoadCount: Int
        public var memoryCacheHitCount: Int
        public var diskCacheHitCount: Int
        public var failureCount: Int
        public var records: [ImageLoadRecord]
    }

    public struct ImageLoadRecord: Codable {
        public var url: String?
        public var host: String?
        public var scene: String?
        public var cacheType: String
        public var success: Bool
        public var error: String?
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
