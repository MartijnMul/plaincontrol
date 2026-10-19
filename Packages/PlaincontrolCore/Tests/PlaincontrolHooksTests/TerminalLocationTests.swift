import Testing

@testable import PlaincontrolHooks

@Test func keepsOnlyTheTerminalAppAndPaneVariables() {
    let location = TerminalLocation(environment: [
        "TERM_PROGRAM": "iTerm.app",
        "__CFBundleIdentifier": "com.googlecode.iterm2",
        "ITERM_SESSION_ID": "w0t1p0:ABC",
        "TMUX_PANE": "%3",
        "HOME": "/Users/example",
        "API_TOKEN": "do-not-keep",
    ])
    #expect(
        location
            == TerminalLocation(
                program: "iTerm.app", paneIDs: ["ITERM_SESSION_ID": "w0t1p0:ABC", "TMUX_PANE": "%3"],
                app: "com.googlecode.iterm2"))
}

@Test func knowsTheAppWithoutATerminalProgram() {
    let location = TerminalLocation(environment: ["__CFBundleIdentifier": "com.example.Editor"])
    #expect(location == TerminalLocation(program: nil, app: "com.example.Editor"))
}

@Test func returnsNilWithoutAnyTerminal() {
    #expect(TerminalLocation(environment: ["HOME": "/Users/example", "TERM_PROGRAM": ""]) == nil)
}
