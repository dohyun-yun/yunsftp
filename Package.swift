// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "yunsftp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "yunsftp",
            targets: ["yunsftp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "yunsftp",
            dependencies: [],
            path: "Sources/YunSFTP",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "YunSFTPTests",
            dependencies: ["yunsftp"],
            path: "Tests/YunSFTPTests"
        )
    ]
)
