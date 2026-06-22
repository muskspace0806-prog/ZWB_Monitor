import Foundation

final class ZWBMonitorRuleEngine {
    struct Trigger {
        let event: String
        let level: ZWBMonitorEventLevel
    }

    private var cpuStartedAt: Date?
    private var fpsStartedAt: Date?
    private var lastTriggeredAt: [String: Date] = [:]

    func reset() {
        cpuStartedAt = nil
        fpsStartedAt = nil
        lastTriggeredAt.removeAll()
    }

    func evaluate(snapshot: ZWBMonitorSnapshot, thresholds: ZWBMonitorThresholds) -> Trigger? {
        if snapshot.runtime.memoryMB > thresholds.memoryMB {
            return allowed("high_memory", thresholds: thresholds).map { Trigger(event: $0, level: .warning) }
        }

        if snapshot.runtime.cpu > thresholds.cpuPercent {
            cpuStartedAt = cpuStartedAt ?? Date()
            if Date().timeIntervalSince(cpuStartedAt!) >= thresholds.cpuDuration {
                return allowed("high_cpu", thresholds: thresholds).map { Trigger(event: $0, level: .warning) }
            }
        } else {
            cpuStartedAt = nil
        }

        if snapshot.runtime.fps > 0, snapshot.runtime.fps < thresholds.fps {
            fpsStartedAt = fpsStartedAt ?? Date()
            if Date().timeIntervalSince(fpsStartedAt!) >= thresholds.fpsDuration {
                return allowed("low_fps", thresholds: thresholds).map { Trigger(event: $0, level: .warning) }
            }
        } else {
            fpsStartedAt = nil
        }

        if snapshot.thermal.state == "serious" || snapshot.thermal.state == "critical" {
            return allowed("thermal_\(snapshot.thermal.state)", thresholds: thresholds).map { Trigger(event: $0, level: .critical) }
        }

        if snapshot.disk.freeGB > 0, snapshot.disk.freeGB < thresholds.diskFreeGB {
            return allowed("low_disk", thresholds: thresholds).map { Trigger(event: $0, level: .warning) }
        }

        if snapshot.counters.socketReconnects >= thresholds.socketReconnectCount {
            return allowed("socket_reconnect", thresholds: thresholds).map { Trigger(event: $0, level: .warning) }
        }

        if snapshot.counters.uploadFailures >= thresholds.uploadFailureCount {
            return allowed("upload_failure", thresholds: thresholds).map { Trigger(event: $0, level: .warning) }
        }

        if snapshot.counters.apiFailures >= thresholds.apiFailureCount {
            return allowed("api_failure", thresholds: thresholds).map { Trigger(event: $0, level: .warning) }
        }

        return nil
    }

    private func allowed(_ event: String, thresholds: ZWBMonitorThresholds) -> String? {
        let now = Date()
        if let last = lastTriggeredAt[event], now.timeIntervalSince(last) < thresholds.triggerCooldown {
            return nil
        }
        lastTriggeredAt[event] = now
        return event
    }
}

final class ZWBMonitorReporter {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func makeReports(snapshot: ZWBMonitorSnapshot, formats: Set<ZWBMonitorReportFormat>, directory: URL) -> [ZWBMonitorReportFile] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return formats.compactMap { format in
            guard let data = makeContent(snapshot: snapshot, format: format) else { return nil }
            let fileName = "\(snapshot.event)_\(safeTime(snapshot.time))_\(snapshot.id).\(format.rawValue)"
            let localURL = directory.appendingPathComponent(fileName)
            try? data.write(to: localURL, options: .atomic)
            return ZWBMonitorReportFile(id: snapshot.id, fileName: fileName, format: format, content: data, localURL: localURL)
        }.sorted { $0.format.rawValue < $1.format.rawValue }
    }

    private func makeContent(snapshot: ZWBMonitorSnapshot, format: ZWBMonitorReportFormat) -> Data? {
        switch format {
        case .json:
            return try? encoder.encode(snapshot)
        case .txt:
            return text(snapshot).data(using: .utf8)
        case .xml:
            return xml(snapshot).data(using: .utf8)
        }
    }

    private func text(_ snapshot: ZWBMonitorSnapshot) -> String {
        """
        ZWB Monitor Report
        ID: \(snapshot.id)
        Event: \(snapshot.event)
        Level: \(snapshot.level.rawValue)
        Time: \(snapshot.time)
        App: \(snapshot.app.name) \(snapshot.app.version)(\(snapshot.app.build))
        Bundle: \(snapshot.app.bundleId)
        Device: \(snapshot.device.model), \(snapshot.device.systemName) \(snapshot.device.systemVersion)
        Page: \(snapshot.page.current ?? "unknown")
        CPU: \(snapshot.runtime.cpu)%
        Memory: \(snapshot.runtime.memoryMB)MB
        FPS: \(snapshot.runtime.fps)
        Network: \(snapshot.network.type)
        Disk Free: \(snapshot.disk.freeGB)GB
        Battery: \(snapshot.battery.level)%, \(snapshot.battery.state)
        Thermal: \(snapshot.thermal.state)
        Socket Reconnects: \(snapshot.counters.socketReconnects)
        Upload Failures: \(snapshot.counters.uploadFailures)
        API Failures: \(snapshot.counters.apiFailures)
        """
    }

    private func xml(_ snapshot: ZWBMonitorSnapshot) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <zwbMonitorReport id="\(escape(snapshot.id))">
          <event>\(escape(snapshot.event))</event>
          <level>\(escape(snapshot.level.rawValue))</level>
          <time>\(escape(snapshot.time))</time>
          <app bundleId="\(escape(snapshot.app.bundleId))" version="\(escape(snapshot.app.version))" build="\(escape(snapshot.app.build))">\(escape(snapshot.app.name))</app>
          <device model="\(escape(snapshot.device.model))" system="\(escape(snapshot.device.systemName))" version="\(escape(snapshot.device.systemVersion))" />
          <runtime cpu="\(snapshot.runtime.cpu)" memoryMB="\(snapshot.runtime.memoryMB)" fps="\(snapshot.runtime.fps)" />
          <network type="\(escape(snapshot.network.type))" />
          <disk totalGB="\(snapshot.disk.totalGB)" freeGB="\(snapshot.disk.freeGB)" usedGB="\(snapshot.disk.usedGB)" />
          <battery level="\(snapshot.battery.level)" state="\(escape(snapshot.battery.state))" charging="\(snapshot.battery.charging)" />
          <thermal state="\(escape(snapshot.thermal.state))" />
          <page current="\(escape(snapshot.page.current ?? ""))" previous="\(escape(snapshot.page.previous ?? ""))" />
        </zwbMonitorReport>
        """
    }

    private func safeTime(_ time: String) -> String {
        time.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

