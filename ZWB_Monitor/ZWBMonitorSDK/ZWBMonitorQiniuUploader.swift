import Foundation

#if canImport(Qiniu)
import Qiniu
#endif

/// 七牛报告上传错误。
public enum ZWBMonitorQiniuUploadError: Error {
    /// 当前工程没有链接 Qiniu SDK。CocoaPods 接入 `ZWB_Monitor` 时会自动拉取 Qiniu。
    case sdkUnavailable
    /// token 接口没有返回 `{ "token": "..." }`。
    case invalidTokenResponse
    /// 七牛上传失败。
    case uploadFailed(String)
    /// 上传成功后通知业务服务器维护索引失败。
    case indexCallbackFailed(String)
}

/// SDK 内置的七牛 token 获取器。
/// 它会向你的业务服务器 POST 报告信息和 objectKey，并期望服务端返回 `{ "token": "七牛上传凭证" }`。
public final class ZWBMonitorQiniuHTTPTokenProvider: ZWBMonitorQiniuTokenProviding {
    /// 业务服务器签发七牛 upload token 的接口。
    private let endpoint: URL
    /// 请求头，例如鉴权 token。
    private let headers: [String: String]

    /// 创建 HTTP token 获取器。
    /// - Parameters:
    ///   - endpoint: 你的业务服务器接口，不是七牛官方接口。
    ///   - headers: 业务鉴权头。
    public init(endpoint: URL, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.headers = headers
    }

    /// 向业务服务器请求七牛 upload token。
    public func requestUploadToken(
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        objectKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body: [String: Any] = [
            "objectKey": objectKey,
            "reportId": snapshot.id,
            "fileName": report.fileName,
            "format": report.format.rawValue,
            "event": snapshot.event,
            "level": snapshot.level.rawValue,
            "time": snapshot.time,
            "app": [
                "bundleId": snapshot.app.bundleId,
                "name": snapshot.app.name,
                "version": snapshot.app.version,
                "build": snapshot.app.build
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String,
                  !token.isEmpty else {
                completion(.failure(ZWBMonitorQiniuUploadError.invalidTokenResponse))
                return
            }
            completion(.success(token))
        }.resume()
    }
}

/// 七牛报告上传器。通常不需要业务手动创建，配置 `ZWBMonitorConfig.qiniuUpload` 后预警会自动触发。
public final class ZWBMonitorQiniuUploader: ZWBMonitorUploading {
    private let config: ZWBMonitorQiniuUploadConfig

    /// 创建七牛报告上传器。
    public init(config: ZWBMonitorQiniuUploadConfig) {
        self.config = config
    }

    /// 上传一份预警报告到七牛。
    public func upload(
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void
    ) {
        let objectKey = normalizedObjectKey(for: report)
        config.tokenProvider.requestUploadToken(report: report, snapshot: snapshot, objectKey: objectKey) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let token):
                self.uploadToQiniu(token: token, objectKey: objectKey, report: report, snapshot: snapshot, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func uploadToQiniu(
        token: String,
        objectKey: String,
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void
    ) {
        #if canImport(Qiniu)
        let startedAt = Date()
        let manager: QNUploadManager? = QNUploadManager()
        guard let manager = manager else {
            completion(.failure(ZWBMonitorQiniuUploadError.uploadFailed("QNUploadManager 初始化失败")))
            return
        }
        manager.put(report.content, key: objectKey, token: token, complete: { [weak self] info, key, _ in
            guard let self else { return }
            let isOK = info?.isOK == true
            let errorMessage = info?.error?.localizedDescription
            // 报告上传本身也是上行流量，归类到 monitor_report 场景，便于后台排查 SDK 自身上传成本。
            ZWBMonitor.recordQiniuUpload(
                host: self.config.uploadHost,
                scene: "monitor_report",
                bytes: Int64(report.content.count),
                duration: Date().timeIntervalSince(startedAt),
                success: isOK,
                error: errorMessage
            )

            guard isOK else {
                completion(.failure(ZWBMonitorQiniuUploadError.uploadFailed(errorMessage ?? "七牛上传失败")))
                return
            }

            let result = ZWBMonitorUploadResult(
                reportId: snapshot.id,
                remoteURL: self.remoteURL(for: key ?? objectKey),
                objectKey: key ?? objectKey
            )
            self.notifyIndexIfNeeded(result: result, report: report, snapshot: snapshot, completion: completion)
        }, option: nil)
        #else
        completion(.failure(ZWBMonitorQiniuUploadError.sdkUnavailable))
        #endif
    }

    private func notifyIndexIfNeeded(
        result: ZWBMonitorUploadResult,
        report: ZWBMonitorReportFile,
        snapshot: ZWBMonitorSnapshot,
        completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void
    ) {
        guard let callback = config.indexCallback else {
            completion(.success(result))
            return
        }

        // 回调业务服务器维护 index.json，让静态 HTML 后台能发现新报告。
        var request = URLRequest(url: callback.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        callback.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let body: [String: Any] = [
            "id": snapshot.id,
            "event": snapshot.event,
            "level": snapshot.level.rawValue,
            "time": snapshot.time,
            "fileName": report.fileName,
            "format": report.format.rawValue,
            "objectKey": result.objectKey ?? "",
            "url": result.remoteURL?.absoluteString ?? "",
            "app": [
                "bundleId": snapshot.app.bundleId,
                "name": snapshot.app.name,
                "version": snapshot.app.version,
                "build": snapshot.app.build
            ],
            "device": [
                "model": snapshot.device.model,
                "systemName": snapshot.device.systemName,
                "systemVersion": snapshot.device.systemVersion
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(statusCode) else {
                completion(.failure(ZWBMonitorQiniuUploadError.indexCallbackFailed("HTTP \(statusCode)")))
                return
            }
            completion(.success(result))
        }.resume()
    }

    private func normalizedObjectKey(for report: ZWBMonitorReportFile) -> String {
        let prefix = trimSlashes(config.keyPrefix)
        let rawKey = trimLeadingSlash(report.suggestedObjectKey ?? report.fileName)
        guard !prefix.isEmpty else { return rawKey }
        if rawKey == prefix || rawKey.hasPrefix(prefix + "/") {
            return rawKey
        }
        return prefix + "/" + rawKey
    }

    private func remoteURL(for objectKey: String) -> URL? {
        guard let baseURL = config.cdnBaseURL else { return nil }
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/" + trimLeadingSlash(objectKey))
    }

    private func trimSlashes(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func trimLeadingSlash(_ value: String) -> String {
        var result = value
        while result.hasPrefix("/") {
            result.removeFirst()
        }
        return result
    }
}
