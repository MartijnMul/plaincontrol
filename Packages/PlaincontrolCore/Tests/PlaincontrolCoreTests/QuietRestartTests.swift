import Testing

@testable import PlaincontrolCore

@Suite struct QuietRestartTests {
    @Test func restartsOnlyWhileTheUserIsAwayAndNoWindowIsOpen() {
        let away = QuietRestart.idleTime
        #expect(QuietRestart.isGoodMoment(idleFor: away, screenLocked: false, windowOpen: false))
        #expect(QuietRestart.isGoodMoment(idleFor: 0, screenLocked: true, windowOpen: false))
        #expect(!QuietRestart.isGoodMoment(idleFor: away - 1, screenLocked: false, windowOpen: false))
        #expect(!QuietRestart.isGoodMoment(idleFor: away, screenLocked: true, windowOpen: true))
    }
}
