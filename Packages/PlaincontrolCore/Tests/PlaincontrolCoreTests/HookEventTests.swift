import Foundation
import Testing

@testable import PlaincontrolCore

struct HookEventTests {
    private func decode(_ json: String) throws -> HookEvent {
        try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    }

    @Test func decodesTheFieldsItNeeds() throws {
        let event = try decode(
            """
            {
              "session_id": "s1",
              "transcript_path": "/Users/example/.claude/projects/demo/s1.jsonl",
              "cwd": "/Users/example/demo",
              "permission_mode": "default",
              "hook_event_name": "Notification",
              "message": "Claude needs your permission",
              "title": "Permission needed",
              "notification_type": "permission_prompt"
            }
            """)
        #expect(
            event
                == HookEvent(
                    sessionID: "s1", kind: .notification, cwd: "/Users/example/demo",
                    notificationType: "permission_prompt"))
    }

    @Test func readsToolNameAndSessionTitle() throws {
        let event = try decode(
            """
            {"session_id": "s1", "hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
             "tool_input": {"questions": []}, "session_title": "Fix the build"}
            """)
        #expect(event.kind == .preToolUse)
        #expect(event.toolName == "AskUserQuestion")
        #expect(event.sessionTitle == "Fix the build")
    }

    @Test func keepsNothingOfThePrompt() throws {
        let event = try decode(
            """
            {"session_id": "s1", "hook_event_name": "UserPromptSubmit", "prompt": "a secret plan"}
            """)
        #expect(event == HookEvent(sessionID: "s1", kind: .userPromptSubmit))
        #expect(!String(describing: event).contains("secret"))
    }

    @Test func unknownEventsAndOddFieldsDoNotFail() throws {
        let event = try decode(
            """
            {"session_id": "s1", "hook_event_name": "SomethingNew", "cwd": 42, "extra": {"a": [1, 2]}}
            """)
        #expect(event.kind == .other("SomethingNew"))
        #expect(event.cwd == nil)
    }

    @Test(arguments: [
        #"{"hook_event_name": "Stop"}"#,
        #"{"session_id": "s1"}"#,
        #"not json"#,
    ])
    func rejectsEventsWithoutSessionOrName(_ json: String) {
        #expect(throws: (any Error).self) { try decode(json) }
    }
}
