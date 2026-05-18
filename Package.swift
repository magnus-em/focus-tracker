// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Focus",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "FocusCore"),
    ],
    targets: [
        .executableTarget(
            name: "Focus",
            dependencies: [
                .product(name: "FocusCore", package: "FocusCore"),
            ],
            path: "Sources"
        )
    ]
)
