import Foundation
import Testing

@testable import PlaincontrolHooks

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

    @Test func findsTheTerminalOfAProcessThatHasOne() throws {
        // Run from a terminal, the tests have one; run by Xcode or CI, they may not.
        let process = try #require(SessionProcess(pid: getpid()))
        if let tty = ttyname(STDIN_FILENO).map({ String(cString: $0) }) {
            #expect(process.terminalDevice == tty)
        }
        let launchd = try #require(SessionProcess(pid: 1))
        #expect(launchd.terminalDevice == nil)
    }

    @Test func readsTheClaudeCodeProcessFromTheEnvironment() {
        #expect(SessionProcess(environment: ["CLAUDE_PID": String(getpid())])?.pid == getpid())
        #expect(SessionProcess(environment: ["CLAUDE_PID": "not a number"]) == nil)
        #expect(SessionProcess(environment: [:]) == nil)
    }
}
