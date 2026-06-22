// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ZWB_Monitor",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "ZWBMonitor",
            targets: ["ZWBMonitor"]
        )
    ],
    targets: [
        .target(
            name: "ZWBMonitor",
            path: "ZWB_Monitor/ZWBMonitorSDK"
        )
    ]
)

