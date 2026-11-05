// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HotSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CSensors",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "HotSwitch",
            dependencies: ["CSensors"],
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("ServiceManagement")]
        ),
    ]
)
