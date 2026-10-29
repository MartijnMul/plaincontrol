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

    /// The English label of the folder button in a session's window, `{value}` standing for
    /// the folder, or for the text that asks for one while it has none.
    public static let folderButtonLabel = "Folder: {value}"

    /// The id of that label in the app's translations.
    static let folderButtonMessageID = "hSyWJr4x1N"

    /// The titles the menu item for a new window has in the languages of the desktop app at
    /// `app`, so it is found whichever language the app shows its menus in.
    public static func newWindowMenuTitles(inAppAt app: URL) -> Set<String> {
        translations(of: newWindowMessageID, inAppAt: app, archive: "app.asar", directory: "resources/i18n")
            .union([newWindowMenuTitle])
    }

    /// The labels the folder button has in the languages of the desktop app at `app`.
    public static func folderButtonLabels(inAppAt app: URL) -> Set<String> {
        translations(of: folderButtonMessageID, inAppAt: app, archive: "ion-dist.asar", directory: "i18n")
            .union([folderButtonLabel])
    }

    /// Whether `description`, what a button in the window says it is, is the folder button's
    /// label in one of `labels`, for any folder or none.
    public static func isFolderButton(described description: String, labels: Set<String>) -> Bool {
        labels.contains { label in
            guard let value = label.range(of: "{value}") else { return false }
            let prefix = label[..<value.lowerBound]
            let suffix = label[value.upperBound...]
            return description.count > prefix.count + suffix.count && description.hasPrefix(prefix)
                && description.hasSuffix(suffix)
        }
    }

    /// The text of message `id` in each language of the desktop app at `app`. The English text
    /// is not always among them, so callers add it, also in case an update gives the message
    /// another id.
    ///
    /// The app keeps its translations as JSON files, one per language, from message ids to
    /// text: in `directory` inside `archive` in `Contents/Resources`, or, before version 4.29,
    /// in `Contents/Resources` itself.
    static func translations(of id: String, inAppAt app: URL, archive: String, directory: String) -> Set<String> {
        let resources = app.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        var files: [Data] = []
        if let asar = Asar(contentsOf: resources.appending(path: archive)) {
            for name in asar.files(in: directory) where name.hasSuffix(".json") {
                asar.contents(of: "\(directory)/\(name)").map { files.append($0) }
            }
        }
        let loose = (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
        for file in loose where file.pathExtension == "json" {
            (try? Data(contentsOf: file)).map { files.append($0) }
        }
        return Set(
            files.compactMap { data in
                (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?[id] as? String
            })
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
