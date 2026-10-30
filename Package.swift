// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "yunsftp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "yunsftp",
            targets: ["yunsftp"]
        )
    ],
    dependencies: [
        // Native SSH/SFTP engine (swift-nio-ssh based); the OpenSSH process transport remains as fallback.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.1")
    ],
    targets: [
        .executableTarget(
            name: "yunsftp",
            dependencies: [
                .product(name: "Citadel", package: "Citadel")
            ],
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
