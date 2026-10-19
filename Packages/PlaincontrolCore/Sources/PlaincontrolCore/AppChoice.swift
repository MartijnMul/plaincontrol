/// Picks the terminal and the editor the launcher opens projects in, so that it works without
/// settings: from the apps the user works in (``AppUsage``) and, for the editor, the apps macOS
/// opens code files with.
///
/// Apps are named by bundle identifier. A setting in the launcher file comes first; the caller
/// finds its app before asking.
public enum AppChoice {
    /// The terminal the launcher opens windows in, and the one it would rather use but cannot.
    public struct Terminal: Sendable, Equatable {
        /// The terminal to open windows in, if one that Plaincontrol can open is installed.
        public var app: String?
        /// The terminal the user set or uses most, when Plaincontrol cannot open its windows.
        public var unsupported: String?

        public init(app: String?, unsupported: String? = nil) {
            self.app = app
            self.unsupported = unsupported
        }
    }

    /// The terminal: the one set, when Plaincontrol can open it; without a setting, the one
    /// the user runs sessions in most of those it can open, or else the first it can open
    /// that is installed. A set or most used terminal that it cannot open is reported, so the
    /// launcher can say so.
    ///
    /// - Parameters:
    ///   - setting: The terminal set in the settings, if any.
    ///   - ranked: The terminals the user runs sessions in, most used first.
    ///   - supported: The terminals Plaincontrol can open windows in, in order of preference.
    ///   - isInstalled: Whether an app is installed.
    public static func terminal(
        setting: String?, ranked: [String], supported: [String], isInstalled: (String) -> Bool
    ) -> Terminal {
        func usable(_ app: String) -> Bool { supported.contains(app) && isInstalled(app) }
        if let setting {
            return usable(setting) ? Terminal(app: setting) : Terminal(app: nil, unsupported: setting)
        }
        let app = (ranked + supported).first(where: usable)
        let favourite = ranked.first
        return Terminal(app: app, unsupported: favourite.flatMap { supported.contains($0) ? nil : $0 })
    }

    /// The editor when none is set and the user was not seen using one.
    public static let defaultEditor = "com.microsoft.VSCode"

    /// Kinds of files mostly opened in an editor, whose default apps hint at the user's
    /// editor, by type identifier.
    public static let codeFileTypes = [
        "public.json",
        "net.daringfireball.markdown",
        "public.source-code",
        "public.python-script",
        "public.yaml",
        "com.netscape.javascript-source",
        "public.shell-script",
    ]

    /// Apps that are often the default for code files without being anyone's editor for a
    /// project: macOS sets them so.
    static let notEditors: Set<String> = ["com.apple.TextEdit", "com.apple.dt.Xcode"]

    /// The editor, when none is set: the one the user works in most that is installed, by
    /// sessions in it and bringing it to the front; or else the app macOS opens most ``codeFileTypes`` with, other than TextEdit,
    /// Xcode and terminals; or else Visual Studio Code, when installed.
    ///
    /// - Parameters:
    ///   - ranked: The editors the user works in, most used first.
    ///   - defaults: The app macOS opens each of ``codeFileTypes`` with, where it has one.
    ///   - isInstalled: Whether an app is installed.
    public static func editor(ranked: [String], defaults: [String], isInstalled: (String) -> Bool) -> String? {
        if let app = ranked.first(where: isInstalled) { return app }
        let candidates = defaults.filter { !notEditors.contains($0) && !AppRole.isTerminal($0) }
        let votes = Dictionary(candidates.map { ($0, 1) }, uniquingKeysWith: +)
        // The most votes wins; a tie goes to the app for the earlier kind of file.
        var best: String?
        for app in candidates where votes[app, default: 0] > best.map({ votes[$0, default: 0] }) ?? 0 {
            best = app
        }
        return best ?? (isInstalled(defaultEditor) ? defaultEditor : nil)
    }
}
