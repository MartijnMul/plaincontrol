import Foundation
import PlaincontrolHooks

/// What an app the user works in is to the launcher.
public enum AppRole: String, Codable, Sendable {
    /// A terminal app, such as iTerm2 or Ghostty.
    case terminal
    /// An editor, such as Visual Studio Code, Xcode or Zed.
    case editor

    /// Terminal apps, by bundle identifier.
    static let terminals: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "org.alacritty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "org.tabby",
        "com.raphaelamorim.rio",
    ]

    /// Editors, by bundle identifier. Visual Studio Code and the editors built on it, such as
    /// Cursor, also say so through `TERM_PROGRAM`, as Zed does; JetBrains IDEs share a prefix.
    static let editors: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "com.apple.dt.Xcode",
        "com.sublimetext.3",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.barebones.bbedit",
        "com.macromates.TextMate",
        "org.vim.MacVim",
        "org.gnu.Emacs",
        "com.google.android.studio",
    ]

    /// The apps known to be of this kind, by bundle identifier; JetBrains IDEs are not
    /// among them, as they are known by their prefix.
    public var knownApps: Set<String> {
        switch self {
        case .terminal: Self.terminals
        case .editor: Self.editors
        }
    }

    /// What the app at `location` is, or nil when it is neither a known terminal nor an
    /// editor.
    public init?(of location: TerminalLocation) {
        guard let app = location.app else { return nil }
        if Self.terminals.contains(app) {
            self = .terminal
        } else if Self.isEditor(app) || ["vscode", "zed"].contains(location.program) {
            self = .editor
        } else {
            return nil
        }
    }

    /// Whether `bundleIdentifier` is a known terminal app.
    public static func isTerminal(_ bundleIdentifier: String) -> Bool {
        terminals.contains(bundleIdentifier)
    }

    /// Whether `bundleIdentifier` is a known editor.
    static func isEditor(_ bundleIdentifier: String) -> Bool {
        editors.contains(bundleIdentifier) || bundleIdentifier.hasPrefix("com.jetbrains.")
    }
}

/// Which terminals and editors the user works in, to pick the ones the launcher opens without
/// asking.
///
/// A use is the start of a Claude Code session in a terminal or an editor, or bringing an
/// editor to the front, which counts at most once an hour: an editor shows how the user works
/// also when they run Claude Code in a terminal. Each use counts for less as it gets older,
/// halving every ``halfLife``, so the launcher follows a switch to another app within days.
public struct AppUsage: Codable, Sendable, Equatable {
    public struct Use: Codable, Sendable, Equatable {
        /// The app's bundle identifier.
        public var app: String
        public var role: AppRole
        public var date: Date
    }

    /// The uses, oldest first.
    public private(set) var uses: [Use] = []

    /// How long until a use counts half: after using another app as much for this long, the
    /// launcher picks it.
    public static let halfLife: TimeInterval = 3 * 24 * 3600
    /// How long bringing the same editor to the front again counts as the same use.
    public static let activationInterval: TimeInterval = 3600
    /// How many uses are kept per role; older ones count for almost nothing anyway.
    public static let limit = 500

    public init() {}

    /// Counts a session started at `location`, if it runs in a known terminal or editor.
    public mutating func record(_ location: TerminalLocation?, at date: Date = .now) {
        guard let location, let app = location.app, let role = AppRole(of: location) else { return }
        append(Use(app: app, role: role, date: date))
    }

    /// Counts bringing the app with `bundleIdentifier` to the front, if it is an editor: a
    /// known one, or one a session ran in. Returns whether it counted.
    @discardableResult
    public mutating func recordActivation(of bundleIdentifier: String, at date: Date = .now) -> Bool {
        let isEditor =
            AppRole.isEditor(bundleIdentifier)
            || uses.contains { $0.app == bundleIdentifier && $0.role == .editor }
        guard isEditor else { return false }
        if let last = uses.last(where: { $0.app == bundleIdentifier && $0.role == .editor }),
            date.timeIntervalSince(last.date) < Self.activationInterval
        {
            return false
        }
        append(Use(app: bundleIdentifier, role: .editor, date: date))
        return true
    }

    /// The apps in `role` the user works in, most used first, weighing recent uses more.
    public func ranked(_ role: AppRole, at now: Date = .now) -> [String] {
        var scores: [String: Double] = [:]
        for use in uses where use.role == role {
            scores[use.app, default: 0] += pow(0.5, max(now.timeIntervalSince(use.date), 0) / Self.halfLife)
        }
        return scores.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    private mutating func append(_ use: Use) {
        uses.append(use)
        if uses.count(where: { $0.role == use.role }) > Self.limit,
            let oldest = uses.firstIndex(where: { $0.role == use.role })
        {
            uses.remove(at: oldest)
        }
    }
}
