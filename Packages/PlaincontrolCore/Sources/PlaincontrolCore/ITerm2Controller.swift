import PlaincontrolHooks

/// Brings iTerm2 panes to the front through iTerm2's AppleScript interface.
///
/// iTerm2 gives every pane an `ITERM_SESSION_ID` such as `w0t1p0:6B9F…`. The part after the
/// colon is the pane's `unique id` in AppleScript, which stays the same when the pane moves
/// to another tab or window.
public struct ITerm2Controller: TerminalController {
    public typealias ScriptRunner = @MainActor @Sendable (String) throws(TerminalControlError) -> String

    static let iTerm2 = "com.googlecode.iterm2"
    public var bundleIdentifier: String { Self.iTerm2 }
    private let runScript: ScriptRunner

    /// - Parameter runScript: Runs an AppleScript and returns its result as text.
    public init(runScript: @escaping ScriptRunner = AppleScript.run) {
        self.runScript = runScript
    }

    public func canFocus(_ location: TerminalLocation) -> Bool {
        Self.paneID(in: location) != nil
    }

    @MainActor
    public func focus(_ location: TerminalLocation) throws(TerminalControlError) {
        guard let paneID = Self.paneID(in: location) else { throw .unsupported }
        switch try runScript(Self.focusScript(paneID: paneID)) {
        case "focused": return
        case "not running": throw .terminalNotRunning
        default: throw .paneNotFound
        }
    }

    /// Opens a new iTerm2 window in `directory` and runs `command` there, if any, through the
    /// user's shell, as if they had typed it. Starts iTerm2 when it is not running.
    @MainActor
    public func openWindow(in directory: String, running command: String? = nil) throws(TerminalControlError) {
        _ = try runScript(Self.openWindowScript(directory: directory, command: command))
    }

    /// The pane's unique id, when the session runs directly in iTerm2.
    ///
    /// Inside tmux, `TERM_PROGRAM` is `tmux` and `ITERM_SESSION_ID` may belong to whichever pane
    /// started the tmux server, so those sessions are left alone.
    static func paneID(in location: TerminalLocation) -> String? {
        guard location.program == "iTerm.app",
            let sessionID = location.paneIDs["ITERM_SESSION_ID"],
            let paneID = sessionID.split(separator: ":").last
        else { return nil }
        // The id goes into a script, so accept only what iTerm2 generates: a UUID.
        guard !paneID.isEmpty, paneID.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
        return String(paneID)
    }

    static func openWindowScript(directory: String, command: String?) -> String {
        // `quoted form of` quotes the folder for the shell; the literals are quoted for AppleScript.
        let run = command.map { " & \" && \" & " + AppleScript.literal($0) } ?? ""
        return """
            tell application id "\(Self.iTerm2)"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "cd " & quoted form of \(AppleScript.literal(directory))\(run)
                end tell
            end tell
            """
    }

    static func focusScript(paneID: String) -> String {
        """
        if application id "\(Self.iTerm2)" is not running then return "not running"
        tell application id "\(Self.iTerm2)"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique id of aSession is "\(paneID)" then
                            -- Activate first: a window brought forward while iTerm2 is not
                            -- active stays on its Space when iTerm2 has a window on this one.
                            activate
                            select aWindow
                            select aTab
                            select aSession
                            return "focused"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "not found"
        """
    }
}
