import Foundation
import Testing

@testable import PlaincontrolCore

/// Starts a process that exits after `seconds`.
private func startSleeping(_ seconds: Double) throws -> Process {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sleep")
    process.arguments = [String(seconds)]
    try process.run()
    return process
}

struct SessionProcessTests {
    @Test func findsARunningProcess() throws {
        let process = try #require(SessionProcess(pid: getpid()))
        #expect(process.startTime > 0)
        #expect(process.isRunning)
    }

    @Test func aProcessThatExitedIsNotRunning() throws {
        let child = try startSleeping(0)
        let process = try #require(SessionProcess(pid: child.processIdentifier))
        child.waitUntilExit()
        #expect(!process.isRunning)
    }

    @Test func anotherProcessWithTheSameIDIsNotTheSame() throws {
        let process = try #require(SessionProcess(pid: getpid()))
        var reused = process
        reused.startTime += 1
        #expect(!reused.isRunning)
    }

    @Test func readsTheClaudeCodeProcessFromTheEnvironment() {
        #expect(SessionProcess(environment: ["CLAUDE_PID": String(getpid())])?.pid == getpid())
        #expect(SessionProcess(environment: ["CLAUDE_PID": "not a number"]) == nil)
        #expect(SessionProcess(environment: [:]) == nil)
    }
}

@MainActor
struct ProcessWatcherTests {
    @Test func reportsWhenTheProcessExits() async throws {
        let child = try startSleeping(0.2)
        let process = try #require(SessionProcess(pid: child.processIdentifier))
        let (exits, continuation) = AsyncStream.makeStream(of: String.self)
        let watcher = ProcessWatcher { continuation.yield($0) }
        watcher.watch(process, for: "s1")
        var iterator = exits.makeAsyncIterator()
        #expect(await iterator.next() == "s1")
    }

    @Test func reportsAProcessThatAlreadyExited() async throws {
        let child = try startSleeping(0)
        let process = try #require(SessionProcess(pid: child.processIdentifier))
        child.waitUntilExit()
        var exited: [String] = []
        let watcher = ProcessWatcher { exited.append($0) }
        watcher.watch(process, for: "s1")
        #expect(exited == ["s1"])
    }

    @Test func aNewProcessReplacesTheOldOne() async throws {
        let first = try startSleeping(0.1)
        let firstProcess = try #require(SessionProcess(pid: first.processIdentifier))
        let current = try #require(SessionProcess(pid: getpid()))
        var exited: [String] = []
        let watcher = ProcessWatcher { exited.append($0) }
        watcher.watch(firstProcess, for: "s1")
        watcher.watch(current, for: "s1")
        first.waitUntilExit()
        try await Task.sleep(for: .milliseconds(100))
        #expect(exited.isEmpty)
    }
}
