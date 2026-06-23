import Foundation
import UIKit

public final class ZWBMonitor {
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
    private var imageLoadRecords: [ZWBMonitorSnapshot.ImageLoadRecord] = []
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

    public static func start(config: ZWBMonitorConfig = .default) {
        shared.start(config: config)
    }

    public static func stop() {
        shared.stop()
    }

    public static func currentSnapshot(reason: String = "manual", level: ZWBMonitorEventLevel = .info) -> ZWBMonitorSnapshot {
        shared.makeSnapshot(event: reason, level: level)
    }

    public static func record(event name: String, attributes: [String: String] = [:]) {
        shared.record(event: name, attributes: attributes)
    }

    public static func recordSocketReconnect() {
        shared.incrementCounter(\.socketReconnects)
    }

    public static func recordUploadFailure() {
        shared.incrementCounter(\.uploadFailures)
    }

    public static func recordAPIFailure() {
        shared.incrementCounter(\.apiFailures)
    }

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

    public static func recordUploadTraffic(
        provider: String = "qiniu",
        host: String,
        scene: String? = nil,
        fileCategory: ZWBMonitorFileCategory = .unknown,
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

    public static func recordImageLoad(
        url: URL?,
        scene: String? = nil,
        cacheType: ZWBMonitorResourceCacheType,
        success: Bool,
        error: String? = nil
    ) {
        shared.recordImageLoad(url: url, scene: scene, cacheType: cacheType, success: success, error: error)
    }

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
        let classification = classify(urlString: trace.url, host: URL(string: trace.url)?.host)
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
                direction: ZWBMonitorTrafficDirection.both.rawValue,
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
            URLProtocol.registerClass(ZWBMonitorURLProtocol.self)
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
        let classification = classify(urlString: url?.absoluteString, host: host, fallbackName: name, fallbackCategory: category)
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

    private func recordImageLoad(url: URL?, scene: String?, cacheType: ZWBMonitorResourceCacheType, success: Bool, error: String?) {
        guard config.enabledModules.contains(.traffic) else { return }
        let record = ZWBMonitorSnapshot.ImageLoadRecord(
            url: url?.absoluteString,
            host: url?.host,
            scene: scene,
            cacheType: cacheType.rawValue,
            success: success,
            error: error,
            time: Self.dateFormatter.string(from: Date())
        )
        lock.lock()
        imageLoadRecords.append(record)
        if imageLoadRecords.count > 200 {
            imageLoadRecords.removeFirst(imageLoadRecords.count - 200)
        }
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
        fallbackName: String? = nil,
        fallbackCategory: ZWBMonitorTrafficCategory = .unclassified
    ) -> (name: String, category: ZWBMonitorTrafficCategory, hosts: [String], host: String?) {
        let host = explicitHost ?? urlString.flatMap { URL(string: $0)?.host }
        if let host {
            for rule in config.trafficRules where rule.hosts.contains(where: { matches(host: host, ruleHost: $0) }) {
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

    private func matches(host: String, ruleHost: String) -> Bool {
        let host = host.lowercased()
        let ruleHost = ruleHost.lowercased()
        return host == ruleHost || host.hasSuffix("." + ruleHost)
    }

    private func makeTrafficInfo() -> ZWBMonitorSnapshot.TrafficInfo {
        lock.lock()
        let copiedRecords = trafficRecords
        let copiedImageLoads = imageLoadRecords
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

        let imageLoads = ZWBMonitorSnapshot.ImageLoadInfo(
            displayCount: copiedImageLoads.filter { $0.success }.count,
            networkLoadCount: copiedImageLoads.filter { $0.success && $0.cacheType == ZWBMonitorResourceCacheType.none.rawValue }.count,
            memoryCacheHitCount: copiedImageLoads.filter { $0.success && $0.cacheType == ZWBMonitorResourceCacheType.memory.rawValue }.count,
            diskCacheHitCount: copiedImageLoads.filter { $0.success && $0.cacheType == ZWBMonitorResourceCacheType.disk.rawValue }.count,
            failureCount: copiedImageLoads.filter { !$0.success }.count,
            records: Array(copiedImageLoads.suffix(50))
        )

        return ZWBMonitorSnapshot.TrafficInfo(
            totalUploadBytes: totalUpload,
            totalDownloadBytes: totalDownload,
            totalUploadMB: bytesToMB(totalUpload),
            totalDownloadMB: bytesToMB(totalDownload),
            groups: grouped.values.sorted { $0.downloadBytes + $0.uploadBytes > $1.downloadBytes + $1.uploadBytes },
            recentRecords: Array(copiedRecords.suffix(80)),
            imageLoads: imageLoads
        )
    }

    private func emptyTrafficInfo() -> ZWBMonitorSnapshot.TrafficInfo {
        ZWBMonitorSnapshot.TrafficInfo(
            totalUploadBytes: 0,
            totalDownloadBytes: 0,
            totalUploadMB: 0,
            totalDownloadMB: 0,
            groups: [],
            recentRecords: [],
            imageLoads: ZWBMonitorSnapshot.ImageLoadInfo(
                displayCount: 0,
                networkLoadCount: 0,
                memoryCacheHitCount: 0,
                diskCacheHitCount: 0,
                failureCount: 0,
                records: []
            )
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
