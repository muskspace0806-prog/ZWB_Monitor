import Foundation
import CryptoKit

final class ZWBMonitorHTTPUploader: ZWBMonitorUploading {
    private let config: ZWBMonitorHTTPUploadConfig

    init(config: ZWBMonitorHTTPUploadConfig) {
        self.config = config
    }

    func upload(report: ZWBMonitorReportFile, snapshot: ZWBMonitorSnapshot, completion: @escaping (Result<ZWBMonitorUploadResult, Error>) -> Void) {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        config.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body: [String: Any] = [
            "directory": config.directory ?? "",
            "fileName": report.fileName,
            "format": report.format.rawValue,
            "content": String(data: report.content, encoding: .utf8) ?? "",
            "snapshotId": snapshot.id,
            "event": snapshot.event,
            "time": snapshot.time,
            "app": [
                "bundleId": snapshot.app.bundleId,
                "name": snapshot.app.name,
                "version": snapshot.app.version,
                "build": snapshot.app.build
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let remoteURL = (response as? HTTPURLResponse)?.url
            let reportId: String?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                reportId = json["reportId"] as? String
            } else {
                reportId = nil
            }
            completion(.success(ZWBMonitorUploadResult(reportId: reportId, remoteURL: remoteURL)))
        }.resume()
    }
}

final class ZWBDingTalkNotifier: ZWBMonitorNotifying {
    private let config: ZWBDingTalkConfig

    init(config: ZWBDingTalkConfig) {
        self.config = config
    }

    func notify(snapshot: ZWBMonitorSnapshot, report: ZWBMonitorReportFile?, completion: @escaping (Result<Void, Error>) -> Void) {
        var url = config.webhook
        if let secret = config.secret, !secret.isEmpty {
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            let stringToSign = "\(timestamp)\n\(secret)"
            let key = SymmetricKey(data: Data(secret.utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            let sign = Data(signature).base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var query = components?.queryItems ?? []
            query.append(URLQueryItem(name: "timestamp", value: "\(timestamp)"))
            query.append(URLQueryItem(name: "sign", value: sign))
            components?.queryItems = query
            url = components?.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let text = """
        【ZWBMonitor 性能异常】
        事件：\(snapshot.event)
        App：\(snapshot.app.name) \(snapshot.app.version)(\(snapshot.app.build))
        设备：\(snapshot.device.model)
        页面：\(snapshot.page.current ?? "unknown")
        CPU：\(snapshot.runtime.cpu)%
        内存：\(snapshot.runtime.memoryMB)MB
        FPS：\(snapshot.runtime.fps)
        网络：\(snapshot.network.type)
        磁盘剩余：\(snapshot.disk.freeGB)GB
        时间：\(snapshot.time)
        """
        let body: [String: Any] = [
            "msgtype": "text",
            "text": ["content": text]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }.resume()
    }
}

