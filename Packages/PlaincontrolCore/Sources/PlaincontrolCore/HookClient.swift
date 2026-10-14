import Darwin

/// Sends hook envelopes to the app.
public enum HookClient {
    /// Sends one envelope over the socket at `path`, waiting at most `timeout` seconds.
    /// Throws when nothing listens there.
    public static func send(_ envelope: HookEnvelope, to path: String, timeout: Double = 0.5) throws {
        let line = try envelope.line()
        let fd = try UnixSocket.make()
        defer { close(fd) }
        UnixSocket.setTimeouts(fd, seconds: timeout)
        try UnixSocket.connect(fd, to: path)
        try UnixSocket.writeAll(fd, Array(line))
    }
}
