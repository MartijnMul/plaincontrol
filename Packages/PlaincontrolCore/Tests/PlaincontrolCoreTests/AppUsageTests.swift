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

    @Test func keepsALimitedNumberOfUses() {
        var usage = AppUsage()
        for _ in 0...AppUsage.limit { usage.record(iTerm2, at: now) }
        #expect(usage.uses.count == AppUsage.limit)
    }

    @Test func survivesEncoding() throws {
        var usage = AppUsage()
        usage.record(cursor, at: now)
        #expect(try JSONDecoder().decode(AppUsage.self, from: JSONEncoder().encode(usage)) == usage)
    }
}
