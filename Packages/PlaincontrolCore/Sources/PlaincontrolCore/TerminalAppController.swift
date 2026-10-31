import CoreGraphics
import PlaincontrolHooks

/// Brings Terminal.app tabs to the front and opens Terminal.app windows through its
/// AppleScript interface.
///
/// Terminal.app's `TERM_SESSION_ID` means nothing to its AppleScript, but every tab has a
/// `tty`, the terminal device of the shell in it, which is also the device of the Claude Code
/// process running there (``TerminalLocation/tty``).
public struct TerminalAppController: TerminalController {
    public typealias ScriptRunner = @MainActor @Sendable (String) throws(TerminalControlError) -> String

    static let terminal = "com.apple.Terminal"
    public var bundleIdentifier: String { Self.terminal }
    public var name: String { "Terminal" }
    /// Terminal.app puts a new window where it wants once it shows it, after any bounds a
    /// script gives it, so the caller moves it then.
    public var placesWindows: Bool { false }
    private let runScript: ScriptRunner

    /// - Parameter runScript: Runs an AppleScript and returns its result as text.
    public init(runScript: @escaping ScriptRunner = AppleScript.run) {
        self.runScript = runScript
    }

    public func canFocus(_ location: TerminalLocation) -> Bool {
        Self.tty(in: location) != nil
    }

    @MainActor
    public func focus(_ location: TerminalLocation) throws(TerminalControlError) {
        guard let tty = Self.tty(in: location) else { throw .unsupported }
        switch try runScript(Self.focusScript(tty: tty)) {
        case "focused": return
        case "not running": throw .terminalNotRunning
        default: throw .paneNotFound
        }
    }

    @MainActor
    public func openWindow(
        in directory: String?, running command: String? = nil, frame: CGRect? = nil, minimized: Bool = false
    ) throws(TerminalControlError) {
        _ = try runScript(Self.openWindowScript(directory: directory, command: command, minimized: minimized))
    }

    /// The tab's terminal device, when the session runs directly in Terminal.app.
    ///
    /// Inside tmux, `TERM_PROGRAM` is `tmux` and the device is one of tmux's own, so those
    /// sessions are left alone.
    static func tty(in location: TerminalLocation) -> String? {
        guard location.program == "Apple_Terminal", let tty = location.tty else { return nil }
        // The device goes into a script, so accept only what the kernel names: /dev/ttys003.
        let name = tty.trimmingPrefix("/dev/")
        guard name.count < tty.count, !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return tty
    }

    static func openWindowScript(directory: String?, command: String?, minimized: Bool = false) -> String {
        // `quoted form of` quotes the folder for the shell; the literals are quoted for AppleScript.
        let cd = directory.map { "\"cd \" & quoted form of " + AppleScript.literal($0) }
        let line = [cd, command.map(AppleScript.literal)].compactMap { $0 }.joined(separator: " & \" && \" & ")
        // `do script` without a window opens a new one. Terminal.app opens a window of its own
        // when it starts, so a terminal that was not running uses that one instead of a second.
        // Without anything to type, that window stays as Terminal.app opened it.
        let inStartWindow = line.isEmpty ? "" : "\n            do script \(line) in window 1"
        // Either way the window is the front one. A minimised window leaves Terminal.app in the
        // background.
        let activate = minimized ? "" : "\n    activate"
        let minimize = minimized ? "\n    set miniaturized of window 1 to true" : ""
        return """
            set wasRunning to application id "\(Self.terminal)" is running
            tell application id "\(Self.terminal)"\(activate)
                if not wasRunning and (count of windows) is 1 then\(inStartWindow)
                else
                    do script \(line.isEmpty ? "\"\"" : line)
                end if\(minimize)
            end tell
            """
    }

    static func focusScript(tty: String) -> String {
        """
        if application id "\(Self.terminal)" is not running then return "not running"
        tell application id "\(Self.terminal)"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if tty of aTab is "\(tty)" then
                        -- Activate first: a window brought forward while Terminal.app is not
                        -- active stays on its Space when Terminal.app has a window on this one.
                        activate
                        set miniaturized of aWindow to false
                        set selected of aTab to true
                        set index of aWindow to 1
                        return "focused"
                    end if
                end repeat
            end repeat
        end tell
        return "not found"
        """
    }
}
