import Foundation
import UIKit
import Network
import Darwin

final class ZWBMonitorRuntimeCollector {
    private let startedAt = Date()

    func cpuUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0 }

        var total: Double = 0
        for index in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let infoResult = withUnsafeMutablePointer(to: &threadInfo) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if infoResult == KERN_SUCCESS, threadInfo.flags & TH_FLAGS_IDLE == 0 {
                total += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), size)
        return min(max(total, 0), 1000)
    }

    func memoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    func launchTime() -> Double {
        Date().timeIntervalSince(startedAt)
    }
}

final class ZWBMonitorFPSCollector {
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount = 0
    private(set) var currentFPS = 0
    private(set) var averageFPS = 0
    private(set) var minimumFPS = Int.max
    private var samples: [Int] = []

    func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        frameCount += 1
        let delta = link.timestamp - lastTimestamp
        guard delta >= 1 else { return }

        let fps = Int(round(Double(frameCount) / delta))
        currentFPS = fps
        minimumFPS = min(minimumFPS, fps)
        samples.append(fps)
        if samples.count > 60 {
            samples.removeFirst(samples.count - 60)
        }
        averageFPS = samples.isEmpty ? fps : Int(round(Double(samples.reduce(0, +)) / Double(samples.count)))
        frameCount = 0
        lastTimestamp = link.timestamp
    }
}

final class ZWBMonitorNetworkCollector {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.zwb.monitor.network")
    private(set) var type = "unknown"
    private(set) var isExpensive = false
    private(set) var isConstrained = false

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.isExpensive = path.isExpensive
            if #available(iOS 13.0, *) {
                self.isConstrained = path.isConstrained
            }
            if path.usesInterfaceType(.wifi) {
                self.type = "WiFi"
            } else if path.usesInterfaceType(.cellular) {
                self.type = "Cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                self.type = "Ethernet"
            } else if path.status == .satisfied {
                self.type = "Other"
            } else {
                self.type = "Offline"
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

enum ZWBMonitorDeviceCollector {
    static func appInfo() -> ZWBMonitorSnapshot.AppInfo {
        let bundle = Bundle.main
        return ZWBMonitorSnapshot.AppInfo(
            bundleId: bundle.bundleIdentifier ?? "unknown",
            name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
    }

    static func deviceInfo() -> ZWBMonitorSnapshot.DeviceInfo {
        let device = UIDevice.current
        return ZWBMonitorSnapshot.DeviceInfo(
            model: machineModel(),
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            language: Locale.preferredLanguages.first ?? "unknown",
            region: currentRegionIdentifier(),
            timeZone: TimeZone.current.identifier
        )
    }

    static func batteryInfo() -> ZWBMonitorSnapshot.BatteryInfo {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state: String
        switch UIDevice.current.batteryState {
        case .charging:
            state = "charging"
        case .full:
            state = "full"
        case .unplugged:
            state = "unplugged"
        default:
            state = "unknown"
        }

        let level = UIDevice.current.batteryLevel >= 0 ? Int(UIDevice.current.batteryLevel * 100) : -1
        return ZWBMonitorSnapshot.BatteryInfo(
            level: level,
            charging: UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full,
            state: state,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    static func thermalInfo() -> ZWBMonitorSnapshot.ThermalInfo {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            state = "nominal"
        case .fair:
            state = "fair"
        case .serious:
            state = "serious"
        case .critical:
            state = "critical"
        @unknown default:
            state = "unknown"
        }
        return ZWBMonitorSnapshot.ThermalInfo(state: state)
    }

    static func diskInfo() -> ZWBMonitorSnapshot.DiskInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Double(values?.volumeTotalCapacity ?? 0) / 1024.0 / 1024.0 / 1024.0
        let free = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1024.0 / 1024.0 / 1024.0
        return ZWBMonitorSnapshot.DiskInfo(totalGB: rounded(total), freeGB: rounded(free), usedGB: rounded(max(total - free, 0)))
    }

    private static func machineModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, child in
            guard let value = child.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
    }

    private static func currentRegionIdentifier() -> String {
        if #available(iOS 16.0, *) {
            return Locale.current.region?.identifier ?? "unknown"
        } else {
            return Locale.current.regionCode ?? "unknown"
        }
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
