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

@Suite struct LauncherConfigEditTests {
    typealias Setting = LauncherConfigFile.Setting

    /// The line an edit puts at the top of a file without it.
    let schema = LauncherConfigFile.schemaComment + "\n"

    @Test(arguments: Setting.allCases)
    func changesOnlyTheSettingsLinesInTheTemplate(_ setting: Setting) throws {
        let config = LauncherConfigRenderTests.only(setting)
        let edited = try #require(LauncherConfigFile.edit(LauncherConfigFile.template, to: config))
        #expect(try LauncherConfigFile.parse(edited) == config)
        // Its lines in place of the template's own, or of its commented-out example.
        let new = try #require(setting.lines(for: config)).joined(separator: "\n")
        let old = (setting.lines(for: LauncherConfig()) ?? setting.example).joined(separator: "\n")
        #expect(edited.replacing(new, with: old) == LauncherConfigFile.template)
    }

    @Test func keepsCommentsAboveBetweenAndAfter() throws {
        let text = """
            # My settings
            holdKey: rightCommand   # the one I can reach

            roots:
              # work first
              - ~/Work
              - ~/Code    # side projects
            # end of roots
            zoxide: false
            # the end

            """
        var config = try LauncherConfigFile.parse(text)
        config.holdKey = .rightShift
        config.roots = [NSHomeDirectory() + "/Work"]
        #expect(
            LauncherConfigFile.edit(text, to: config) == """
                \(LauncherConfigFile.schemaComment)
                # My settings
                holdKey: rightShift   # the one I can reach

                roots:
                  - ~/Work
                # end of roots
                zoxide: false
                # the end

                """)
    }

    @Test func addsAMissingSettingInTheTemplatesOrder() throws {
        let text = "holdKey: rightCommand\n\nzoxide: false\n"
        var config = try LauncherConfigFile.parse(text)
        config.terminal = "Ghostty"
        config.activeDays = 30
        let edited = try #require(LauncherConfigFile.edit(text, to: config))
        let terminal = Setting.terminal.explanation.joined(separator: "\n")
        #expect(
            edited
                == "\(schema)holdKey: rightCommand\n\n\(terminal)\nterminal: Ghostty\n\nzoxide: false\nactiveDays: 30\n"
        )
    }

    @Test func addsASettingAtTheTopWhenNoneComesBefore() throws {
        let text = "# Mine\n\nzoxide: false\n"
        var config = try LauncherConfigFile.parse(text)
        config.holdKey = .rightControl
        let explanation = Setting.holdKey.explanation.joined(separator: "\n")
        #expect(
            LauncherConfigFile.edit(text, to: config)
                == "\(schema)# Mine\n\n\(explanation)\nholdKey: rightControl\n\nzoxide: false\n")
    }

    @Test func commentsOutASettingLeftOutAndTakesItsPlaceAgain() throws {
        let text = "terminal: Ghostty  # for now\nwindows:\n  external: 4\nzoxide: false\n"
        var config = try LauncherConfigFile.parse(text)
        config.terminal = nil
        config.windows = nil
        let removed = try #require(LauncherConfigFile.edit(text, to: config))
        #expect(removed == "\(schema)# terminal: Ghostty  # for now\n# windows:\n#   external: 4\nzoxide: false\n")

        config.terminal = "iTerm2"
        config.windows = WindowLayout()
        let restored = try #require(LauncherConfigFile.edit(removed, to: config))
        let windows = try #require(Setting.windows.lines(for: config)).joined(separator: "\n")
        #expect(restored == "\(schema)terminal: iTerm2\n\(windows)\nzoxide: false\n")
    }

    @Test func leavesATextThatAlreadyReadsSoAlone() throws {
        let text = "roots: [~/Work, ~/Code]  # inline\nzoxide: false\n"
        #expect(LauncherConfigFile.edit(text, to: try LauncherConfigFile.parse(text)) == text)
    }

    @Test func replacesAnInlineListWhole() throws {
        let text = "roots: [~/Work, ~/Code]  # inline\nzoxide: false\n"
        var config = try LauncherConfigFile.parse(text)
        config.roots.removeLast()
        #expect(LauncherConfigFile.edit(text, to: config) == "\(schema)roots:  # inline\n  - ~/Work\nzoxide: false\n")
    }

    @Test func cannotEditAnchorsOrWhatDoesNotRead() throws {
        let anchored = "roots: &folders\n  - /work\nprojects:\n  - path: /work/app\nextra: *folders\n"
        var config = try LauncherConfigFile.parse(anchored)
        config.zoxide = false
        #expect(LauncherConfigFile.edit(anchored, to: config) == nil)
        #expect(LauncherConfigFile.edit("holdKey: capsLock\n", to: LauncherConfig()) == nil)
        #expect(LauncherConfigFile.edit("{zoxide: true}\n", to: LauncherConfig(zoxide: false)) == nil)
    }

    @Test func updatesTheFileInPlace() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "settings.yaml").path(percentEncoded: false)

        // Without a file, from the template.
        let created = try LauncherConfigFile.update(at: path) { $0.zoxide = false }
        #expect(created == .init(config: LauncherConfig(zoxide: false)))
        #expect(
            try String(contentsOfFile: path, encoding: .utf8)
                == LauncherConfigFile.template.replacing("zoxide: true", with: "zoxide: false"))

        try "# mine\nzoxide: false\n".write(toFile: path, atomically: true, encoding: .utf8)
        let update = try LauncherConfigFile.update(at: path) { $0.roots = ["~/Work"] }
        #expect(update.config.roots == [NSHomeDirectory() + "/Work"])
        #expect(update.backup == nil)
        #expect(try String(contentsOfFile: path, encoding: .utf8).hasPrefix("\(schema)# mine\nzoxide: false\n"))
        #expect(!FileManager.default.fileExists(atPath: path + ".backup"))
    }

    @Test func writesTheFileWholeWithABackupWhenItCannotEditIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "settings.yaml").path(percentEncoded: false)
        let anchored = "roots: &folders\n  - /work\nextra: *folders\n"
        try anchored.write(toFile: path, atomically: true, encoding: .utf8)

        let update = try LauncherConfigFile.update(at: path) { $0.zoxide = false }
        #expect(update.backup == path + ".backup")
        #expect(try String(contentsOfFile: path + ".backup", encoding: .utf8) == anchored)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == LauncherConfigFile.render(update.config))
        #expect(update.config == LauncherConfig(zoxide: false, roots: ["/work"]))
    }

    @Test func leavesAFileThatDoesNotReadAlone() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "settings.yaml").path(percentEncoded: false)
        try "actionOrder: random\n".write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.update(at: path) { $0.zoxide = false } }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "actionOrder: random\n")
        #expect(!FileManager.default.fileExists(atPath: path + ".backup"))
    }
}

