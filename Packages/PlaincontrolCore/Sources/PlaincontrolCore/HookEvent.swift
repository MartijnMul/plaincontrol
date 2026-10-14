/// One event from a Claude Code hook, reduced to the fields Plaincontrol needs.
///
/// Decoding is tolerant: only `session_id` and `hook_event_name` are required, and unknown
/// events and fields are ignored, so a newer Claude Code keeps working. Prompt text, tool
/// inputs and assistant messages are never decoded.
public struct HookEvent: Sendable, Equatable {
    public var sessionID: String
    public var kind: Kind
    /// The working directory of the session when the hook ran.
    public var cwd: String?
    /// The tool a tool event is about, such as `Bash` or `AskUserQuestion`.
    public var toolName: String?
    /// Which kind of notification a `Notification` event is, such as `permission_prompt`.
    public var notificationType: String?
    /// The custom title of the session, when the user set one.
    public var sessionTitle: String?

    public init(
        sessionID: String,
        kind: Kind,
        cwd: String? = nil,
        toolName: String? = nil,
        notificationType: String? = nil,
        sessionTitle: String? = nil
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.cwd = cwd
        self.toolName = toolName
        self.notificationType = notificationType
        self.sessionTitle = sessionTitle
    }
}

extension HookEvent {
    /// The hook event names Plaincontrol acts on; anything else is `other`.
    public enum Kind: Sendable, Equatable {
        case sessionStart
        case userPromptSubmit
        case preToolUse
        case permissionRequest
        case postToolUse
        case postToolUseFailure
        case postToolBatch
        case subagentStart
        case subagentStop
        case notification
        case stop
        case stopFailure
        case sessionEnd
        case other(String)

        public init(name: String) {
            switch name {
            case "SessionStart": self = .sessionStart
            case "UserPromptSubmit": self = .userPromptSubmit
            case "PreToolUse": self = .preToolUse
            case "PermissionRequest": self = .permissionRequest
            case "PostToolUse": self = .postToolUse
            case "PostToolUseFailure": self = .postToolUseFailure
            case "PostToolBatch": self = .postToolBatch
            case "SubagentStart": self = .subagentStart
            case "SubagentStop": self = .subagentStop
            case "Notification": self = .notification
            case "Stop": self = .stop
            case "StopFailure": self = .stopFailure
            case "SessionEnd": self = .sessionEnd
            default: self = .other(name)
            }
        }
    }
}

extension HookEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case notificationType = "notification_type"
        case sessionTitle = "session_title"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(String.self, forKey: .sessionID),
            kind: Kind(name: try container.decode(String.self, forKey: .hookEventName)),
            cwd: try? container.decodeIfPresent(String.self, forKey: .cwd),
            toolName: try? container.decodeIfPresent(String.self, forKey: .toolName),
            notificationType: try? container.decodeIfPresent(String.self, forKey: .notificationType),
            sessionTitle: try? container.decodeIfPresent(String.self, forKey: .sessionTitle)
        )
    }
}
