import Foundation

/// The Claude desktop app, whose Code tab runs Claude Code sessions in a window of its own
/// instead of a terminal.
public enum ClaudeDesktop {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"

    /// The link that asks the desktop app for a new Claude Code session in `folder`.
    ///
    /// The app reads the query as a web form does, where `+` stands for a space, so everything
    /// but unreserved characters and slashes is percent-encoded.
    public static func newSessionURL(in folder: String) -> URL {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        let encoded = folder.addingPercentEncoding(withAllowedCharacters: allowed) ?? folder
        return URL(string: "claude://code/new?folder=\(encoded)")!
    }
}
