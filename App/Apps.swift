import AppKit
import UniformTypeIdentifiers

/// Finds the apps the launcher's actions open projects in.
enum Apps {
    /// Finder, which opens folders unless the user chose another app for them.
    static let finder = "com.apple.finder"

    /// The app for `setting`: a bundle identifier, an app name such as `Cursor`, or a path to
    /// an app.
    static func app(for setting: String) -> URL? {
        let fileManager = FileManager.default
        if setting.hasPrefix("/") || setting.hasPrefix("~") {
            let path = (setting as NSString).expandingTildeInPath
            return fileManager.fileExists(atPath: path) ? URL(filePath: path) : nil
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: setting) {
            return url
        }
        let name = setting.hasSuffix(".app") ? setting : setting + ".app"
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "~/Applications"]
        return folders.map { (($0 as NSString).expandingTildeInPath as NSString).appendingPathComponent(name) }
            .first { fileManager.fileExists(atPath: $0) }
            .map { URL(filePath: $0) }
    }

    /// The app with `bundleIdentifier`, if it is installed.
    static func app(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static func isInstalled(_ bundleIdentifier: String) -> Bool {
        app(bundleIdentifier: bundleIdentifier) != nil
    }

    /// The bundle identifiers of the apps macOS opens each kind of file with, by type
    /// identifier, leaving out kinds it has no app for.
    static func defaults(forTypes identifiers: [String]) -> [String] {
        identifiers.compactMap { identifier in
            UTType(identifier).flatMap(NSWorkspace.shared.urlForApplication(toOpen:)).flatMap(bundleIdentifier(of:))
        }
    }

    /// The app macOS opens folders with: Finder, unless the user chose another, such as Path
    /// Finder or ForkLift.
    static var folders: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: .folder)
    }

    /// The browser macOS opens web pages with.
    static var browser: URL? {
        URL(string: "http://localhost").flatMap(NSWorkspace.shared.urlForApplication(toOpen:))
    }

    /// The name the app with `bundleIdentifier` shows, or the identifier when it is not
    /// installed.
    static func name(ofApp bundleIdentifier: String) -> String {
        app(bundleIdentifier: bundleIdentifier).map(name(of:)) ?? bundleIdentifier
    }

    /// The name the app shows, such as `Visual Studio Code`.
    static func name(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// The bundle identifier of the app at `url`, if it has one.
    static func bundleIdentifier(of url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }
}
