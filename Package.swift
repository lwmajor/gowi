// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "gowi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gowi", targets: ["Gowi"])
    ],
    targets: [
        .executableTarget(
            name: "Gowi",
            path: "Sources/Gowi"
        ),
        .testTarget(
            name: "GowiTests",
            dependencies: ["Gowi"],
            path: "Tests/GowiTests"
        )
    ]
)
