/// Where a Claude Code session stands, as far as Plaincontrol knows.
public enum SessionStatus: String, Sendable, Codable, CaseIterable {
    /// Claude is working: a prompt was submitted and the answer has not finished.
    case working
    /// Claude asked a question, wants a permission, or has been idle long enough to notify.
    case waiting
    /// Claude stopped without asking anything.
    case finished
    /// The session ended, or stopped reporting.
    case gone

    /// Whether the session needs the user before it can continue.
    public var needsAttention: Bool {
        self == .waiting
    }
}
