import Testing

@testable import PlaincontrolCore

@Test func onlyWaitingNeedsAttention() {
    #expect(SessionStatus.allCases.filter(\.needsAttention) == [.waiting])
}
