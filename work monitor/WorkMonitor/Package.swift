// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorkMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "WorkMonitorCore",
            path: "WorkMonitorCore/Sources/WorkMonitorCore"
        ),
        .executableTarget(
            name: "WorkMonitor",
            dependencies: ["WorkMonitorCore"],
            path: "WorkMonitor",
            exclude: ["Info.plist", "WorkMonitor.entitlements"]
        ),
        .testTarget(
            name: "WorkMonitorCoreTests",
            dependencies: ["WorkMonitorCore"],
            path: "Tests/WorkMonitorCoreTests"
        )
    ]
)
