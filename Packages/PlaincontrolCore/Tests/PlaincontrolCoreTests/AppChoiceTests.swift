import Testing

@testable import PlaincontrolCore

@Suite struct AppChoiceTests {
    let iTerm2 = "com.googlecode.iterm2"
    let ghostty = "com.mitchellh.ghostty"
    let terminal = "com.apple.Terminal"
    let vsCode = "com.microsoft.VSCode"
    let cursor = "com.todesktop.230313mzl4w4u92"
    let zed = "dev.zed.Zed"

    func installed(_ apps: String...) -> (String) -> Bool { { apps.contains($0) } }

    // MARK: Terminal

    @Test func opensTheTerminalTheUserUsesMost() {
        let choice = AppChoice.terminal(
            setting: nil, ranked: [terminal, iTerm2], supported: [iTerm2, terminal],
            isInstalled: installed(iTerm2, terminal))
        #expect(choice == AppChoice.Terminal(app: terminal))
    }

    @Test func fallsBackToASupportedTerminalAndSaysWhichOneItCannotOpen() {
        let choice = AppChoice.terminal(
            setting: nil, ranked: [ghostty], supported: [iTerm2], isInstalled: installed(iTerm2, ghostty))
        #expect(choice == AppChoice.Terminal(app: iTerm2, unsupported: ghostty))
    }

    @Test func picksTheFirstSupportedTerminalWithoutAnyUse() {
        let choice = AppChoice.terminal(setting: nil, ranked: [], supported: [iTerm2], isInstalled: installed(iTerm2))
        #expect(choice == AppChoice.Terminal(app: iTerm2))
    }

    @Test func skipsATerminalThatIsNoLongerInstalled() {
        let choice = AppChoice.terminal(
            setting: nil, ranked: [terminal, iTerm2], supported: [terminal, iTerm2], isInstalled: installed(iTerm2))
        #expect(choice == AppChoice.Terminal(app: iTerm2))
    }

    @Test func hasNoTerminalWhenNoSupportedOneIsInstalled() {
        let choice = AppChoice.terminal(setting: nil, ranked: [ghostty], supported: [iTerm2], isInstalled: installed())
        #expect(choice == AppChoice.Terminal(app: nil, unsupported: ghostty))
    }

    @Test func keepsToTheSetTerminal() {
        let supported = AppChoice.terminal(
            setting: terminal, ranked: [iTerm2], supported: [iTerm2, terminal], isInstalled: installed(iTerm2, terminal)
        )
        #expect(supported == AppChoice.Terminal(app: terminal))
        let unsupported = AppChoice.terminal(
            setting: ghostty, ranked: [iTerm2], supported: [iTerm2], isInstalled: installed(iTerm2, ghostty))
        #expect(unsupported == AppChoice.Terminal(app: nil, unsupported: ghostty))
    }

    // MARK: Editor

    @Test func opensTheEditorTheUserRunsSessionsIn() {
        let editor = AppChoice.editor(
            ranked: [cursor], defaults: [vsCode, vsCode], isInstalled: installed(cursor, vsCode))
        #expect(editor == cursor)
    }

    @Test func skipsAnEditorThatIsNoLongerInstalled() {
        let editor = AppChoice.editor(ranked: [cursor, zed], defaults: [], isInstalled: installed(zed))
        #expect(editor == zed)
    }

    @Test func otherwiseTakesTheAppMacOSOpensMostCodeFilesWith() {
        let editor = AppChoice.editor(
            ranked: [], defaults: ["com.apple.dt.Xcode", zed, vsCode, vsCode, iTerm2, "com.apple.TextEdit"],
            isInstalled: installed(vsCode, zed))
        #expect(editor == vsCode)
    }

    @Test func breaksATieByTheEarlierKindOfFile() {
        let editor = AppChoice.editor(ranked: [], defaults: [zed, vsCode], isInstalled: installed(vsCode, zed))
        #expect(editor == zed)
    }

    @Test func endsWithVisualStudioCodeWhenInstalled() {
        let defaults = ["com.apple.TextEdit", "com.apple.dt.Xcode", iTerm2]
        #expect(AppChoice.editor(ranked: [], defaults: defaults, isInstalled: installed(vsCode)) == vsCode)
        #expect(AppChoice.editor(ranked: [], defaults: defaults, isInstalled: installed()) == nil)
    }
}
