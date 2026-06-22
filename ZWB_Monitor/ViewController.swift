//
//  ViewController.swift
//  ZWB_Monitor
//
//  Created by hule on 2026/6/22.
//

import UIKit

class ViewController: UIViewController {
    private let textView = UITextView()
    private let refreshButton = UIButton(type: .system)
    private let eventButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ZWB Monitor Demo"
        view.backgroundColor = .systemBackground
        buildUI()
        refreshSnapshot()
    }

    private func buildUI() {
        let titleLabel = UILabel()
        titleLabel.text = "ZWB Monitor"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.text = "点击刷新即可查看 SDK 当前收集到的性能快照。"
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        refreshButton.setTitle("刷新快照", for: .normal)
        refreshButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        refreshButton.addTarget(self, action: #selector(refreshSnapshot), for: .touchUpInside)

        eventButton.setTitle("记录一条事件", for: .normal)
        eventButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        eventButton.addTarget(self, action: #selector(recordDemoEvent), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [refreshButton, eventButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.isEditable = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, buttonStack, textView])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            refreshButton.heightAnchor.constraint(equalToConstant: 44),
            eventButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func refreshSnapshot() {
        let snapshot = ZWBMonitor.currentSnapshot(reason: "demo_button")
        textView.text = makeReadableText(from: snapshot)
    }

    @objc private func recordDemoEvent() {
        ZWBMonitor.record(event: "DemoButtonTapped", attributes: ["screen": "ViewController"])
        refreshSnapshot()
    }

    private func makeReadableText(from snapshot: ZWBMonitorSnapshot) -> String {
        let eventNames = snapshot.eventHistory.map { "  - \(displayName(forEvent: $0.name))  \($0.time)" }.joined(separator: "\n")
        let networkNames = snapshot.networkHistory.suffix(5).map {
            "  - \($0.method) \($0.url)\n    状态码：\($0.statusCode.map(String.init) ?? "-")，耗时：\(format($0.durationMS)) ms，响应大小：\($0.responseBytes) B"
        }.joined(separator: "\n")
        let trafficGroups = snapshot.traffic.groups.map {
            "  - \($0.name)：上传 \(format($0.uploadMB)) MB，下载 \(format($0.downloadMB)) MB，请求 \($0.requestCount) 次，失败 \($0.failureCount) 次"
        }.joined(separator: "\n")

        return """
        【基础信息】
        报告 ID：\(snapshot.id)
        触发事件：\(displayName(forEvent: snapshot.event))
        告警等级：\(displayName(forLevel: snapshot.level.rawValue))
        采集时间：\(snapshot.time)

        【App 信息】
        App 名称：\(snapshot.app.name)
        Bundle ID：\(snapshot.app.bundleId)
        版本号：\(snapshot.app.version)
        Build：\(snapshot.app.build)

        【设备信息】
        设备型号：\(snapshot.device.model)
        系统版本：\(snapshot.device.systemName) \(snapshot.device.systemVersion)
        语言：\(snapshot.device.language)
        地区：\(snapshot.device.region)
        时区：\(snapshot.device.timeZone)

        【运行状态】
        CPU 占用：\(format(snapshot.runtime.cpu))%
        内存占用：\(format(snapshot.runtime.memoryMB)) MB
        当前 FPS：\(snapshot.runtime.fps)
        平均 FPS：\(snapshot.runtime.averageFPS)
        最低 FPS：\(snapshot.runtime.minimumFPS)
        启动后时长：\(format(snapshot.runtime.launchTime ?? 0)) 秒

        【网络 / 存储】
        网络类型：\(displayName(forNetwork: snapshot.network.type))
        低数据模式：\(snapshot.network.isConstrained ? "是" : "否")
        昂贵网络：\(snapshot.network.isExpensive ? "是" : "否")
        总上行流量：\(format(snapshot.traffic.totalUploadMB)) MB
        总下载流量：\(format(snapshot.traffic.totalDownloadMB)) MB
        磁盘总空间：\(format(snapshot.disk.totalGB)) GB
        磁盘剩余：\(format(snapshot.disk.freeGB)) GB
        磁盘已用：\(format(snapshot.disk.usedGB)) GB

        【流量分组】
        \(trafficGroups.isEmpty ? "暂无流量记录" : trafficGroups)

        【图片加载 / 缓存】
        展示成功次数：\(snapshot.traffic.imageLoads.displayCount)
        网络加载次数：\(snapshot.traffic.imageLoads.networkLoadCount)
        内存缓存命中：\(snapshot.traffic.imageLoads.memoryCacheHitCount)
        磁盘缓存命中：\(snapshot.traffic.imageLoads.diskCacheHitCount)
        加载失败次数：\(snapshot.traffic.imageLoads.failureCount)

        【电量 / 温度】
        电量：\(snapshot.battery.level)%
        充电状态：\(displayName(forBattery: snapshot.battery.state))
        是否充电：\(snapshot.battery.charging ? "是" : "否")
        低电量模式：\(snapshot.battery.lowPowerMode ? "是" : "否")
        温度状态：\(displayName(forThermal: snapshot.thermal.state))

        【页面】
        当前页面：\(snapshot.page.current ?? "未知")
        上一个页面：\(snapshot.page.previous ?? "未知")
        停留时长：\(format(snapshot.page.stayDuration ?? 0)) 秒

        【计数器】
        Socket 重连次数：\(snapshot.counters.socketReconnects)
        上传失败次数：\(snapshot.counters.uploadFailures)
        API 失败次数：\(snapshot.counters.apiFailures)

        【事件记录】
        \(eventNames.isEmpty ? "暂无事件" : eventNames)

        【最近网络请求】
        \(networkNames.isEmpty ? "暂无网络请求记录" : networkNames)
        """
    }

    private func displayName(forEvent event: String) -> String {
        [
            "manual": "手动采集",
            "demo_button": "Demo 按钮采集",
            "sample": "定时采样",
            "high_memory": "内存过高",
            "high_cpu": "CPU 过高",
            "low_fps": "FPS 过低",
            "thermal_serious": "设备温度严重",
            "thermal_critical": "设备温度危险",
            "low_disk": "磁盘空间不足",
            "socket_reconnect": "Socket 重连过多",
            "upload_failure": "上传失败过多",
            "api_failure": "API 失败过多",
            "ZWBMonitorStarted": "监控已启动",
            "PageAppear": "页面展示",
            "DemoButtonTapped": "Demo 按钮点击"
        ][event] ?? event
    }

    private func displayName(forLevel level: String) -> String {
        [
            "info": "普通信息",
            "warning": "警告",
            "critical": "严重"
        ][level] ?? level
    }

    private func displayName(forNetwork network: String) -> String {
        [
            "WiFi": "无线网络",
            "Cellular": "蜂窝网络",
            "Ethernet": "有线网络",
            "Other": "其他网络",
            "Offline": "无网络",
            "unknown": "未知",
            "disabled": "未开启监控"
        ][network] ?? network
    }

    private func displayName(forBattery state: String) -> String {
        [
            "charging": "充电中",
            "full": "已充满",
            "unplugged": "未充电",
            "unknown": "未知",
            "disabled": "未开启监控"
        ][state] ?? state
    }

    private func displayName(forThermal state: String) -> String {
        [
            "nominal": "正常",
            "fair": "偏热",
            "serious": "严重发热",
            "critical": "危险发热",
            "unknown": "未知",
            "disabled": "未开启监控"
        ][state] ?? state
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
