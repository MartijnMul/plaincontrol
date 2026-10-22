import Foundation

/// The link through which the Claude Code plugin finds the hook command inside the app.
///
/// The app carries the command, so it is signed with the app and always matches it. The
/// plugin can't know where the app is, so each time the app starts it points
/// `~/Library/Application Support/<app name>/bin/plaincontrol-hook` at its own copy. The
/// plugin's script runs whatever the link points to, and nothing when it points nowhere.
public enum HookCommandLink {
    public static let commandName = "plaincontrol-hook"

    /// Where the link of the app named `appName` goes.
    public static func defaultURL(appName: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: appName, directoryHint: .isDirectory)
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: commandName)
    }

    /// Points the link at `command`, unless it does already.
    ///
    /// The new link replaces the old one in a single step, so a hook running meanwhile finds
    /// either the old command or the new one, never nothing.
    public static func update(_ link: URL, to command: URL) throws {
        let fileManager = FileManager.default
        let target = command.path(percentEncoded: false)
        let path = link.path(percentEncoded: false)
        if (try? fileManager.destinationOfSymbolicLink(atPath: path)) == target { return }
        try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = link.deletingLastPathComponent().appending(path: ".\(commandName)-\(UUID().uuidString)")
        try fileManager.createSymbolicLink(atPath: temporary.path(percentEncoded: false), withDestinationPath: target)
        guard rename(temporary.path(percentEncoded: false), path) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}
