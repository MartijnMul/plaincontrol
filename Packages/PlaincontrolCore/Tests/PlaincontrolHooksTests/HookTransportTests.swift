import Foundation
import Testing

@testable import PlaincontrolHooks

struct HookTransportTests {
    /// A short socket path: socket addresses hold only about 100 bytes, and the default
    /// temporary directory on macOS is long.
    private let path = "/tmp/plaincontrol-test-\(UUID().uuidString.prefix(8)).sock"

    private let envelope = HookEnvelope(
        event: HookEvent(sessionID: "s1", kind: .permissionRequest, cwd: "/tmp/demo", toolName: "Bash"),
        terminal: TerminalLocation(program: "iTerm.app", paneIDs: ["ITERM_SESSION_ID": "w0t0p0:ABC"]),
        process: SessionProcess(pid: 4242, startTime: 1_000_000_000_000),
        sentAt: Date(timeIntervalSince1970: 1_000_000)
    )

    @Test func envelopeIsOneLineOfJSON() throws {
        let line = try envelope.line()
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        #expect(try HookEnvelope.decode(line: line) == envelope)
    }

    @Test func deliversEnvelopesInOrder() async throws {
        let (received, continuation) = AsyncStream.makeStream(of: HookEnvelope.self)
        let server = HookServer(path: path) { continuation.yield($0) }
        try server.start()
        defer { server.stop() }

        var second = envelope
        second.event.kind = .postToolUse
        try HookClient.send(envelope, to: path)
        try HookClient.send(second, to: path)

        var iterator = received.makeAsyncIterator()
        #expect(await iterator.next() == envelope)
        #expect(await iterator.next() == second)
    }

    @Test func socketIsPrivateToTheUser() throws {
        let server = HookServer(path: path) { _ in }
        try server.start()
        defer { server.stop() }
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func sendingFailsWhenNothingListens() {
        #expect(throws: UnixSocketError.self) { try HookClient.send(envelope, to: path) }
    }

    @Test func refusesToTakeOverASocketInUse() throws {
        let first = HookServer(path: path) { _ in }
        try first.start()
        defer { first.stop() }
        #expect(throws: UnixSocketError.alreadyListening(path)) {
            try HookServer(path: path) { _ in }.start()
        }
    }

    @Test func replacesASocketLeftBehind() async throws {
        // A crashed app leaves its socket file behind, with nothing listening on it.
        let stale = try UnixSocket.make()
        #expect(try UnixSocket.withAddress(path) { bind(stale, $0, $1) } == 0)
        close(stale)
        #expect(FileManager.default.fileExists(atPath: path))

        let (received, continuation) = AsyncStream.makeStream(of: HookEnvelope.self)
        let server = HookServer(path: path) { continuation.yield($0) }
        try server.start()
        defer { server.stop() }
        try HookClient.send(envelope, to: path)
        var iterator = received.makeAsyncIterator()
        #expect(await iterator.next() == envelope)
    }

    @Test func rejectsAPathThatDoesNotFit() {
        let long = "/tmp/" + String(repeating: "x", count: 120)
        #expect(throws: UnixSocketError.pathTooLong(long)) { try HookClient.send(envelope, to: long) }
    }

    @Test func socketPathFollowsTheEnvironment() {
        #expect(HookSocket.path(environment: ["PLAINCONTROL_SOCKET": "/tmp/x.sock"]) == "/tmp/x.sock")
        #expect(HookSocket.path(environment: [:]).hasSuffix("/Application Support/Plaincontrol/hooks.sock"))
        #expect(
            HookSocket.path(environment: [:], appName: HookSocket.developmentAppName)
                .hasSuffix("/Application Support/Plaincontrol Dev/hooks.sock"))
    }
}
