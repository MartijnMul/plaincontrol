import Testing

@testable import PlaincontrolCore

struct SessionAlertTests {
    private func change(_ from: SessionStatus?, _ to: SessionStatus) -> StatusChange {
        StatusChange(sessionID: "s1", from: from, to: to)
    }

    @Test func alertsWhenASessionStartsWaiting() {
        #expect(SessionAlert(for: change(.working, .waiting(.permission))) == .waiting(.permission))
        #expect(SessionAlert(for: change(.waiting(.question), .waiting(.permission))) == .waiting(.permission))
        #expect(SessionAlert(for: change(nil, .waiting(.question))) == .waiting(.question))
    }

    @Test func alertsWhenAWorkingSessionFinishes() {
        #expect(SessionAlert(for: change(.working, .idle)) == .finished)
    }

    @Test func staysQuietOtherwise() {
        #expect(SessionAlert(for: change(nil, .idle)) == nil)
        #expect(SessionAlert(for: change(.idle, .working)) == nil)
        #expect(SessionAlert(for: change(.waiting(.permission), .working)) == nil)
        #expect(SessionAlert(for: change(.waiting(.permission), .idle)) == nil)
        #expect(SessionAlert(for: change(.working, .gone)) == nil)
    }

    @Test func workingAgainOrEndingWithdrawsAShownAlert() {
        #expect(change(.waiting(.permission), .working).withdrawsShownAlert)
        #expect(change(.idle, .working).withdrawsShownAlert)
        #expect(change(.idle, .gone).withdrawsShownAlert)
        #expect(!change(.working, .idle).withdrawsShownAlert)
        #expect(!change(.working, .waiting(.question)).withdrawsShownAlert)
    }
}
