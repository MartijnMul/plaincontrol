import Foundation
import Observation
import PlaincontrolCore

/// Receives hook events and keeps the sessions the app shows.
@MainActor
@Observable
final class SessionStore {
    private(set) var registry = SessionRegistry()
    /// Why the app cannot receive events, when it cannot.
    private(set) var problem: String?
    @ObservationIgnored private var server: HookServer?
    @ObservationIgnored private let notifier = SessionNotifier()

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

    private func receive(_ envelope: HookEnvelope) {
        guard let change = registry.apply(envelope.event, terminal: envelope.terminal, at: envelope.sentAt),
            let session = registry.sessions[change.sessionID]
        else { return }
        notifier.handle(change, of: session)
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
