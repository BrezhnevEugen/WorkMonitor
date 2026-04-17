// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorkMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WorkMonitor",
            path: "WorkMonitor",
            exclude: ["Info.plist"]
        )
    ]
)
