import Dispatch
import PlaincontrolHooks

/// Tells when the process of a session exits.
///
/// Claude Code sends `SessionEnd` when it shuts down, also when its terminal is closed, but
/// not when it is killed or crashes. The process exiting is then the only sign that the
/// session is gone. The kernel reports the exit right away; nothing is polled.
@MainActor
public final class ProcessWatcher {
    private var watched: [String: (process: SessionProcess, source: any DispatchSourceProcess)] = [:]
    private let onExit: @MainActor (String) -> Void

    /// - Parameter onExit: Called with the session ID once the session's process has exited.
    public init(onExit: @escaping @MainActor (String) -> Void) {
        self.onExit = onExit
    }

    /// Watches `process` as the process of `sessionID`, in place of an earlier one, such as
    /// when a session is resumed in a new process.
    public func watch(_ process: SessionProcess, for sessionID: String) {
        guard watched[sessionID]?.process != process else { return }
        watched.removeValue(forKey: sessionID)?.source.cancel()

        let source = DispatchSource.makeProcessSource(identifier: process.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.exited(process, of: sessionID) }
        }
        watched[sessionID] = (process, source)
        source.resume()
        // The process may have exited before the source was set up.
        if !process.isRunning {
            exited(process, of: sessionID)
        }
    }

    /// Stops watching the process of `sessionID`.
    public func stopWatching(_ sessionID: String) {
        watched.removeValue(forKey: sessionID)?.source.cancel()
    }

    private func exited(_ process: SessionProcess, of sessionID: String) {
        guard watched[sessionID]?.process == process else { return }
        stopWatching(sessionID)
        onExit(sessionID)
    }
}
