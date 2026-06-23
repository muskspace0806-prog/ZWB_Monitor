import Foundation
import UIKit

public final class ZWBMonitor {
    /// SDK 单例。普通接入建议使用静态方法，不需要直接访问该对象。
    public static let shared = ZWBMonitor()

    private var config: ZWBMonitorConfig = .default
    private let runtimeCollector = ZWBMonitorRuntimeCollector()
    private let fpsCollector = ZWBMonitorFPSCollector()
    private let networkCollector = ZWBMonitorNetworkCollector()
    private let pageTracker = ZWBMonitorPageTracker.shared
    private let ruleEngine = ZWBMonitorRuleEngine()
    private let reporter = ZWBMonitorReporter()
    private var timer: Timer?
    private var breadcrumbs: [ZWBMonitorBreadcrumb] = []
    private var networkTraces: [ZWBMonitorSnapshot.NetworkTrace] = []
    private var trafficRecords: [ZWBMonitorSnapshot.TrafficRecord] = []
    private var socketReconnects = 0
    private var uploadFailures = 0
    private var apiFailures = 0
    private let lock = NSLock()
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    /// 启动性能监控。通常在 `AppDelegate` 或应用启动入口调用一次。
    /// - Parameter config: 监控配置；不传时默认开启全部模块，但不会自动上传。
    public static func start(config: ZWBMonitorConfig = .default) {
        shared.start(config: config)
    }

    /// 停止性能监控。一般仅在调试或特殊业务场景使用。
    public static func stop() {
        shared.stop()
    }

    /// 获取当前性能快照，不会触发上传。
    /// - Parameters:
    ///   - reason: 本次手动采集原因，方便后台识别。
    ///   - level: 快照等级，默认普通信息。
    public static func currentSnapshot(reason: String = "manual", level: ZWBMonitorEventLevel = .info) -> ZWBMonitorSnapshot {
        shared.makeSnapshot(event: reason, level: level)
    }

    /// 记录一条业务事件，会出现在报告的事件记录中。
    /// - Parameters:
    ///   - name: 事件名，例如 `SendMessage`、`EnterRoom`。
    ///   - attributes: 附加信息，建议只放轻量字符串。
    public static func record(event name: String, attributes: [String: String] = [:]) {
        shared.record(event: name, attributes: attributes)
    }

    /// 记录一次 Socket 重连。达到阈值后会触发 `socket_reconnect` 告警。
    public static func recordSocketReconnect() {
        shared.incrementCounter(\.socketReconnects)
    }

    /// 记录一次上传失败。达到阈值后会触发 `upload_failure` 告警。
    public static func recordUploadFailure() {
        shared.incrementCounter(\.uploadFailures)
    }

    /// 记录一次 API 失败。达到阈值后会触发 `api_failure` 告警。
    public static func recordAPIFailure() {
        shared.incrementCounter(\.apiFailures)
    }

    /// 手动记录一笔流量。普通接入优先使用 `recordQiniuUpload` 或 URLSession 自动采集。
    /// - Parameters:
    ///   - host: 请求域名，用于流量分组。
    ///   - name: 展示名称；为空时使用匹配到的分组名。
    ///   - category: 流量分类。
    ///   - direction: 上传、下载或双向。
    ///   - bytes: 流量大小，单位字节。
    public static func recordTraffic(
        host: String,
        name: String? = nil,
        category: ZWBMonitorTrafficCategory = .custom,
        direction: ZWBMonitorTrafficDirection,
        bytes: Int64,
        url: URL? = nil,
        scene: String? = nil,
        provider: String? = nil,
        fileCategory: ZWBMonitorFileCategory? = nil,
        fileExtension: String? = nil,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        success: Bool = true,
        error: String? = nil
    ) {
        shared.recordManualTraffic(
            host: host,
            name: name,
            category: category,
            direction: direction,
            bytes: bytes,
            url: url,
            scene: scene,
            provider: provider,
            fileCategory: fileCategory,
            fileExtension: fileExtension,
            mimeType: mimeType,
            duration: duration,
            success: success,
            error: error
        )
    }

