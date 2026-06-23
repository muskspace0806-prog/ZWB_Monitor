import Foundation

#if canImport(Qiniu)
import Qiniu
#endif

public enum ZWBMonitorQiniuUploadError: Error {
    case sdkUnavailable
    case invalidTokenResponse
    case uploadFailed(String)
    case indexCallbackFailed(String)
}

public final class ZWBMonitorQiniuHTTPTokenProvider: ZWBMonitorQiniuTokenProviding {
    private let endpoint: URL
    private let headers: [String: String]

    public init(endpoint: URL, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.headers = headers
    }

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

public final class ZWBMonitorQiniuUploader: ZWBMonitorUploading {
    private let config: ZWBMonitorQiniuUploadConfig

    public init(config: ZWBMonitorQiniuUploadConfig) {
        self.config = config
    }

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
