/// Where a session runs: the terminal program, the app it belongs to, the identifiers it
/// gives the pane, and the pane's terminal device.
///
/// Built from the environment the hook command inherits from the terminal. Only the
/// variables below are kept; the rest of the environment is never read or stored.
public struct TerminalLocation: Sendable, Equatable, Codable {
    /// The terminal program, from `TERM_PROGRAM`, such as `iTerm.app` or `Apple_Terminal`.
    public var program: String?
    /// Pane identifiers by environment variable name, such as `ITERM_SESSION_ID`.
    public var paneIDs: [String: String]
    /// The bundle identifier of the app the session runs in, such as `com.googlecode.iterm2`,
    /// or an editor's for a session in its terminal. macOS sets `__CFBundleIdentifier` for an
    /// app it starts, and the processes the app starts inherit it.
    public var app: String?
    /// The terminal device of the pane, such as `/dev/ttys003`, from the Claude Code process.
    /// Terminal.app sets no variable its AppleScript knows, but it does know each tab's device.
    public var tty: String?

    /// The environment variables that identify a pane, per terminal.
    public static let paneVariables = [
        "ITERM_SESSION_ID",  // iTerm2
        "TERM_SESSION_ID",  // Terminal.app (iTerm2 sets it too)
        "TMUX_PANE",  // tmux, inside any terminal
        "KITTY_WINDOW_ID",  // kitty
        "WEZTERM_PANE",  // WezTerm
    ]

    private enum CodingKeys: String, CodingKey {
        case program
        case paneIDs = "pane_ids"
        case app
        case tty
    }

    public init(program: String?, paneIDs: [String: String] = [:], app: String? = nil, tty: String? = nil) {
        self.program = program
        self.paneIDs = paneIDs
        self.app = app
        self.tty = tty
    }

    /// Picks the terminal program, its app and the pane identifiers out of an environment.
    /// Returns nil when nothing in it identifies a terminal.
    public init?(environment: [String: String]) {
        let program = environment["TERM_PROGRAM"].flatMap { $0.isEmpty ? nil : $0 }
        let app = environment["__CFBundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 }
        let paneIDs = environment.filter { key, value in
            Self.paneVariables.contains(key) && !value.isEmpty
        }
        guard program != nil || app != nil || !paneIDs.isEmpty else { return nil }
        self.init(program: program, paneIDs: paneIDs, app: app)
    }
}
