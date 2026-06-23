//
//  AppDelegate.swift
//  ZWB_Monitor
//
//  Created by hule on 2026/6/22.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        var config = ZWBMonitorConfig.default
        // Demo 同时生成三种报告格式。真实项目如果只给 HTML 后台用，通常保留 `.json` 即可。
        config.reportFormats = [.json, .txt, .xml]
        // Demo 使用默认阈值示例。真实项目可以按设备性能和业务容忍度调整。
        config.thresholds = ZWBMonitorThresholds(
            memoryMB: 800,
            cpuPercent: 80,
            cpuDuration: 30,
            fps: 20,
            fpsDuration: 10,
            diskFreeGB: 2,
            socketReconnectCount: 5,
            uploadFailureCount: 10,
            apiFailureCount: 20
        )
        // 最小接入只需要调用 start。若配置 qiniuUpload，达到预警会自动上传报告。
        ZWBMonitor.start(config: config)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
