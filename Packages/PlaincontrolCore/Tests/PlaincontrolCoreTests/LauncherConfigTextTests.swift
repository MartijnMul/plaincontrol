import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct LauncherConfigRenderTests {
    /// A configuration that sets every setting away from its default.
    static let everything = LauncherConfig(
        holdKey: .rightShift, terminal: "com.googlecode.iterm2", editor: "Visual Studio Code",
        claudeCommand: "claude --continue", actionOrder: .usage, zoxide: false,
        roots: ["~/Developer", "/work/clients"], activeDays: 30,
        projects: [
            Project(path: "~/Developer/my-app", name: "My App"), Project(path: "/work/site"),
            Project(path: "/work/api", name: "true"),
        ],
        devCommands: [Project(path: "/work/api").resolvedPath: "uv run fastapi dev --port 8000"],
        windows: WindowLayout(
            builtInColumns: 1, externalColumns: 4, gap: 12.5, editorBuiltInColumns: 1, editorExternalColumns: 3))

    @Test func templateIsTheDefaults() throws {
        #expect(try LauncherConfigFile.parse(LauncherConfigFile.template) == LauncherConfig())
        #expect(LauncherConfigFile.template.contains("\n# terminal: iTerm2\n"))
        #expect(LauncherConfigFile.template.contains("\nroots:\n#  - ~/Developer\nactiveDays: 90\n"))
        #expect(
            LauncherConfigFile.template.contains("\n# windows:\n#   builtIn: 2    # columns on the built-in screen\n"))
    }

    @Test func readsBackWhatItWrites() throws {
        let config = Self.everything
        #expect(try LauncherConfigFile.parse(LauncherConfigFile.render(config)) == config)
    }

    @Test(arguments: LauncherConfigFile.Setting.allCases)
    func readsBackEachSettingOnItsOwn(_ setting: LauncherConfigFile.Setting) throws {
        let config = Self.only(setting)
        #expect(!setting.isSame(in: config, and: LauncherConfig()))
        #expect(try LauncherConfigFile.parse(LauncherConfigFile.render(config)) == config)
    }

    @Test func writesPathsInTheHomeFolderWithATilde() {
        let text = LauncherConfigFile.render(Self.everything)
        #expect(text.contains("\n  - ~/Developer\n  - /work/clients\n"))
        #expect(text.contains("\n  - name: My App\n    path: ~/Developer/my-app\n  - path: /work/site\n"))
        #expect(!text.contains("# terminal:"))
    }

    @Test func quotesWhatYAMLWouldReadOtherwise() throws {
        for value in [
            "true", "No", "~", "42", "1.5", "a: b", "a # b", "- a", "[a]", "\"quoted\"", "back\\slash",
            "tab\tand\nline",
        ] {
            let config = LauncherConfig(claudeCommand: value)
            #expect(try LauncherConfigFile.parse(LauncherConfigFile.render(config)).claudeCommand == value)
        }
        #expect(LauncherConfigFile.Setting.scalar("claude --continue") == "claude --continue")
        #expect(LauncherConfigFile.Setting.scalar("true") == "\"true\"")
    }

    /// The defaults, with `setting` taken from ``everything``.
    static func only(_ setting: LauncherConfigFile.Setting) -> LauncherConfig {
        var config = LauncherConfig()
        let source = everything
        switch setting {
        case .holdKey: config.holdKey = source.holdKey
        case .terminal: config.terminal = source.terminal
        case .editor: config.editor = source.editor
        case .claudeCommand: config.claudeCommand = source.claudeCommand
        case .actionOrder: config.actionOrder = source.actionOrder
        case .zoxide: config.zoxide = source.zoxide
        case .roots: config.roots = source.roots
        case .activeDays: config.activeDays = source.activeDays
        case .projects:
            config.projects = source.projects
            config.devCommands = source.devCommands
        case .windows: config.windows = source.windows
        }
        return config
    }
}
