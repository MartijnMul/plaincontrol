import CoreGraphics
import PlaincontrolHooks

/// Brings the terminal pane of a session to the front, and opens new terminal windows.
///
/// There is one controller per terminal program; ``TerminalControllers`` picks the one that
/// knows a session's ``TerminalLocation``, or the one for the terminal the launcher opens. The
/// rest of Plaincontrol never needs to know which terminal a session runs in.
public protocol TerminalController: Sendable {
    /// The bundle identifier of the terminal app, so the caller can hand it the focus.
    var bundleIdentifier: String { get }
    /// The name of the terminal app, such as `iTerm2`.
    var name: String { get }

    /// Whether this controller knows how to find the pane at `location`.
    func canFocus(_ location: TerminalLocation) -> Bool

    /// Brings the pane at `location` to the front, with its window, tab and Space.
    @MainActor func focus(_ location: TerminalLocation) throws(TerminalControlError)

    /// Opens a new window in `directory`, or where the terminal starts new windows without one,
    /// and runs `command` there, if any, through the user's shell, as if they had typed it.
    /// Starts the terminal when it is not running.
    ///
    /// - Parameter frame: Where the window goes, in global coordinates from the top left of the
    ///   main screen; without one, the terminal decides.
    @MainActor func openWindow(in directory: String?, running command: String?, frame: CGRect?)
        throws(TerminalControlError)
}

/// Why a pane could not be brought to the front.
public enum TerminalControlError: Error, Equatable, Sendable {
    /// No controller knows this kind of terminal location.
    case unsupported
    /// The terminal program is not running, so the pane is gone.
    case terminalNotRunning
    /// The terminal is running, but the pane is no longer there.
    case paneNotFound
    /// The user has not allowed Plaincontrol to control the terminal.
    case notAuthorized
    /// Anything else, with the terminal's own description.
    case failed(String)
}

/// The terminal controllers Plaincontrol knows, in order of preference.
public struct TerminalControllers: Sendable {
    public var controllers: [any TerminalController]

    public init(_ controllers: [any TerminalController]) {
        self.controllers = controllers
    }

    /// Every terminal Plaincontrol supports.
    public static let standard = TerminalControllers([ITerm2Controller()])

    /// The first controller that can focus `location`, if any.
    public func controller(for location: TerminalLocation?) -> (any TerminalController)? {
        guard let location else { return nil }
        return controllers.first { $0.canFocus(location) }
    }

    /// The controller for the terminal app with `bundleIdentifier`, if Plaincontrol supports it.
    public func controller(forApp bundleIdentifier: String) -> (any TerminalController)? {
        controllers.first { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Whether some controller can focus `location`.
    public func canFocus(_ location: TerminalLocation?) -> Bool {
        controller(for: location) != nil
    }

    /// Brings the pane at `location` to the front with the first controller that can.
    @MainActor
    public func focus(_ location: TerminalLocation?) throws(TerminalControlError) {
        guard let location, let controller = controller(for: location) else {
            throw .unsupported
        }
        try controller.focus(location)
    }
}
