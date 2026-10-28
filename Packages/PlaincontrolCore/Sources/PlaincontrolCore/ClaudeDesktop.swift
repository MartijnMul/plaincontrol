import Foundation

/// The Claude desktop app, whose Code tab runs Claude Code sessions in a window of its own
/// instead of a terminal.
///
/// The app has no way for other apps to open a session in a window of its own: its links show
/// a session in its main window, and a link with a folder asks the user to trust that folder
/// every time, trusted before or not. Its File menu does open a new session in a window of its
/// own, and the folder picker in that window sets the folder without asking, for any folder
/// Claude Code has worked in.
public enum ClaudeDesktop {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"

    /// The link that shows a new Claude Code session in the app's main window, in the folder
    /// it had last. It takes the main window to the Code tab, whose File menu has the item for a
    /// new window.
    public static let codeURL = URL(string: "claude://code/new")!

    /// The link that shows a new Claude Code session in `folder` in the app's main window,
    /// once the user has answered whether to trust the folder.
    ///
    /// The app reads the query as a web form does, where `+` stands for a space, so everything
    /// but unreserved characters and slashes is percent-encoded.
    public static func newSessionURL(in folder: String) -> URL {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        let encoded = folder.addingPercentEncoding(withAllowedCharacters: allowed) ?? folder
        return URL(string: "claude://code/new?folder=\(encoded)")!
    }

    /// The English title of the menu item that opens a new session in a window of its own.
    public static let newWindowMenuTitle = "New Session in New Window"

    /// The id of that title in the app's translations.
    static let newWindowMessageID = "U//bQDu9Yk"

    /// The titles the menu item for a new window has in the languages of the desktop app at
    /// `app`, so it is found whichever language the app shows its menus in.
    ///
    /// The app keeps its translations in `Contents/Resources`, one JSON file per language from
    /// message ids to text. The English title is always included, in case an update gives the
    /// message another id.
    public static func newWindowMenuTitles(inAppAt app: URL) -> Set<String> {
        let resources = app.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let files =
            (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
        var titles: Set<String> = [newWindowMenuTitle]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let title = messages[newWindowMessageID] as? String
            else { continue }
            titles.insert(title)
        }
        return titles
    }

    /// The folder a path in the app's window stands for: the folder button shows the path from
    /// the home folder (`~/Code/app`), the folder picker shows it in full.
    public static func folder(shownAs path: String, home: String) -> String? {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        let full = path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst() : path
        guard full.hasPrefix("/") else { return nil }
        return full.count > 1 && full.hasSuffix("/") ? String(full.dropLast()) : full
    }
}
