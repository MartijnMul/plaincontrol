import Foundation
import PlaincontrolHooks

/// What an app that runs Claude Code sessions is to the user.
public enum AppRole: String, Codable, Sendable {
    /// A terminal app, such as iTerm2 or Ghostty.
    case terminal
    /// An editor with a terminal of its own, such as Visual Studio Code or Zed.
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
    /// Cursor, also say so through `TERM_PROGRAM`, as Zed does.
    static let editors: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.google.android.studio",
    ]

    /// What the app at `location` is, or nil when it is neither a known terminal nor an
    /// editor.
    public init?(of location: TerminalLocation) {
        guard let app = location.app else { return nil }
        if Self.terminals.contains(app) {
            self = .terminal
        } else if Self.editors.contains(app) || app.hasPrefix("com.jetbrains.")
            || ["vscode", "zed"].contains(location.program)
        {
            self = .editor
        } else {
            return nil
        }
    }

    /// Whether `bundleIdentifier` is a known terminal app.
    public static func isTerminal(_ bundleIdentifier: String) -> Bool {
        terminals.contains(bundleIdentifier)
    }
}

/// Which apps the user runs Claude Code sessions in, to pick the terminal and the editor the
/// launcher opens without asking.
///
/// A use is the start of a session in an app. As with ``ProjectUsage``, each use counts for
/// less as it gets older, halving every week.
public struct AppUsage: Codable, Sendable, Equatable {
    public struct Use: Codable, Sendable, Equatable {
        /// The app's bundle identifier.
        public var app: String
        public var role: AppRole
        public var date: Date
    }

    /// The uses, oldest first.
    public private(set) var uses: [Use] = []

    /// How many uses are kept; older ones count for almost nothing anyway.
    public static let limit = 500

    public init() {}

    /// Counts a session started at `location`, if it runs in a known terminal or editor.
    public mutating func record(_ location: TerminalLocation?, at date: Date = .now) {
        guard let location, let app = location.app, let role = AppRole(of: location) else { return }
        uses.append(Use(app: app, role: role, date: date))
        if uses.count > Self.limit { uses.removeFirst(uses.count - Self.limit) }
    }

    /// The apps in `role` the user ran sessions in, most used first, weighing recent uses more.
    public func ranked(_ role: AppRole, at now: Date = .now) -> [String] {
        var scores: [String: Double] = [:]
        for use in uses where use.role == role {
            scores[use.app, default: 0] += pow(0.5, max(now.timeIntervalSince(use.date), 0) / ProjectUsage.halfLife)
        }
        return scores.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }
}
