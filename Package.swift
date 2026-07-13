// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoFlash",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AutoFlash", targets: ["AutoFlash"])
    ],
    targets: [
        .executableTarget(
            name: "AutoFlash",
            path: "Sources/AutoFlash",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
