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
    private let qiniuButton = UIButton(type: .system)

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

        qiniuButton.setTitle("模拟七牛报告上传", for: .normal)
        qiniuButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        qiniuButton.addTarget(self, action: #selector(simulateQiniuUpload), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [refreshButton, eventButton, qiniuButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 10
        buttonStack.distribution = .fill

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
            eventButton.heightAnchor.constraint(equalToConstant: 44),
            qiniuButton.heightAnchor.constraint(equalToConstant: 44)
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

    @objc private func simulateQiniuUpload() {
        qiniuButton.isEnabled = false
        // Demo 手动构造一份报告，用来演示“预警后自动上传七牛”的完整链路。
        // 真实项目不需要手动调用这里；配置 qiniuUpload 后 SDK 会在达到阈值时自动处理。
        let snapshot = ZWBMonitor.currentSnapshot(reason: "demo_qiniu_upload")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(snapshot)) ?? Data()
        let fileName = "demo_qiniu_upload_\(snapshot.id).json"
        let objectKey = "reports/\(String(snapshot.time.prefix(10)))/\(sanitizePathComponent(snapshot.app.bundleId))/\(fileName)"
        let report = ZWBMonitorReportFile(
            id: snapshot.id,
            fileName: fileName,
            format: .json,
            content: data,
            localURL: nil,
            suggestedObjectKey: objectKey
        )
        // Demo 使用假 tokenProvider，不会真正携带七牛凭证。
        // 接入真实项目时替换成 ZWBMonitorQiniuHTTPTokenProvider 或自己的 tokenProvider。
        let config = ZWBMonitorQiniuUploadConfig(
            tokenProvider: DemoQiniuTokenProvider(),
            keyPrefix: "monitor-reports",
            uploadHost: "upload.qiniup.com",
            cdnBaseURL: URL(string: "https://cdn.example.com"),
            indexCallback: nil
        )

        ZWBMonitorQiniuUploader(config: config).upload(report: report, snapshot: snapshot) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.qiniuButton.isEnabled = true
                self.textView.text = self.makeQiniuDemoText(snapshot: snapshot, report: report, result: result)
            }
        }
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
            "demo_qiniu_upload": "Demo 七牛报告上传",
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

    private func makeQiniuDemoText(
        snapshot: ZWBMonitorSnapshot,
        report: ZWBMonitorReportFile,
        result: Result<ZWBMonitorUploadResult, Error>
    ) -> String {
        let status: String
        switch result {
        case .success(let uploadResult):
            status = """
            上传结果：成功
            七牛对象路径：\(uploadResult.objectKey ?? report.suggestedObjectKey ?? report.fileName)
            CDN 地址：\(uploadResult.remoteURL?.absoluteString ?? "未配置")
            """
        case .failure(let error):
            status = """
            上传结果：未真正上传
            原因：\(displayName(forQiniuError: error))
            """
        }

        return """
        【七牛自动上传 Demo】
        这个按钮演示 SDK 内部封装的预警报告上传链路：
        1. 生成监控快照
        2. 生成 JSON 报告
        3. 生成唯一七牛对象路径
        4. 请求业务服务端签发上传 token
        5. 调用七牛 SDK 上传
        6. 可选回调业务服务端维护 index.json

        【本次模拟报告】
        报告 ID：\(snapshot.id)
        事件：\(displayName(forEvent: snapshot.event))
        文件名：\(report.fileName)
        报告大小：\(report.content.count) B
        建议对象路径：\(report.suggestedObjectKey ?? "-")
        实际对象前缀：monitor-reports
        上传域名：upload.qiniup.com
        CDN 示例：https://cdn.example.com

        【Token 接口约定】
        SDK 会 POST：
        objectKey / reportId / fileName / format / event / level / time / app

        服务端返回：
        { "token": "七牛上传凭证" }

        【索引回调】
        如果配置 indexCallback，上传成功后 SDK 会把报告 ID、App 信息、事件、等级、对象路径和 CDN URL 发给你的服务端。
        服务端再维护 index.json，HTML 后台就能从统一目录读取多个 App 的多份报告。

        【执行结果】
        \(status)

        提示：Demo 默认使用 mock token，不会携带真实七牛凭证。接入真实项目时，把 DemoQiniuTokenProvider 换成 ZWBMonitorQiniuHTTPTokenProvider 或你自己的 tokenProvider。
        """
    }

    private func displayName(forQiniuError error: Error) -> String {
        if let qiniuError = error as? ZWBMonitorQiniuUploadError {
            switch qiniuError {
            case .sdkUnavailable:
                return "当前 Demo 工程没有链接 Qiniu SDK；CocoaPods 接入后会自动拉取 Qiniu。"
            case .invalidTokenResponse:
                return "token 接口没有返回有效 token。"
            case .uploadFailed(let message):
                return message
            case .indexCallbackFailed(let message):
                return "索引回调失败：\(message)"
            }
        }
        return error.localizedDescription
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.map(String.init).joined()
    }
}

/// Demo 专用 tokenProvider：只返回假 token，用于说明接口形态。
/// 真实项目必须由业务服务器用七牛 AK/SK 签发 upload token，客户端不要保存 AK/SK。
private final class DemoQiniuTokenProvider: ZWBMonitorQiniuTokenProviding {
    func requestUploadToken(
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        objectKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        completion(.success("demo-upload-token-from-your-server"))
    }
}
