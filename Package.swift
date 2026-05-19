// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "open-maestri",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", "1.4.0"..<"2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", "2.6.0"..<"3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "open-maestri",
            dependencies: [
                "SwiftTerm",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: ["CLI"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "omaestri",
            dependencies: [],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "OpenMaestriTests",
            dependencies: ["open-maestri"],
            path: "Tests/OpenMaestriTests"
        ),
    ]
)
