import Foundation
import Testing

@testable import PlaincontrolCore

struct SessionRegistryTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func event(
        _ kind: HookEvent.Kind, session: String = "s1", tool: String? = nil, notification: String? = nil
    ) -> HookEvent {
        HookEvent(sessionID: session, kind: kind, toolName: tool, notificationType: notification)
    }

    /// Applies the events one second apart and returns the registry.
    private func registry(after events: [HookEvent]) -> SessionRegistry {
        var registry = SessionRegistry()
        for (offset, event) in events.enumerated() {
            registry.apply(event, at: start.addingTimeInterval(Double(offset)))
        }
        return registry
    }

    private func status(after events: [HookEvent]) -> SessionStatus? {
        registry(after: events).sessions["s1"]?.status
    }

    @Test func followsATurnFromPromptToStop() {
        #expect(status(after: [event(.sessionStart)]) == .idle)
        #expect(status(after: [event(.sessionStart), event(.userPromptSubmit)]) == .working)
        #expect(status(after: [event(.sessionStart), event(.userPromptSubmit), event(.stop)]) == .idle)
        #expect(status(after: [event(.userPromptSubmit), event(.stopFailure)]) == .idle)
        #expect(status(after: [event(.userPromptSubmit), event(.sessionEnd)]) == .gone)
    }

    @Test func waitsForAPermissionUntilTheToolRuns() {
        let asked = [
            event(.userPromptSubmit), event(.preToolUse, tool: "Bash"), event(.permissionRequest, tool: "Bash"),
        ]
        #expect(status(after: asked) == .waiting(.permission))
        #expect(status(after: asked + [event(.postToolUse, tool: "Bash")]) == .working)
    }

    @Test func aLatePermissionNotificationAlsoMeansWaiting() {
        let events = [event(.userPromptSubmit), event(.notification, notification: "permission_prompt")]
        #expect(status(after: events) == .waiting(.permission))
    }

    @Test func questionsPlansAndFormsAreWaiting() {
        #expect(
            status(after: [event(.userPromptSubmit), event(.preToolUse, tool: "AskUserQuestion")])
                == .waiting(.question))
        #expect(
            status(after: [event(.userPromptSubmit), event(.preToolUse, tool: "ExitPlanMode")])
                == .waiting(.planApproval))
        #expect(
            status(after: [event(.userPromptSubmit), event(.notification, notification: "elicitation_dialog")])
                == .waiting(.input))
    }

    @Test func idleReminderDoesNotChangeTheStatus() {
        let events = [event(.userPromptSubmit), event(.stop), event(.notification, notification: "idle_prompt")]
        #expect(status(after: events) == .idle)
    }

    @Test func backgroundActivityDoesNotWakeAnIdleSession() {
        let events = [event(.userPromptSubmit), event(.stop), event(.subagentStop), event(.postToolUse, tool: "Read")]
        #expect(status(after: events) == .idle)
    }

    @Test func aSessionFirstSeenMidTurnIsWorking() {
        #expect(status(after: [event(.postToolUse, tool: "Edit")]) == .working)
        #expect(status(after: [event(.other("CwdChanged"))]) == .idle)
    }

    @Test func aResumedSessionComesBack() {
        #expect(status(after: [event(.sessionEnd), event(.sessionStart)]) == .idle)
    }

    @Test func statusSinceMovesOnlyWhenTheStatusChanges() {
        let registry = registry(after: [
            event(.userPromptSubmit), event(.preToolUse, tool: "Read"), event(.postToolUse, tool: "Read"),
        ])
        let session = registry.sessions["s1"]
        #expect(session?.statusSince == start)
        #expect(session?.lastEventAt == start.addingTimeInterval(2))
    }

    @Test func reportsStatusChangesOnly() {
        var registry = SessionRegistry()
        #expect(registry.apply(event(.sessionStart)) == StatusChange(sessionID: "s1", from: nil, to: .idle))
        #expect(registry.apply(event(.userPromptSubmit)) == StatusChange(sessionID: "s1", from: .idle, to: .working))
        #expect(registry.apply(event(.preToolUse, tool: "Read")) == nil)
    }

    @Test func remembersWhereTheSessionRuns() {
        var registry = SessionRegistry()
        let terminal = TerminalLocation(program: "Apple_Terminal", paneIDs: ["TERM_SESSION_ID": "T1"])
        registry.apply(HookEvent(sessionID: "s1", kind: .sessionStart, cwd: "/tmp/demo"), terminal: terminal)
        registry.apply(event(.userPromptSubmit))
        #expect(registry.sessions["s1"]?.terminal == terminal)
        #expect(registry.sessions["s1"]?.cwd == "/tmp/demo")
    }

    @Test func listsWaitingSessionsLongestWaitingFirst() {
        let registry = registry(after: [
            event(.permissionRequest, session: "late"),
            event(.userPromptSubmit, session: "busy"),
            event(.permissionRequest, session: "later"),
        ])
        #expect(registry.needingAttention.map(\.id) == ["late", "later"])
    }
}
