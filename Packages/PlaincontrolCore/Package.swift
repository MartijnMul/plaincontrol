// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlaincontrolCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PlaincontrolCore", targets: ["PlaincontrolCore"]),
        .executable(name: "plaincontrol-hook", targets: ["plaincontrol-hook"]),
    ],
    targets: [
        .target(name: "PlaincontrolCore"),
        .executableTarget(name: "plaincontrol-hook", dependencies: ["PlaincontrolCore"]),
        .testTarget(name: "PlaincontrolCoreTests", dependencies: ["PlaincontrolCore"]),
    ]
)
