import Darwin
import Dispatch
import Foundation

/// Listens on a Unix domain socket for hook envelopes and hands each one to a handler.
///
/// Each connection carries lines of JSON until the sender closes it. Envelopes are handled
/// one at a time, in the order they arrive, on a private queue. The socket is readable and
/// writable by the current user only.
public final class HookServer: @unchecked Sendable {
    // `source` is only touched by `start()` and `stop()`, which callers use from one thread;
    // everything else is immutable or confined to `queue`.
    private let path: String
    private let handler: @Sendable (HookEnvelope) -> Void
    private let queue = DispatchQueue(label: "Plaincontrol.HookServer")
    private var source: (any DispatchSourceRead)?

    /// The largest amount of data accepted on one connection.
    static let connectionLimit = 64 * 1024

    public init(path: String, handler: @escaping @Sendable (HookEnvelope) -> Void) {
        self.path = path
        self.handler = handler
    }

    deinit {
        source?.cancel()
    }

    /// Starts listening. Throws when another process already listens on the path.
    public func start() throws {
        guard source == nil else { return }
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try removeStaleSocket()

        let listener = try UnixSocket.make()
        do {
            let bound = try UnixSocket.withAddress(path) { bind(listener, $0, $1) }
            guard bound == 0 else { throw UnixSocketError.system(call: "bind", errno: errno) }
            chmod(path, 0o600)
            guard listen(listener, 16) == 0 else { throw UnixSocketError.system(call: "listen", errno: errno) }
            _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)
        } catch {
            close(listener)
            throw error
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        let path = path
        source.setEventHandler { [weak self] in self?.acceptPending(on: listener) }
        source.setCancelHandler {
            close(listener)
            unlink(path)
        }
        source.resume()
        self.source = source
    }

    /// Stops listening and removes the socket.
    public func stop() {
        source?.cancel()
        source = nil
    }

    /// Removes a socket file left behind by a process that is gone, and refuses to take over
    /// one that is still in use.
    private func removeStaleSocket() throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let probe = try UnixSocket.make()
        defer { close(probe) }
        if (try? UnixSocket.connect(probe, to: path)) != nil {
            throw UnixSocketError.alreadyListening(path)
        }
        unlink(path)
    }

    private func acceptPending(on listener: Int32) {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }
            receive(from: connection)
        }
    }

    private func receive(from connection: Int32) {
        defer { close(connection) }
        // Accepted sockets inherit the listener's non-blocking flag; read them blocking,
        // with a timeout so a stalled sender cannot hold up the queue.
        _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
        UnixSocket.setTimeouts(connection, seconds: 1)
        let bytes = UnixSocket.readAll(connection, limit: Self.connectionLimit)
        for line in bytes.split(separator: 0x0A) {
            if let envelope = try? HookEnvelope.decode(line: Data(line)) {
                handler(envelope)
            }
        }
    }
}
