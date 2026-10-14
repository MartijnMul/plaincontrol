import AppKit
import Observation
import PlaincontrolCore
import PlaincontrolHooks
import os

/// Receives hook events and keeps the sessions the app shows.
@MainActor
@Observable
final class SessionStore {
    private(set) var registry = SessionRegistry()
    /// Why the app cannot receive events, when it cannot.
    private(set) var problem: String?
    /// Why the last jump to a session failed, until the next one succeeds.
    private(set) var jumpProblem: String?
    /// Called with the folder of each session that starts.
    @ObservationIgnored var onSessionStart: ((String) -> Void)?
    @ObservationIgnored private var server: HookServer?
    @ObservationIgnored private var processes: ProcessWatcher?
    @ObservationIgnored private let notifier = SessionNotifier()
    @ObservationIgnored private let terminals = TerminalControllers.standard
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "jump")

    /// The sessions to show: everything still running, waiting ones first.
    var sessions: [Session] {
        registry.sessions.values
            .filter { $0.status != .gone }
            .sorted { ($0.status.sortOrder, $0.statusSince) < ($1.status.sortOrder, $1.statusSince) }
    }

    var waitingCount: Int {
        registry.needingAttention.count
    }

    func start() {
        notifier.onOpen = { [weak self] sessionID in self?.jump(to: sessionID) }
        processes = ProcessWatcher { [weak self] sessionID in self?.processExited(of: sessionID) }
        notifier.start()
        let path = HookSocket.path(environment: ProcessInfo.processInfo.environment, appName: AppInfo.name)
        let server = HookServer(path: path) { [weak self] envelope in
            // The server calls in order on its own queue; the main queue keeps that order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(envelope) }
            }
        }
        do {
            try server.start()
            self.server = server
        } catch UnixSocketError.alreadyListening {
            problem = "Another copy of \(AppInfo.name) is already running."
        } catch {
            problem = "Cannot listen for Claude Code sessions: \(error)"
        }
    }

    func canJump(to session: Session) -> Bool {
        terminals.canFocus(session.terminal)
    }

    /// Brings the session's terminal pane to the front.
    func jump(to sessionID: String) {
        guard let session = registry.sessions[sessionID] else {
            log.notice("Jump to unknown session \(sessionID, privacy: .public)")
            return
        }
        do {
            if let controller = terminals.controller(for: session.terminal) {
                // Clicking a notification activates this app; let the terminal take over.
                NSApp.yieldActivation(toApplicationWithBundleIdentifier: controller.bundleIdentifier)
            }
            try terminals.focus(session.terminal)
            jumpProblem = nil
            log.info("Jumped to session \(sessionID, privacy: .public)")
        } catch {
            jumpProblem = "Could not open \(session.displayName): \(error.message)"
            log.error(
                "Jump to session \(sessionID, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    private func receive(_ envelope: HookEnvelope) {
        let change = registry.apply(envelope.event, terminal: envelope.terminal, at: envelope.sentAt)
        let sessionID = envelope.event.sessionID
        if envelope.event.kind == .sessionStart, let cwd = envelope.event.cwd {
            onSessionStart?(cwd)
        }
        if registry.sessions[sessionID]?.status == .gone {
            processes?.stopWatching(sessionID)
        } else if let process = envelope.process {
            processes?.watch(process, for: sessionID)
        }
        if let change { notify(change) }
    }

    /// Claude Code was killed or crashed, so no `SessionEnd` came.
    private func processExited(of sessionID: String) {
        Logger(subsystem: AppInfo.subsystem, category: "sessions")
            .info("The process of session \(sessionID, privacy: .public) exited")
        if let change = registry.markGone(sessionID) { notify(change) }
    }

    private func notify(_ change: StatusChange) {
        guard let session = registry.sessions[change.sessionID] else { return }
        notifier.handle(change, of: session)
    }
}

extension TerminalControlError {
    fileprivate var message: String {
        switch self {
        case .unsupported: "jumping to this terminal is not supported yet."
        case .terminalNotRunning: "its terminal is no longer running."
        case .paneNotFound: "its terminal pane is closed."
        case .notAuthorized:
            "allow \(AppInfo.name) to control your terminal in System Settings › Privacy & Security › Automation."
        case .failed(let reason): reason
        }
    }
}

extension SessionStatus {
    fileprivate var sortOrder: Int {
        switch self {
        case .waiting: 0
        case .working: 1
        case .idle: 2
        case .gone: 3
        }
    }
}
