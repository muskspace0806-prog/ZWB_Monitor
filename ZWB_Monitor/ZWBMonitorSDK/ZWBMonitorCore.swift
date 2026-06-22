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

    public static func makeMonitoredURLSessionConfiguration(_ base: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        let existing = base.protocolClasses ?? []
        if !existing.contains(where: { $0 == ZWBMonitorURLProtocol.self }) {
            base.protocolClasses = [ZWBMonitorURLProtocol.self] + existing
        }
        return base
    }

    func recordNetworkTrace(_ trace: ZWBMonitorSnapshot.NetworkTrace) {
        lock.lock()
        networkTraces.append(trace)
        if networkTraces.count > 50 {
            networkTraces.removeFirst(networkTraces.count - 50)
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

        let network = ZWBMonitorSnapshot.NetworkInfo(
            type: config.enabledModules.contains(.network) ? networkCollector.type : "disabled",
            isExpensive: config.enabledModules.contains(.network) ? networkCollector.isExpensive : false,
            isConstrained: config.enabledModules.contains(.network) ? networkCollector.isConstrained : false,
            uploadMB: nil,
            downloadMB: nil
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
}
