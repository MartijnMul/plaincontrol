import AppKit
import UniformTypeIdentifiers

/// Finds the apps the launcher's actions open projects in.
enum Apps {
    /// Visual Studio Code, the editor when none is set.
    static let defaultEditor = "com.microsoft.VSCode"
    /// Finder, which opens folders unless the user chose another app for them.
    static let finder = "com.apple.finder"

    /// The editor for `setting`: a bundle identifier, an app name such as `Cursor`, or a path
    /// to an app. Without a setting, Visual Studio Code if it is installed.
    static func editor(for setting: String?) -> URL? {
        guard let setting else {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: defaultEditor)
        }
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

    /// The app macOS opens folders with: Finder, unless the user chose another, such as Path
    /// Finder or ForkLift.
    static var folders: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: .folder)
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
