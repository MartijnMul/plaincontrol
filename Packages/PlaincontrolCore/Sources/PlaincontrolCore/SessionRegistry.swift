import Foundation
import PlaincontrolHooks

/// A Claude Code session as Plaincontrol tracks it.
public struct Session: Sendable, Equatable, Identifiable {
    public let id: String
    public var status: SessionStatus
    /// When the session entered its current status.
    public var statusSince: Date
    /// When the last event for this session arrived.
    public var lastEventAt: Date
    public var cwd: String?
    public var title: String?
    public var terminal: TerminalLocation?
}

/// A change of a session's status, for notifications and the like.
public struct StatusChange: Sendable, Equatable {
    public var sessionID: String
    /// The previous status, or nil for a session seen for the first time.
    public var from: SessionStatus?
    public var to: SessionStatus
}

/// Keeps track of every session from the hook events it receives.
///
/// The rules that map events to statuses are in ``SessionRegistry/status(after:from:)``.
public struct SessionRegistry: Sendable {
    public private(set) var sessions: [String: Session] = [:]

    public init() {}

    /// The sessions that need the user, the longest-waiting first.
    public var needingAttention: [Session] {
        sessions.values
            .filter(\.status.needsAttention)
            .sorted { $0.statusSince < $1.statusSince }
    }

    /// Applies one event and returns the status change it caused, if any.
    @discardableResult
    public mutating func apply(
        _ event: HookEvent,
        terminal: TerminalLocation? = nil,
        at date: Date = .now
    ) -> StatusChange? {
        let existing = sessions[event.sessionID]
        let newStatus = Self.status(after: event, from: existing?.status) ?? existing?.status ?? .idle

        var session =
            existing
            ?? Session(id: event.sessionID, status: newStatus, statusSince: date, lastEventAt: date)
        session.lastEventAt = date
        if let cwd = event.cwd { session.cwd = cwd }
        if let title = event.sessionTitle { session.title = title }
        if let terminal { session.terminal = terminal }

        let changed = existing == nil || existing?.status != newStatus
        if changed {
            session.status = newStatus
            session.statusSince = date
        }
        sessions[event.sessionID] = session

        return changed ? StatusChange(sessionID: event.sessionID, from: existing?.status, to: newStatus) : nil
    }

    /// Marks a session as gone because its process exited without a `SessionEnd`, such as
    /// after a crash.
    @discardableResult
    public mutating func markGone(_ sessionID: String, at date: Date = .now) -> StatusChange? {
        guard var session = sessions[sessionID], session.status != .gone else { return nil }
        let change = StatusChange(sessionID: sessionID, from: session.status, to: .gone)
        session.status = .gone
        session.statusSince = date
        sessions[sessionID] = session
        return change
    }

    /// The status an event moves a session to, or nil when it leaves the status as it is.
    static func status(after event: HookEvent, from current: SessionStatus?) -> SessionStatus? {
        switch event.kind {
        case .sessionStart:
            return .idle
        case .userPromptSubmit:
            return .working
        case .preToolUse where event.toolName == "AskUserQuestion":
            return .waiting(.question)
        case .preToolUse where event.toolName == "ExitPlanMode":
            return .waiting(.planApproval)
        case .permissionRequest:
            return .waiting(.permission)
        case .notification:
            switch event.notificationType {
            case "permission_prompt": return .waiting(.permission)
            case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input": return .waiting(.input)
            default: return nil
            }
        case .preToolUse, .postToolUse, .postToolUseFailure, .postToolBatch, .subagentStart, .subagentStop:
            // Activity inside a turn. A background subagent can report after the turn ended,
            // so this never wakes an idle session. A session not seen before is most likely
            // in the middle of a turn that started before Plaincontrol did.
            switch current {
            case .working, .waiting, nil: return .working
            case .idle, .gone: return nil
            }
        case .stop, .stopFailure:
            return .idle
        case .sessionEnd:
            return .gone
        case .other:
            return nil
        }
    }
}
