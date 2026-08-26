// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BarTimeTracker",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure calculation logic — no AppKit, testable
        .target(
            name: "BarTimeTrackerCore",
            path: "Sources/BarTimeTrackerCore"
        ),
        // The actual app — depends on Core
        .executableTarget(
            name: "BarTimeTracker",
            dependencies: ["BarTimeTrackerCore"],
            path: "Sources/BarTimeTracker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BarTimeTrackerTests",
            dependencies: ["BarTimeTrackerCore"],
            path: "Tests/BarTimeTrackerTests"
        ),
    ]
)
