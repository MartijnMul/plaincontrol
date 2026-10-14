/// Where a session runs: the terminal program and the identifiers it gives the pane.
///
/// Built from the environment the hook command inherits from the terminal. Only the
/// variables below are kept; the rest of the environment is never read or stored.
public struct TerminalLocation: Sendable, Equatable, Codable {
    /// The terminal program, from `TERM_PROGRAM`, such as `iTerm.app` or `Apple_Terminal`.
    public var program: String?
    /// Pane identifiers by environment variable name, such as `ITERM_SESSION_ID`.
    public var paneIDs: [String: String]

    /// The environment variables that identify a pane, per terminal.
    public static let paneVariables = [
        "ITERM_SESSION_ID",  // iTerm2
        "TERM_SESSION_ID",  // Terminal.app
        "TMUX_PANE",  // tmux, inside any terminal
        "KITTY_WINDOW_ID",  // kitty
        "WEZTERM_PANE",  // WezTerm
    ]

    public init(program: String?, paneIDs: [String: String] = [:]) {
        self.program = program
        self.paneIDs = paneIDs
    }

    /// Picks the terminal program and pane identifiers out of an environment.
    /// Returns nil when nothing in it identifies a terminal.
    public init?(environment: [String: String]) {
        let program = environment["TERM_PROGRAM"].flatMap { $0.isEmpty ? nil : $0 }
        let paneIDs = environment.filter { key, value in
            Self.paneVariables.contains(key) && !value.isEmpty
        }
        guard program != nil || !paneIDs.isEmpty else { return nil }
        self.init(program: program, paneIDs: paneIDs)
    }
}
