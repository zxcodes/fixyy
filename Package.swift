// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Fixyy",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "FixyyCore",
            path: "Sources/Fixyy",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "Fixyy",
            dependencies: ["FixyyCore"],
            path: "Sources/FixyyApp"
        ),
        .executableTarget(
            name: "fixyy-fixtures",
            dependencies: ["FixyyCore"],
            path: "Sources/FixturesRunner"
        ),
        .executableTarget(
            name: "fixyy-check",
            dependencies: ["FixyyCore"],
            path: "Sources/FixyyCheck"
        ),
        .testTarget(
            name: "FixyyTests",
            dependencies: ["FixyyCore"],
            path: "Tests/FixyyTests"
        ),
    ]
)
