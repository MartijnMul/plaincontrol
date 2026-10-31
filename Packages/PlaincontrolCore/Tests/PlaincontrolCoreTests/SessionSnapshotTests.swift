import Foundation
import PlaincontrolHooks
import Testing

@testable import PlaincontrolCore

@Suite struct SessionSnapshotTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let running = SessionProcess(pid: 101, startTime: 1)
    let ended = SessionProcess(pid: 102, startTime: 2)

    func registry() -> SessionRegistry {
        var registry = SessionRegistry()
        registry.apply(HookEvent(sessionID: "a", kind: .sessionStart, cwd: "/work/app"), at: now)
        registry.apply(HookEvent(sessionID: "a", kind: .permissionRequest), at: now)
        registry.apply(HookEvent(sessionID: "b", kind: .sessionStart), at: now)
        registry.apply(HookEvent(sessionID: "c", kind: .sessionStart), at: now)
        registry.apply(HookEvent(sessionID: "c", kind: .sessionEnd), at: now)
        registry.apply(HookEvent(sessionID: "d", kind: .sessionStart), at: now)
        return registry
    }

    @Test func keepsTheSessionsStillRunningWithAKnownProcess() throws {
        let processes = ["a": running, "b": ended, "c": running]
        let snapshot = SessionSnapshot(registry(), processes: processes, at: now)
        #expect(snapshot.entries.map(\.session.id) == ["a", "b"])

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
        let restored = decoded.restorable(at: now + 30) { $0 == running }
        #expect(restored.map(\.session.id) == ["a"])
        #expect(restored.first?.session.status == .waiting(.permission))
        #expect(restored.first?.session.cwd == "/work/app")
    }

    @Test func usesOnlyASnapshotFromARestart() {
        let snapshot = SessionSnapshot(registry(), processes: ["a": running], at: now)
        #expect(snapshot.restorable(at: now + SessionSnapshot.maximumAge) { _ in true }.count == 1)
        #expect(snapshot.restorable(at: now + SessionSnapshot.maximumAge + 1) { _ in true }.isEmpty)
        #expect(snapshot.restorable(at: now - 1) { _ in true }.isEmpty)
    }

    @Test func restoresOnlySessionsNotHeardFromSince() {
        var registry = SessionRegistry()
        registry.apply(HookEvent(sessionID: "a", kind: .userPromptSubmit), at: now)
        var saved = Session(id: "a", status: .idle, statusSince: now - 60, lastEventAt: now - 60)
        registry.restore(saved)
        #expect(registry.sessions["a"]?.status == .working)
        saved = Session(id: "b", status: .waiting(.question), statusSince: now - 60, lastEventAt: now - 60)
        registry.restore(saved)
        #expect(registry.needingAttention.map(\.id) == ["b"])
        registry.restore(Session(id: "c", status: .gone, statusSince: now, lastEventAt: now))
        #expect(registry.sessions["c"] == nil)
    }
}
