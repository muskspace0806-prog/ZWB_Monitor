import Foundation
import UIKit

final class ZWBMonitorPageTracker {
    static let shared = ZWBMonitorPageTracker()
    private static var installed = false
    private let lock = NSLock()
    private var current: String?
    private var previous: String?
    private var appearedAt: Date?

    static func install() {
        guard !installed else { return }
        installed = true
        UIViewController.zwb_swizzleAppearMethods()
    }

    func trackAppear(_ viewController: UIViewController) {
        let name = String(describing: type(of: viewController))
        lock.lock()
        previous = current
        current = name
        appearedAt = Date()
        lock.unlock()
        ZWBMonitor.record(event: "PageAppear", attributes: ["page": name])
    }

    func currentPageInfo() -> ZWBMonitorSnapshot.PageInfo {
        lock.lock()
        let info = ZWBMonitorSnapshot.PageInfo(
            current: current,
            previous: previous,
            stayDuration: appearedAt.map { (Date().timeIntervalSince($0) * 100).rounded() / 100 }
        )
        lock.unlock()
        return info
    }
}

private extension UIViewController {
    static func zwb_swizzleAppearMethods() {
        let original = class_getInstanceMethod(UIViewController.self, #selector(viewDidAppear(_:)))
        let swizzled = class_getInstanceMethod(UIViewController.self, #selector(zwb_monitor_viewDidAppear(_:)))
        if let original, let swizzled {
            method_exchangeImplementations(original, swizzled)
        }
    }

    @objc func zwb_monitor_viewDidAppear(_ animated: Bool) {
        zwb_monitor_viewDidAppear(animated)
        ZWBMonitorPageTracker.shared.trackAppear(self)
    }
}

public final class ZWBMonitorURLProtocol: URLProtocol {
    private static let handledKey = "ZWBMonitorURLProtocolHandled"
    private var dataTask: URLSessionDataTask?
    private var startedAt: Date?

    public override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        startedAt = Date()
        let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)
        let contentLength = mutable.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init)
        let requestBytes = mutable.httpBody?.count ?? contentLength ?? 0

        dataTask = URLSession.shared.dataTask(with: mutable as URLRequest) { [weak self] data, response, error in
            guard let self else { return }
            let duration = Date().timeIntervalSince(self.startedAt ?? Date()) * 1000
            let httpResponse = response as? HTTPURLResponse
            let trace = ZWBMonitorSnapshot.NetworkTrace(
                url: self.request.url?.absoluteString ?? "",
                method: self.request.httpMethod ?? "GET",
                statusCode: httpResponse?.statusCode,
                durationMS: (duration * 100).rounded() / 100,
                requestBytes: requestBytes,
                responseBytes: data?.count ?? 0,
                trafficGroup: nil,
                trafficCategory: nil,
                error: error?.localizedDescription,
                time: ISO8601DateFormatter().string(from: Date())
            )
            ZWBMonitor.shared.recordNetworkTrace(trace)

            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        dataTask?.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
    }
}

final class ZWBMonitorURLProtocolInstaller {
    private static var installed = false
    private static let lock = NSLock()

    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true

        URLProtocol.registerClass(ZWBMonitorURLProtocol.self)
        URLSessionConfiguration.zwb_swizzleConfigurationFactory()
    }
}

private extension URLSessionConfiguration {
    static func zwb_swizzleConfigurationFactory() {
        swizzleClassMethod(
            originalSelector: #selector(getter: URLSessionConfiguration.default),
            swizzledSelector: #selector(URLSessionConfiguration.zwb_monitor_default)
        )
        swizzleClassMethod(
            originalSelector: #selector(getter: URLSessionConfiguration.ephemeral),
            swizzledSelector: #selector(URLSessionConfiguration.zwb_monitor_ephemeral)
        )
    }

    @objc class func zwb_monitor_default() -> URLSessionConfiguration {
        let configuration = zwb_monitor_default()
        configuration.zwb_insertMonitorURLProtocol()
        return configuration
    }

    @objc class func zwb_monitor_ephemeral() -> URLSessionConfiguration {
        let configuration = zwb_monitor_ephemeral()
        configuration.zwb_insertMonitorURLProtocol()
        return configuration
    }

    private static func swizzleClassMethod(originalSelector: Selector, swizzledSelector: Selector) {
        guard
            let metaClass = object_getClass(URLSessionConfiguration.self),
            let originalMethod = class_getClassMethod(URLSessionConfiguration.self, originalSelector),
            let swizzledMethod = class_getClassMethod(URLSessionConfiguration.self, swizzledSelector)
        else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
        _ = metaClass
    }

    func zwb_insertMonitorURLProtocol() {
        let existing = protocolClasses ?? []
        guard !existing.contains(where: { $0 == ZWBMonitorURLProtocol.self }) else { return }
        protocolClasses = [ZWBMonitorURLProtocol.self] + existing
    }
}