    /// 手动记录一笔上传流量。七牛上传建议使用更简单的 `recordQiniuUpload`。
    /// - Parameters:
    ///   - provider: 上传服务商，例如 `qiniu`、`oss`。
    ///   - host: 上传域名。
    ///   - scene: 业务场景，例如 `chat_attachment`、`avatar_upload`。
    ///   - bytes: 上传大小，单位字节。
    ///   - duration: 上传耗时，单位秒。
    ///   - success: 是否上传成功。
    ///   - error: 失败原因，成功时可为空。
    public static func recordUploadTraffic(
        provider: String = "qiniu",
        host: String,
        scene: String? = nil,
        fileCategory: ZWBMonitorFileCategory = .file,
        fileExtension: String? = nil,
        mimeType: String? = nil,
        bytes: Int64,
        duration: TimeInterval? = nil,
        success: Bool,
        error: String? = nil
    ) {
        shared.recordManualTraffic(
            host: host,
            name: provider,
            category: provider.lowercased() == "qiniu" ? .qiniu : .upload,
            direction: .upload,
            bytes: bytes,
            url: nil,
            scene: scene,
            provider: provider,
            fileCategory: fileCategory,
            fileExtension: fileExtension,
            mimeType: mimeType,
            duration: duration,
            success: success,
            error: error
        )
    }

    /// 记录一笔七牛上传流量。适合已经知道文件大小的场景。
    /// - Parameters:
    ///   - host: 七牛上传域名，默认 `upload.qiniup.com`。
    ///   - scene: 业务场景，例如 `chat_attachment`、`avatar_upload`。
    ///   - bytes: 上传大小，单位字节。
    ///   - startedAt: 上传开始时间；传入后 SDK 自动计算耗时。
    ///   - duration: 已计算好的上传耗时；优先级高于 `startedAt`。
    ///   - success: 七牛回调是否成功。
    ///   - error: 失败原因，成功时可为空。
    public static func recordQiniuUpload(
        host: String = "upload.qiniup.com",
        scene: String? = nil,
        bytes: Int64,
        startedAt: Date? = nil,
        duration: TimeInterval? = nil,
        success: Bool,
        error: String? = nil
    ) {
        recordUploadTraffic(
            provider: "qiniu",
            host: host,
            scene: scene,
            fileCategory: .file,
            bytes: bytes,
            duration: duration ?? startedAt.map { Date().timeIntervalSince($0) },
            success: success,
            error: error
        )
    }

    /// 记录一笔七牛上传流量。适合使用 `Data` 上传的场景，SDK 会自动读取 `data.count`。
    public static func recordQiniuUpload(
        host: String = "upload.qiniup.com",
        scene: String? = nil,
        data: Data,
        startedAt: Date? = nil,
        duration: TimeInterval? = nil,
        success: Bool,
        error: String? = nil
    ) {
        recordQiniuUpload(
            host: host,
            scene: scene,
            bytes: Int64(data.count),
            startedAt: startedAt,
            duration: duration,
            success: success,
            error: error
        )
    }

