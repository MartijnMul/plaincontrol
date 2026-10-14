import PlaincontrolHooks
import Testing

@testable import PlaincontrolCore

@MainActor
@Suite struct ITerm2ControllerTests {
    let paneID = "6B9F3C2A-0D4E-4F1A-9C8B-7E6D5A4B3C21"

    func iTerm(_ sessionID: String?, program: String = "iTerm.app") -> TerminalLocation {
        TerminalLocation(program: program, paneIDs: sessionID.map { ["ITERM_SESSION_ID": $0] } ?? [:])
    }

    @Test func findsThePaneIDAfterTheColon() {
        #expect(ITerm2Controller.paneID(in: iTerm("w0t1p0:\(paneID)")) == paneID)
    }

    @Test func leavesOtherTerminalsAlone() {
        #expect(ITerm2Controller.paneID(in: iTerm(nil)) == nil)
        #expect(ITerm2Controller.paneID(in: iTerm("w0t1p0:\(paneID)", program: "tmux")) == nil)
        #expect(ITerm2Controller.paneID(in: TerminalLocation(program: "Apple_Terminal")) == nil)
    }

    @Test func refusesIDsThatAreNotUUIDs() {
        #expect(ITerm2Controller.paneID(in: iTerm("w0t1p0:")) == nil)
        #expect(ITerm2Controller.paneID(in: iTerm("w0t1p0:AB\" & quit & \"CD")) == nil)
    }

    @Test func looksUpThePaneByItsID() throws {
        var scripts: [String] = []
        let controller = ITerm2Controller { script in
            scripts.append(script)
            return "focused"
        }
        try controller.focus(iTerm("w0t1p0:\(paneID)"))
        #expect(scripts.count == 1)
        #expect(scripts[0].contains("unique id of aSession is \"\(paneID)\""))
    }

    @Test func reportsWhatTheScriptFound() {
        #expect(throws: TerminalControlError.terminalNotRunning) {
            try ITerm2Controller { _ in "not running" }.focus(iTerm("w0t1p0:\(paneID)"))
        }
        #expect(throws: TerminalControlError.paneNotFound) {
            try ITerm2Controller { _ in "not found" }.focus(iTerm("w0t1p0:\(paneID)"))
        }
        #expect(throws: TerminalControlError.notAuthorized) {
            try ITerm2Controller { _ throws(TerminalControlError) in throw .notAuthorized }
                .focus(iTerm("w0t1p0:\(paneID)"))
        }
    }

    @Test func opensAWindowInAFolderWithItsNameQuoted() throws {
        var scripts: [String] = []
        let controller = ITerm2Controller { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: #"/work/a "quoted" \ folder"#, running: "claude")
        #expect(scripts.count == 1)
        #expect(scripts[0].contains(#"quoted form of "/work/a \"quoted\" \\ folder" & " && " & "claude""#))
    }

    @Test func opensAWindowWithNothingRunning() throws {
        var scripts: [String] = []
        let controller = ITerm2Controller { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: "/work/app")
        #expect(scripts.count == 1)
        #expect(scripts[0].contains(#"write text "cd " & quoted form of "/work/app""#))
        #expect(!scripts[0].contains("&&"))
    }

    @Test func runsNoScriptForAnotherTerminal() {
        let controller = ITerm2Controller { _ in
            Issue.record("ran a script")
            return ""
        }
        #expect(throws: TerminalControlError.unsupported) {
            try controller.focus(TerminalLocation(program: "Apple_Terminal"))
        }
    }
}

@MainActor
@Suite struct TerminalControllersTests {
    struct Fake: TerminalController {
        let program: String
        var bundleIdentifier: String { "example.\(program)" }
        let focused: @MainActor @Sendable () -> Void

        func canFocus(_ location: TerminalLocation) -> Bool { location.program == program }
        func focus(_ location: TerminalLocation) throws(TerminalControlError) { focused() }
    }

    @Test func picksTheControllerForTheTerminal() throws {
        var focused: [String] = []
        let terminals = TerminalControllers([
            Fake(program: "A") { focused.append("A") },
            Fake(program: "B") { focused.append("B") },
        ])
        try terminals.focus(TerminalLocation(program: "B"))
        #expect(focused == ["B"])
    }

    @Test func cannotFocusAnUnknownOrMissingLocation() {
        let terminals = TerminalControllers([Fake(program: "A") {}])
        #expect(!terminals.canFocus(TerminalLocation(program: "B")))
        #expect(!terminals.canFocus(nil))
        #expect(throws: TerminalControlError.unsupported) { try terminals.focus(nil) }
    }
}
