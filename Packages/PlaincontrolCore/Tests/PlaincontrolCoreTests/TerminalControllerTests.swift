import CoreGraphics
import Foundation
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
        #expect(scripts[0].contains("set miniaturized of aWindow to false"))
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

    @Test func opensAWindowAsTheTerminalDoesWithoutAFolder() throws {
        var scripts: [String] = []
        let controller = ITerm2Controller { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: nil)
        #expect(scripts[0].contains("create window with default profile"))
        #expect(!scripts[0].contains("write text"))
        try controller.openWindow(in: nil, running: "claude")
        #expect(scripts[1].contains(#"write text "claude""#))
        #expect(!scripts[1].contains("cd "))
    }

    @Test func opensAWindowAtAFrame() throws {
        var scripts: [String] = []
        let controller = ITerm2Controller { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: "/work/app", frame: CGRect(x: -230, y: -1400, width: 840, height: 1390))
        #expect(scripts[0].contains("set bounds of newWindow to {-230, -1400, 610, -10}"))
        try controller.openWindow(in: "/work/app")
        #expect(!scripts[1].contains("bounds"))
    }

    @Test func opensAWindowMinimisedInTheBackground() throws {
        var scripts: [String] = []
        let controller = ITerm2Controller { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: "/work/app", running: "make dev", minimized: true)
        #expect(scripts[0].contains("set miniaturized of newWindow to true"))
        #expect(!scripts[0].contains("activate"))
        try controller.openWindow(in: "/work/app")
        #expect(!scripts[1].contains("miniaturized"))
        #expect(scripts[1].contains("activate"))
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
@Suite struct TerminalAppControllerTests {
    func terminal(_ tty: String?, program: String = "Apple_Terminal") -> TerminalLocation {
        TerminalLocation(program: program, paneIDs: ["TERM_SESSION_ID": "6B9F3C2A"], tty: tty)
    }

    @Test func findsTheTabByItsTerminalDevice() throws {
        #expect(TerminalAppController.tty(in: terminal("/dev/ttys003")) == "/dev/ttys003")
        var scripts: [String] = []
        let controller = TerminalAppController { script in
            scripts.append(script)
            return "focused"
        }
        try controller.focus(terminal("/dev/ttys003"))
        #expect(scripts.count == 1)
        #expect(scripts[0].contains(#"if tty of aTab is "/dev/ttys003" then"#))
    }

    @Test func leavesOtherTerminalsAlone() {
        #expect(TerminalAppController.tty(in: terminal(nil)) == nil)
        #expect(TerminalAppController.tty(in: terminal("/dev/ttys003", program: "tmux")) == nil)
        #expect(TerminalAppController.tty(in: terminal("/dev/ttys003", program: "iTerm.app")) == nil)
    }

    @Test func refusesDevicesTheKernelWouldNotName() {
        #expect(TerminalAppController.tty(in: terminal("ttys003")) == nil)
        #expect(TerminalAppController.tty(in: terminal("/dev/")) == nil)
        #expect(TerminalAppController.tty(in: terminal(#"/dev/ttys0" & quit & ""#)) == nil)
    }

    @Test func reportsWhatTheScriptFound() {
        #expect(throws: TerminalControlError.terminalNotRunning) {
            try TerminalAppController { _ in "not running" }.focus(terminal("/dev/ttys003"))
        }
        #expect(throws: TerminalControlError.paneNotFound) {
            try TerminalAppController { _ in "not found" }.focus(terminal("/dev/ttys003"))
        }
    }

    @Test func opensAWindowInAFolderWithItsNameQuoted() throws {
        var scripts: [String] = []
        let controller = TerminalAppController { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: #"/work/a "quoted" \ folder"#, running: "claude")
        #expect(
            scripts[0].contains(#"do script "cd " & quoted form of "/work/a \"quoted\" \\ folder" & " && " & "claude""#)
        )
    }

    @Test func usesTheWindowTerminalOpensWhenItStarts() throws {
        var scripts: [String] = []
        let controller = TerminalAppController { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: "/work/app")
        #expect(scripts[0].contains(#"do script "cd " & quoted form of "/work/app" in window 1"#))
        // Without anything to type, the window it opens is left as it is, and a new one is empty.
        try controller.openWindow(in: nil)
        #expect(!scripts[1].contains("in window 1"))
        #expect(scripts[1].contains(#"do script """#))
    }

    @Test func leavesPlacingTheWindowToTheCaller() throws {
        var scripts: [String] = []
        let controller = TerminalAppController { script in
            scripts.append(script)
            return ""
        }
        #expect(!controller.placesWindows)
        try controller.openWindow(in: "/work/app", frame: CGRect(x: -230, y: -1400, width: 840, height: 1390))
        #expect(!scripts[0].contains("bounds"))
    }

    @Test func opensAWindowMinimisedInTheBackground() throws {
        var scripts: [String] = []
        let controller = TerminalAppController { script in
            scripts.append(script)
            return ""
        }
        try controller.openWindow(in: "/work/app", running: "make dev", minimized: true)
        #expect(scripts[0].contains("set miniaturized of window 1 to true"))
        #expect(!scripts[0].contains("activate"))
        try controller.openWindow(in: "/work/app")
        #expect(!scripts[1].contains("miniaturized"))
    }

    @Test func writesScriptsThatCompile() throws {
        let scripts = [
            TerminalAppController.focusScript(tty: "/dev/ttys003"),
            TerminalAppController.openWindowScript(directory: "/work/app", command: "claude"),
            TerminalAppController.openWindowScript(directory: nil, command: nil),
            TerminalAppController.openWindowScript(directory: "/work/app", command: "make dev", minimized: true),
        ]
        for source in scripts {
            var error: NSDictionary?
            #expect(NSAppleScript(source: source)?.compileAndReturnError(&error) == true, "\(source)")
        }
    }
}

@MainActor
@Suite struct TerminalControllersTests {
    struct Fake: TerminalController {
        let program: String
        var bundleIdentifier: String { "example.\(program)" }
        var name: String { program }
        let focused: @MainActor @Sendable () -> Void

        func canFocus(_ location: TerminalLocation) -> Bool { location.program == program }
        func focus(_ location: TerminalLocation) throws(TerminalControlError) { focused() }
        func openWindow(in directory: String?, running command: String?, frame: CGRect?, minimized: Bool) {}
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

    @Test func findsTheControllerForAnApp() {
        let terminals = TerminalControllers([Fake(program: "A") {}, Fake(program: "B") {}])
        #expect(terminals.controller(forApp: "example.B")?.name == "B")
        #expect(terminals.controller(forApp: "example.C") == nil)
    }

    @Test func cannotFocusAnUnknownOrMissingLocation() {
        let terminals = TerminalControllers([Fake(program: "A") {}])
        #expect(!terminals.canFocus(TerminalLocation(program: "B")))
        #expect(!terminals.canFocus(nil))
        #expect(throws: TerminalControlError.unsupported) { try terminals.focus(nil) }
    }
}
