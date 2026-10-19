import Foundation
import PlaincontrolHooks
import Testing

@testable import PlaincontrolCore

@Suite struct AppRoleTests {
    @Test func knowsTerminalsAndEditorsByBundleIdentifier() {
        #expect(AppRole(of: TerminalLocation(program: "iTerm.app", app: "com.googlecode.iterm2")) == .terminal)
        #expect(AppRole(of: TerminalLocation(program: "ghostty", app: "com.mitchellh.ghostty")) == .terminal)
        #expect(AppRole(of: TerminalLocation(program: nil, app: "dev.zed.Zed")) == .editor)
        #expect(AppRole(of: TerminalLocation(program: nil, app: "com.jetbrains.goland")) == .editor)
        #expect(AppRole(of: TerminalLocation(program: nil, app: "com.apple.dt.Xcode")) == .editor)
    }

    @Test func takesAnAppWithTheTerminalOfVisualStudioCodeForAnEditor() {
        #expect(AppRole(of: TerminalLocation(program: "vscode", app: "com.example.CodeFork")) == .editor)
    }

    @Test func leavesOtherAppsOut() {
        #expect(AppRole(of: TerminalLocation(program: nil, app: "com.example.Notes")) == nil)
        #expect(AppRole(of: TerminalLocation(program: "iTerm.app")) == nil)
    }
}

@Suite struct AppUsageTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let day: TimeInterval = 24 * 3600
    let iTerm2 = TerminalLocation(program: "iTerm.app", app: "com.googlecode.iterm2")
    let ghostty = TerminalLocation(program: "ghostty", app: "com.mitchellh.ghostty")
    let cursor = TerminalLocation(program: "vscode", app: "com.todesktop.230313mzl4w4u92")
    let vsCode = "com.microsoft.VSCode"
    let xcode = "com.apple.dt.Xcode"

    @Test func ranksAppsPerRoleByUse() {
        var usage = AppUsage()
        usage.record(ghostty, at: now)
        usage.record(iTerm2, at: now)
        usage.record(iTerm2, at: now)
        usage.record(cursor, at: now)
        #expect(usage.ranked(.terminal, at: now) == ["com.googlecode.iterm2", "com.mitchellh.ghostty"])
        #expect(usage.ranked(.editor, at: now) == ["com.todesktop.230313mzl4w4u92"])
    }

    @Test func weighsRecentUsesMore() {
        var usage = AppUsage()
        for days in 30...33 { usage.record(iTerm2, at: now - Double(days) * day) }
        usage.record(ghostty, at: now - day)
        #expect(usage.ranked(.terminal, at: now).first == "com.mitchellh.ghostty")
    }

    @Test func ignoresSessionsInUnknownApps() {
        var usage = AppUsage()
        usage.record(TerminalLocation(program: nil, app: "com.example.Notes"), at: now)
        usage.record(nil, at: now)
        #expect(usage.uses.isEmpty)
    }

    /// Which of `activations`, in order, counted as a use.
    func counted(_ usage: inout AppUsage, _ activations: [(String, Date)]) -> [Bool] {
        activations.map { usage.recordActivation(of: $0.0, at: $0.1) }
    }

    @Test func countsBringingAnEditorToTheFront() {
        var usage = AppUsage()
        let results = counted(&usage, [(xcode, now), ("com.googlecode.iterm2", now), ("com.example.Notes", now)])
        #expect(results == [true, false, false])
        #expect(usage.ranked(.editor, at: now) == [xcode])
        #expect(usage.ranked(.terminal, at: now).isEmpty)
    }

    @Test func countsAnEditorASessionRanInOnceUnknown() {
        var usage = AppUsage()
        let fork = TerminalLocation(program: "vscode", app: "com.example.CodeFork")
        #expect(counted(&usage, [("com.example.CodeFork", now)]) == [false])
        usage.record(fork, at: now)
        #expect(counted(&usage, [("com.example.CodeFork", now + 2 * 3600)]) == [true])
    }

    @Test func countsAnEditorBroughtToTheFrontAtMostOnceAnHour() {
        var usage = AppUsage()
        let results = counted(
            &usage, [(vsCode, now), (vsCode, now + 59 * 60), (xcode, now + 59 * 60), (vsCode, now + 61 * 60)])
        #expect(results == [true, false, true, true])
        #expect(usage.uses.count == 3)
    }

    @Test func followsASwitchToAnotherEditorWithinDays() {
        // Months of one editor every few hours, then another as often since `now`.
        func editorAfter(days: Double) -> String? {
            var usage = AppUsage()
            for hour in stride(from: 90 * 24, to: 0, by: -3) {
                usage.recordActivation(of: vsCode, at: now - Double(hour) * 3600)
            }
            for hour in stride(from: 0, to: days * 24, by: 3) {
                usage.recordActivation(of: xcode, at: now + hour * 3600)
            }
            return usage.ranked(.editor, at: now + days * day).first
        }
        #expect(editorAfter(days: 2) == vsCode)
        #expect(editorAfter(days: 4) == xcode)
    }

    @Test func keepsALimitedNumberOfUsesPerRole() {
        var usage = AppUsage()
        usage.record(cursor, at: now)
        for _ in 0...AppUsage.limit { usage.record(iTerm2, at: now) }
        #expect(usage.uses.count(where: { $0.role == .terminal }) == AppUsage.limit)
        #expect(usage.ranked(.editor, at: now) == ["com.todesktop.230313mzl4w4u92"])
    }

    @Test func survivesEncoding() throws {
        var usage = AppUsage()
        usage.record(cursor, at: now)
        #expect(try JSONDecoder().decode(AppUsage.self, from: JSONEncoder().encode(usage)) == usage)
    }
}