@Suite struct LauncherConfigSchemaTests {
    typealias Setting = LauncherConfigFile.Setting

    let schema: [String: Any]

    init() throws {
        let data = Data(LauncherConfigFile.schema.utf8)
        schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func properties(_ path: String...) throws -> [String: [String: Any]] {
        var object = schema
        for key in path {
            let properties = try #require(object["properties"] as? [String: Any])
            object = try #require(properties[key] as? [String: Any])
            if let items = object["items"] as? [String: Any] { object = items }
        }
        return try #require(object["properties"] as? [String: [String: Any]])
    }

    static func keys(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    @Test func namesEverySettingTheReaderKnows() throws {
        #expect(Set(try properties().keys) == Self.keys(of: LauncherConfigFile.File()))
        #expect(Set(Setting.allCases.map(\.key)) == Self.keys(of: LauncherConfigFile.File()))
        #expect(Set(try properties("projects").keys) == Self.keys(of: LauncherConfigFile.Entry(path: "")))
        #expect(Set(try properties("windows").keys) == Self.keys(of: LauncherConfigFile.Windows()))
        #expect(Set(try properties("windows", "editor").keys) == Self.keys(of: LauncherConfigFile.Columns()))
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test func allowsTheValuesTheReaderAllows() throws {
        let settings = try properties()
        #expect(settings["holdKey"]?["enum"] as? [String] == HoldKey.allCases.map(\.rawValue))
        #expect(settings["actionOrder"]?["enum"] as? [String] == ActionOrder.allCases.map(\.rawValue))
        for value in try #require(settings["holdKey"]?["enum"] as? [String]) {
            #expect(throws: Never.self) { try LauncherConfigFile.parse("holdKey: \(value)\n") }
        }
        for value in try #require(settings["actionOrder"]?["enum"] as? [String]) {
            #expect(throws: Never.self) { try LauncherConfigFile.parse("actionOrder: \(value)\n") }
        }
    }

    @Test func hasTheReadersRanges() throws {
        let days = try #require(try properties()["activeDays"]?["minimum"] as? Int)
        #expect(throws: Never.self) { try LauncherConfigFile.parse("activeDays: \(days)\n") }
        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse("activeDays: \(days - 1)\n") }

        let windows = try properties("windows")
        let editor = try properties("windows", "editor")
        let numbers = [
            ("builtIn", windows["builtIn"]), ("external", windows["external"]), ("gap", windows["gap"]),
            ("editor:\n    builtIn", editor["builtIn"]), ("editor:\n    external", editor["external"]),
        ]
        for (key, property) in numbers {
            let minimum = try #require(property?["minimum"] as? Double)
            let maximum = try #require(property?["maximum"] as? Double)
            let text = { (value: Double) in "windows:\n  \(key): \(value.formatted(.number.grouping(.never)))\n" }
            #expect(throws: Never.self) { try LauncherConfigFile.parse(text(minimum)) }
            #expect(throws: Never.self) { try LauncherConfigFile.parse(text(maximum)) }
            #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse(text(minimum - 1)) }
            #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse(text(maximum + 1)) }
        }
    }

    @Test func explainsEverySetting() throws {
        for (key, property) in try properties() {
            let description = try #require(property["description"] as? String, "\(key)")
            #expect(!description.isEmpty && !description.contains("#") && !description.contains("  "))
        }
    }

    @Test func isPointedAtFromTheTemplate() {
        #expect(LauncherConfigFile.template.hasPrefix("# yaml-language-server: $schema=settings.schema.json\n"))
    }

    @Test func isWrittenNextToTheSettings() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "settings.yaml").path(percentEncoded: false)
        let schemaPath = folder.appending(path: "settings.schema.json").path(percentEncoded: false)
        #expect(LauncherConfigFile.schemaPath(nextTo: path) == schemaPath)

        try LauncherConfigFile.writeSchema(nextTo: path)
        #expect(try String(contentsOfFile: schemaPath, encoding: .utf8) == LauncherConfigFile.schema)
        try "{}".write(toFile: schemaPath, atomically: true, encoding: .utf8)
        try LauncherConfigFile.writeSchema(nextTo: path)
        #expect(try String(contentsOfFile: schemaPath, encoding: .utf8) == LauncherConfigFile.schema)
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
