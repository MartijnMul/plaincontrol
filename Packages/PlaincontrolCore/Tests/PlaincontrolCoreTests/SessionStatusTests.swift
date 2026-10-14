import Testing

@testable import PlaincontrolCore

@Test func onlyWaitingNeedsAttention() {
    #expect(SessionStatus.waiting(.permission).needsAttention)
    #expect(SessionStatus.waiting(.question).needsAttention)
    #expect(!SessionStatus.working.needsAttention)
    #expect(!SessionStatus.idle.needsAttention)
    #expect(!SessionStatus.gone.needsAttention)
}
