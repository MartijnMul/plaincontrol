// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlaincontrolCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PlaincontrolCore", targets: ["PlaincontrolCore"]),
        .library(name: "PlaincontrolHooks", targets: ["PlaincontrolHooks"]),
        .executable(name: "plaincontrol-hook", targets: ["plaincontrol-hook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0")
    ],
    targets: [
        // What travels between Claude Code's hooks and the app; all the hook command needs.
        .target(name: "PlaincontrolHooks"),
        .target(name: "PlaincontrolCore", dependencies: ["PlaincontrolHooks", "Yams"]),
        .executableTarget(name: "plaincontrol-hook", dependencies: ["PlaincontrolHooks"]),
        .testTarget(name: "PlaincontrolHooksTests", dependencies: ["PlaincontrolHooks"]),
        .testTarget(name: "PlaincontrolCoreTests", dependencies: ["PlaincontrolCore", "PlaincontrolHooks"]),
    ]
)