    /// 记录一笔七牛上传流量。适合使用本地文件路径上传的场景，SDK 会自动读取文件大小。
    public static func recordQiniuUpload(
        host: String = "upload.qiniup.com",
        scene: String? = nil,
        fileURL: URL,
        startedAt: Date? = nil,
        duration: TimeInterval? = nil,
        success: Bool,
        error: String? = nil
    ) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        recordQiniuUpload(
            host: host,
            scene: scene,
            bytes: bytes,
            startedAt: startedAt,
            duration: duration,
            success: success,
            error: error
        )
    }

    /// 创建带 SDK 网络采集能力的 URLSessionConfiguration。
    /// 默认 runtime 注入会自动处理大多数 `URLSession.shared`、Alamofire、Moya 场景；
    /// 只有当项目关闭自动注入，或使用特殊自定义 configuration 时，才需要手动调用该方法。
    public static func makeMonitoredURLSessionConfiguration(_ base: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        let existing = base.protocolClasses ?? []
        if !existing.contains(where: { $0 == ZWBMonitorURLProtocol.self }) {
            base.protocolClasses = [ZWBMonitorURLProtocol.self] + existing
        }
        return base
    }

    func recordNetworkTrace(_ trace: ZWBMonitorSnapshot.NetworkTrace) {
        guard config.enabledModules.contains(.traffic) || config.enabledModules.contains(.network) else { return }
        var trace = trace
        let direction = inferTrafficDirection(uploadBytes: Int64(trace.requestBytes), downloadBytes: Int64(trace.responseBytes))
        let classification = classify(urlString: trace.url, host: URL(string: trace.url)?.host, direction: direction)
        trace.trafficGroup = classification.name
        trace.trafficCategory = classification.category.rawValue

        lock.lock()
        networkTraces.append(trace)
        if networkTraces.count > 50 {
            networkTraces.removeFirst(networkTraces.count - 50)
        }
        if config.enabledModules.contains(.traffic) {
            let record = ZWBMonitorSnapshot.TrafficRecord(
                source: ZWBMonitorTrafficSource.automatic.rawValue,
                groupName: classification.name,
                category: classification.category.rawValue,
                direction: direction.rawValue,
                host: classification.host,
                url: trace.url,
                method: trace.method,
                uploadBytes: Int64(trace.requestBytes),
                downloadBytes: Int64(trace.responseBytes),
                statusCode: trace.statusCode,
                success: trace.error == nil && ((trace.statusCode ?? 200) < 400),
                durationMS: trace.durationMS,
                scene: nil,
                provider: nil,
                fileCategory: inferFileCategory(urlString: trace.url).rawValue,
                fileExtension: URL(string: trace.url)?.pathExtension,
                mimeType: nil,
                error: trace.error,
                time: trace.time
            )
            appendTrafficRecordLocked(record)
        }
        lock.unlock()
    }

    private func start(config: ZWBMonitorConfig) {
        stop()
        self.config = config
        ruleEngine.reset()
        if config.enabledModules.contains(.fps) {
            fpsCollector.start()
        }
        if config.enabledModules.contains(.network) {
            networkCollector.start()
        }
        if config.enabledModules.contains(.page), config.enablePageAutoTrack {
            ZWBMonitorPageTracker.install()
        }
        if config.enableNetworkURLProtocol {
            ZWBMonitorURLProtocolInstaller.install()
        }
        timer = Timer.scheduledTimer(withTimeInterval: max(config.sampleInterval, 0.5), repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer!, forMode: .common)
        record(event: "ZWBMonitorStarted", attributes: [:])
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        fpsCollector.stop()
        networkCollector.stop()
    }

    private func sample() {
        let snapshot = makeSnapshot(event: "sample", level: .info)
        guard let trigger = ruleEngine.evaluate(snapshot: snapshot, thresholds: config.thresholds) else { return }
        let triggeredSnapshot = makeSnapshot(event: trigger.event, level: trigger.level)
        handleTrigger(snapshot: triggeredSnapshot)
    }

    private func handleTrigger(snapshot: ZWBMonitorSnapshot) {
        let files = reporter.makeReports(snapshot: snapshot, formats: config.reportFormats, directory: reportDirectory())
        let primary = files.first(where: { $0.format == .json }) ?? files.first

        if let upload = config.upload, let report = primary {
            ZWBMonitorHTTPUploader(config: upload).upload(report: report, snapshot: snapshot) { _ in }
        }

        if let qiniuUpload = config.qiniuUpload, let report = primary {
            ZWBMonitorQiniuUploader(config: qiniuUpload).upload(report: report, snapshot: snapshot) { _ in }
        }

        if let uploader = config.customUploader, let report = primary {
            uploader.upload(report: report, snapshot: snapshot) { _ in }
        }

        if let dingTalk = config.dingTalk {
            ZWBDingTalkNotifier(config: dingTalk).notify(snapshot: snapshot, report: primary) { _ in }
        }

        if let notifier = config.customNotifier {
            notifier.notify(snapshot: snapshot, report: primary) { _ in }
        }
    }

    private func makeSnapshot(event: String, level: ZWBMonitorEventLevel) -> ZWBMonitorSnapshot {
        lock.lock()
        let copiedBreadcrumbs = breadcrumbs
        let copiedNetworkTraces = networkTraces
        let counters = ZWBMonitorSnapshot.Counters(
            socketReconnects: socketReconnects,
            uploadFailures: uploadFailures,
            apiFailures: apiFailures
        )
        lock.unlock()

        let runtime = ZWBMonitorSnapshot.RuntimeInfo(
            cpu: rounded(config.enabledModules.contains(.cpu) ? runtimeCollector.cpuUsage() : 0),
            memoryMB: rounded(config.enabledModules.contains(.memory) ? runtimeCollector.memoryMB() : 0),
            fps: config.enabledModules.contains(.fps) ? fpsCollector.currentFPS : 0,
            averageFPS: config.enabledModules.contains(.fps) ? fpsCollector.averageFPS : 0,
            minimumFPS: config.enabledModules.contains(.fps) ? (fpsCollector.minimumFPS == Int.max ? 0 : fpsCollector.minimumFPS) : 0,
            launchTime: rounded(runtimeCollector.launchTime())
        )

        let trafficInfo = config.enabledModules.contains(.traffic) ? makeTrafficInfo() : emptyTrafficInfo()
        let network = ZWBMonitorSnapshot.NetworkInfo(
            type: config.enabledModules.contains(.network) ? networkCollector.type : "disabled",
            isExpensive: config.enabledModules.contains(.network) ? networkCollector.isExpensive : false,
            isConstrained: config.enabledModules.contains(.network) ? networkCollector.isConstrained : false,
            uploadMB: config.enabledModules.contains(.traffic) ? trafficInfo.totalUploadMB : nil,
            downloadMB: config.enabledModules.contains(.traffic) ? trafficInfo.totalDownloadMB : nil
        )

        return ZWBMonitorSnapshot(
            id: UUID().uuidString,
            event: event,
            level: level,
            time: Self.dateFormatter.string(from: Date()),
            app: ZWBMonitorDeviceCollector.appInfo(),
            device: ZWBMonitorDeviceCollector.deviceInfo(),
            runtime: runtime,
            network: network,
            disk: config.enabledModules.contains(.disk) ? ZWBMonitorDeviceCollector.diskInfo() : .init(totalGB: 0, freeGB: 0, usedGB: 0),
            battery: config.enabledModules.contains(.battery) ? ZWBMonitorDeviceCollector.batteryInfo() : .init(level: -1, charging: false, state: "disabled", lowPowerMode: false),
            thermal: config.enabledModules.contains(.thermal) ? ZWBMonitorDeviceCollector.thermalInfo() : .init(state: "disabled"),
            page: config.enabledModules.contains(.page) ? pageTracker.currentPageInfo() : .init(current: nil, previous: nil, stayDuration: nil),
            traffic: trafficInfo,
            counters: counters,
            eventHistory: copiedBreadcrumbs,
            networkHistory: copiedNetworkTraces
        )
    }

    private func record(event name: String, attributes: [String: String]) {
        let breadcrumb = ZWBMonitorBreadcrumb(name: name, time: Self.dateFormatter.string(from: Date()), attributes: attributes)
        lock.lock()
        breadcrumbs.append(breadcrumb)
        if breadcrumbs.count > 80 {
            breadcrumbs.removeFirst(breadcrumbs.count - 80)
        }
        lock.unlock()
    }

    private func incrementCounter(_ keyPath: ReferenceWritableKeyPath<ZWBMonitor, Int>) {
        lock.lock()
        self[keyPath: keyPath] += 1
        lock.unlock()
    }

    private func recordManualTraffic(
        host: String,
        name: String?,
        category: ZWBMonitorTrafficCategory,
        direction: ZWBMonitorTrafficDirection,
        bytes: Int64,
        url: URL?,
        scene: String?,
        provider: String?,
        fileCategory: ZWBMonitorFileCategory?,
        fileExtension: String?,
        mimeType: String?,
        duration: TimeInterval?,
        success: Bool,
        error: String?
    ) {
        guard config.enabledModules.contains(.traffic) else { return }
        let classification = classify(urlString: url?.absoluteString, host: host, direction: direction, fallbackName: name, fallbackCategory: category)
        let uploadBytes: Int64
        let downloadBytes: Int64
        switch direction {
        case .upload:
            uploadBytes = max(bytes, 0)
            downloadBytes = 0
        case .download:
            uploadBytes = 0
            downloadBytes = max(bytes, 0)
        case .both:
            uploadBytes = max(bytes, 0)
            downloadBytes = max(bytes, 0)
        }

        let record = ZWBMonitorSnapshot.TrafficRecord(
            source: ZWBMonitorTrafficSource.manual.rawValue,
            groupName: classification.name,
            category: classification.category.rawValue,
            direction: direction.rawValue,
            host: host,
            url: url?.absoluteString,
            method: nil,
            uploadBytes: uploadBytes,
            downloadBytes: downloadBytes,
            statusCode: nil,
            success: success,
            durationMS: duration.map { ($0 * 1000 * 100).rounded() / 100 },
            scene: scene,
            provider: provider,
            fileCategory: (fileCategory ?? ZWBMonitorFileCategory.infer(fromExtension: fileExtension)).rawValue,
            fileExtension: fileExtension,
            mimeType: mimeType,
            error: error,
            time: Self.dateFormatter.string(from: Date())
        )

        lock.lock()
        appendTrafficRecordLocked(record)
        lock.unlock()
    }

    private func appendTrafficRecordLocked(_ record: ZWBMonitorSnapshot.TrafficRecord) {
        trafficRecords.append(record)
        if trafficRecords.count > 300 {
            trafficRecords.removeFirst(trafficRecords.count - 300)
        }
    }

    private func classify(
        urlString: String?,
        host explicitHost: String?,
        direction: ZWBMonitorTrafficDirection? = nil,
        fallbackName: String? = nil,
        fallbackCategory: ZWBMonitorTrafficCategory = .unclassified
    ) -> (name: String, category: ZWBMonitorTrafficCategory, hosts: [String], host: String?) {
        let host = explicitHost ?? urlString.flatMap { URL(string: $0)?.host }
        if let host {
            let matchedRules = config.trafficRules.filter { rule in
                rule.hosts.contains(where: { matches(host: host, ruleHost: $0) })
            }
            if let rule = preferredRule(from: matchedRules, direction: direction) {
                return (rule.name, rule.category, rule.hosts, host)
            }
        }
        if let fallbackName {
            return (fallbackName, fallbackCategory, host.map { [$0] } ?? [], host)
        }
        if config.trafficRules.isEmpty {
            return ("All Traffic", .unclassified, [], host)
        }
        return ("Unclassified Traffic", .unclassified, host.map { [$0] } ?? [], host)
    }

    private func preferredRule(
        from rules: [ZWBMonitorTrafficRule],
        direction: ZWBMonitorTrafficDirection?
    ) -> ZWBMonitorTrafficRule? {
        guard !rules.isEmpty else { return nil }
        let preferredCategories: [ZWBMonitorTrafficCategory]
        switch direction {
        case .some(.upload):
            preferredCategories = [.qiniu, .upload]
        case .some(.download):
            preferredCategories = [.resource, .api]
        case .some(.both), .none:
            preferredCategories = []
        }

        for category in preferredCategories {
            if let rule = rules.first(where: { $0.category == category }) {
                return rule
            }
        }
        return rules.first
    }

    private func inferTrafficDirection(uploadBytes: Int64, downloadBytes: Int64) -> ZWBMonitorTrafficDirection {
        if uploadBytes > 0 {
            return .upload
        }
        if downloadBytes > 0 {
            return .download
        }
        return .both
    }

    private func matches(host: String, ruleHost: String) -> Bool {
        let host = host.lowercased()
        let ruleHost = ruleHost.lowercased()
        return host == ruleHost || host.hasSuffix("." + ruleHost)
    }

    private func makeTrafficInfo() -> ZWBMonitorSnapshot.TrafficInfo {
        lock.lock()
        let copiedRecords = trafficRecords
        lock.unlock()

        let totalUpload = copiedRecords.reduce(Int64(0)) { $0 + $1.uploadBytes }
        let totalDownload = copiedRecords.reduce(Int64(0)) { $0 + $1.downloadBytes }
        var grouped: [String: ZWBMonitorSnapshot.TrafficGroup] = [:]
        for record in copiedRecords {
            let key = record.groupName + "|" + record.category
            var group = grouped[key] ?? ZWBMonitorSnapshot.TrafficGroup(
                name: record.groupName,
                category: record.category,
                hosts: [],
                uploadBytes: 0,
                downloadBytes: 0,
                uploadMB: 0,
                downloadMB: 0,
                requestCount: 0,
                failureCount: 0
            )
            if let host = record.host, !group.hosts.contains(host) {
                group.hosts.append(host)
            }
            group.uploadBytes += record.uploadBytes
            group.downloadBytes += record.downloadBytes
            group.uploadMB = bytesToMB(group.uploadBytes)
            group.downloadMB = bytesToMB(group.downloadBytes)
            group.requestCount += 1
            if !record.success {
                group.failureCount += 1
            }
            grouped[key] = group
        }

        return ZWBMonitorSnapshot.TrafficInfo(
            totalUploadBytes: totalUpload,
            totalDownloadBytes: totalDownload,
            totalUploadMB: bytesToMB(totalUpload),
            totalDownloadMB: bytesToMB(totalDownload),
            groups: grouped.values.sorted { $0.downloadBytes + $0.uploadBytes > $1.downloadBytes + $1.uploadBytes },
            recentRecords: Array(copiedRecords.suffix(80))
        )
    }

    private func emptyTrafficInfo() -> ZWBMonitorSnapshot.TrafficInfo {
        ZWBMonitorSnapshot.TrafficInfo(
            totalUploadBytes: 0,
            totalDownloadBytes: 0,
            totalUploadMB: 0,
            totalDownloadMB: 0,
            groups: [],
            recentRecords: []
        )
    }

    private func inferFileCategory(urlString: String?) -> ZWBMonitorFileCategory {
        ZWBMonitorFileCategory.infer(fromExtension: urlString.flatMap { URL(string: $0)?.pathExtension })
    }

    private func reportDirectory() -> URL {
        if let directory = config.localReportDirectory {
            return directory
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("ZWBMonitorReports", isDirectory: true)
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func bytesToMB(_ bytes: Int64) -> Double {
        rounded(Double(bytes) / 1024.0 / 1024.0)
    }
}
