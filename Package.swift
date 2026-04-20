// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BarTimeTracker",
    platforms: [.macOS(.v13)],
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
            path: "Sources/BarTimeTracker"
        ),
        .testTarget(
            name: "BarTimeTrackerTests",
            dependencies: ["BarTimeTrackerCore"],
            path: "Tests/BarTimeTrackerTests"
        ),
    ]
)
