// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "300KTimer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "300KTimer", targets: ["TimerApp"])],
    targets: [
        .target(name: "TimerCore"),
        .executableTarget(name: "TimerApp", dependencies: ["TimerCore"]),
        .executableTarget(name: "TimerCoreChecks", dependencies: ["TimerCore"], path: "Tests/TimerCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
