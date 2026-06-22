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
        config.reportFormats = [.json, .txt, .xml]
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
        ZWBMonitor.start(config: config)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}

