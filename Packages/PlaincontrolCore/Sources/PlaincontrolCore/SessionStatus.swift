/// Where a Claude Code session stands, as far as Plaincontrol knows.
public enum SessionStatus: Sendable, Equatable, Codable {
    /// Claude is working: a prompt was submitted and the turn has not ended.
    case working
    /// Claude cannot continue until the user responds.
    case waiting(WaitingReason)
    /// Claude is not working and not asking anything: a turn ended, or no prompt was sent yet.
    case idle
    /// The session ended.
    case gone

    /// Whether the session needs the user before it can continue.
    public var needsAttention: Bool {
        if case .waiting = self { true } else { false }
    }
}

/// What a waiting session needs from the user.
public enum WaitingReason: String, Sendable, Equatable, Codable {
    /// Approve or deny a tool call.
    case permission
    /// Answer a question Claude asked with its question tool.
    case question
    /// Approve or reject a proposed plan.
    case planApproval
    /// Respond to another kind of request, such as a form from an MCP server.
    case input
}
