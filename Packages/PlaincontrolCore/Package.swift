// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlaincontrolCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PlaincontrolCore", targets: ["PlaincontrolCore"])
    ],
    targets: [
        .target(name: "PlaincontrolCore"),
        .testTarget(name: "PlaincontrolCoreTests", dependencies: ["PlaincontrolCore"]),
    ]
)
