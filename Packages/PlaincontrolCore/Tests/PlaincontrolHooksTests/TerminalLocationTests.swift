import Testing

@testable import PlaincontrolHooks

@Test func keepsOnlyTheTerminalAndPaneVariables() {
    let location = TerminalLocation(environment: [
        "TERM_PROGRAM": "iTerm.app",
        "ITERM_SESSION_ID": "w0t1p0:ABC",
        "TMUX_PANE": "%3",
        "HOME": "/Users/example",
        "API_TOKEN": "do-not-keep",
    ])
    #expect(
        location
            == TerminalLocation(program: "iTerm.app", paneIDs: ["ITERM_SESSION_ID": "w0t1p0:ABC", "TMUX_PANE": "%3"]))
}

@Test func returnsNilWithoutAnyTerminal() {
    #expect(TerminalLocation(environment: ["HOME": "/Users/example", "TERM_PROGRAM": ""]) == nil)
}
