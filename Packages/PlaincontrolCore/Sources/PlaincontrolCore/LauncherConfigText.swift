import Foundation

/// The settings file as text: written whole from a ``LauncherConfig``, in the order and with
/// the explanations of the template, or edited a setting at a time, keeping the rest of the
/// text as the user wrote it.
extension LauncherConfigFile {
    /// What a new settings file starts with: every setting at its default.
    public static let template = render(LauncherConfig())

    /// `config` as a whole settings file: every setting in the template's order with its
    /// explanation, and those left unset as commented-out examples.
    public static func render(_ config: LauncherConfig) -> String {
        var lines = header
        for setting in Setting.allCases {
            if !setting.isAttached { lines.append("") }
            lines += setting.explanation
            lines += setting.lines(for: config) ?? []
            if setting.isEmpty(in: config) { lines += setting.example }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `text` with each setting that reads differently from `config` changed to it, and
    /// everything else, comments included, left as it is; or nil when the text is written in a
    /// way this cannot edit, such as with YAML anchors, or does not read at all.
    ///
    /// A changed setting replaces its lines: a value, or the whole of a list or section. One
    /// left out is commented out, so its example stays for the next time. One not in the text
    /// takes the place of its commented-out example, or else goes in the template's order with
    /// the template's explanation.
    public static func edit(_ text: String, to config: LauncherConfig) -> String? {
        guard let current = try? parse(text), var document = Document(text) else { return nil }
        let changed = Setting.allCases.filter { !$0.isSame(in: current, and: config) }
        guard !changed.isEmpty else { return text }
        for setting in changed {
            document.set(setting, to: setting.lines(for: config))
        }
        document.addSchemaComment()
        let edited = document.text
        guard (try? parse(edited)) == config else { return nil }
        return edited
    }

    /// What ``update(at:_:)`` did to the file.
    public struct Update: Sendable, Equatable {
        /// The settings the file holds now.
        public var config: LauncherConfig
        /// Where the file was copied before it was written whole, when it could not be edited
        /// in place.
        public var backup: String?
    }

    /// Changes the settings in the file at `path` with `change`, editing only the changed
    /// settings in its text (``edit(_:to:)``). Where the text cannot be edited that way, the
    /// file is copied to `path` + `.backup` and written whole (``render(_:)``). A file that
    /// cannot be read is left alone.
    @discardableResult
    public static func update(
        at path: String = defaultPath, _ change: (inout LauncherConfig) -> Void
    ) throws(LauncherConfigError) -> Update {
        let exists = FileManager.default.fileExists(atPath: path)
        let text: String
        do {
            text = exists ? try String(contentsOfFile: path, encoding: .utf8) : template
        } catch {
            throw LauncherConfigError(message: error.localizedDescription)
        }
        var config = try parse(text)
        change(&config)
        // The settings may have changed in what they read as, such as a path given with `~`.
        config = try parse(render(config))
        var update = Update(config: config)
        do {
            if let edited = edit(text, to: config) {
                guard edited != text || !exists else { return update }
                try write(edited, to: path)
            } else {
                if exists {
                    let backup = path + ".backup"
                    try? FileManager.default.removeItem(atPath: backup)
                    try FileManager.default.copyItem(atPath: path, toPath: backup)
                    update.backup = backup
                }
                try write(render(config), to: path)
            }
        } catch {
            throw LauncherConfigError(message: error.localizedDescription)
        }
        return update
    }

    private static func write(_ text: String, to path: String) throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static let header = [
        schemaComment, "# Settings for Plaincontrol. Changes apply the next time the launcher opens.",
    ]

    /// The line that points editors with the YAML language server at ``schema``.
    static let schemaComment = "# yaml-language-server: $schema=\(schemaName)"

    /// A setting in the file, in the template's order.
    enum Setting: String, CaseIterable {
        case holdKey, terminal, editor, claudeCommand, actionOrder, zoxide, roots, activeDays, projects, windows

        var key: String { rawValue }

        /// The comment above the setting.
        var explanation: [String] {
            switch self {
            case .holdKey:
                [
                    "# The key that opens the launcher when you hold it on its own:",
                    "# rightOption, rightCommand, rightControl or rightShift.",
                ]
            case .terminal:
                [
                    "# The terminal for Claude Code, Terminal and the dev server, by app name or bundle",
                    "# identifier. Without one, it is the terminal you run Claude Code in most. Plaincontrol",
                    "# can open iTerm2 windows so far.",
                ]
            case .editor:
                [
                    "# The editor, by app name (such as Cursor or Zed) or bundle identifier. Without",
                    "# one, it is the editor you use most lately, such as Xcode or Zed; before you have used",
                    "# one, the app your Mac opens code files with, or else Visual Studio Code.",
                ]
            case .claudeCommand:
                ["# What Claude Code runs in a new terminal window in the project's folder."]
            case .actionOrder:
                [
                    "# How a project's actions are ordered:",
                    "#   fixed     always the same order, with the first action selected",
                    "#   selected  the same order, with the action you use most in that project selected,",
                    "#             so Return runs it",
                    "#   usage     the actions you use most in that project first; their digits move with them",
                    "# A project you haven't used an action in yet follows your use in all projects.",
                ]
            case .zoxide:
                [
                    "# The launcher lists the folders where you start Claude Code or open projects from the",
                    "# launcher. If you use zoxide (https://github.com/ajeetdsouza/zoxide), it also lists the",
                    "# folders you visit most, and ranks by both. zoxide's data is only read, never changed.",
                ]
            case .roots:
                [
                    "# Folders whose subfolders are projects, such as a folder of git repositories. A project",
                    "# is listed while you work on it: a commit (in a git repository) or a changed file (in",
                    "# any other folder), or a Claude Code session or launcher action in it, within",
                    "# activeDays. Older ones show up when you search for them.",
                ]
            case .activeDays:
                []
            case .projects:
                [
                    "# Projects that are always listed, with an optional name; without one, a project is",
                    "# named after its folder. A dev server command replaces the one the launcher finds:",
                    "# make dev or the package.json dev script, else make run or Docker Compose.",
                ]
            case .windows:
                [
                    "# Where the windows the launcher opens go. Without this, each app decides. With it,",
                    "# every screen is split into columns, as a window manager such as Rectangle does, and a",
                    "# new window takes a free column: on the screen with the pointer first, then on the",
                    "# other external screens, then on the built-in one. Each screen fills from the columns",
                    "# nearest you, taking you to sit in front of the built-in screen: a screen in front of",
                    "# you from its middle, then from left to right; one to your left from right to left.",
                    "# The editor takes several columns side by side. Finder and the editor are moved once",
                    "# their window appears.",
                ]
            }
        }

        /// Whether the setting follows the one before it without a blank line, explained by
        /// that one's comment.
        var isAttached: Bool { self == .activeDays }

        /// The setting's lines for `config`, or nil when the file leaves it out.
        func lines(for config: LauncherConfig) -> [String]? {
            switch self {
            case .holdKey: ["holdKey: \(config.holdKey.rawValue)"]
            case .terminal: config.terminal.map { ["terminal: \(Self.scalar($0))"] }
            case .editor: config.editor.map { ["editor: \(Self.scalar($0))"] }
            case .claudeCommand: ["claudeCommand: \(Self.scalar(config.claudeCommand))"]
            case .actionOrder: ["actionOrder: \(config.actionOrder.rawValue)"]
            case .zoxide: ["zoxide: \(config.zoxide)"]
            case .roots: ["roots:"] + config.roots.map { "  - \(Self.scalar(Self.abbreviate($0)))" }
            case .activeDays: ["activeDays: \(config.activeDays)"]
            case .projects:
                ["projects:"]
                    + config.projects.flatMap { project in
                        var entry: [String] = []
                        if project.name != (project.path as NSString).lastPathComponent {
                            entry.append("name: \(Self.scalar(project.name))")
                        }
                        entry.append("path: \(Self.scalar(Self.abbreviate(project.path)))")
                        if let command = config.devCommand(for: project) {
                            entry.append("devCommand: \(Self.scalar(command))")
                        }
                        return entry.enumerated().map { $0.offset == 0 ? "  - \($0.element)" : "    \($0.element)" }
                    }
            case .windows: config.windows.map(Self.lines(for:))
            }
        }

        /// Whether the setting is a list without items or is left out, which the file shows
        /// with ``example``.
        func isEmpty(in config: LauncherConfig) -> Bool {
            switch self {
            case .terminal: config.terminal == nil
            case .editor: config.editor == nil
            case .roots: config.roots.isEmpty
            case .projects: config.projects.isEmpty
            case .windows: config.windows == nil
            case .holdKey, .claudeCommand, .actionOrder, .zoxide, .activeDays: false
            }
        }

        /// Commented-out lines that show how to set the setting, while it has no value.
        var example: [String] {
            switch self {
            case .terminal: ["# terminal: iTerm2"]
            case .editor: ["# editor: Visual Studio Code"]
            case .roots: ["#  - ~/Developer"]
            case .projects:
                ["#  - name: My App", "#    path: ~/Developer/my-app", "#    devCommand: uv run fastapi dev"]
            case .windows: Self.lines(for: WindowLayout()).map { "# \($0)" }
            case .holdKey, .claudeCommand, .actionOrder, .zoxide, .activeDays: []
            }
        }

        /// Whether `a` and `b` agree on this setting.
        func isSame(in a: LauncherConfig, and b: LauncherConfig) -> Bool {
            switch self {
            case .holdKey: a.holdKey == b.holdKey
            case .terminal: a.terminal == b.terminal
            case .editor: a.editor == b.editor
            case .claudeCommand: a.claudeCommand == b.claudeCommand
            case .actionOrder: a.actionOrder == b.actionOrder
            case .zoxide: a.zoxide == b.zoxide
            case .roots: a.roots == b.roots
            case .activeDays: a.activeDays == b.activeDays
            case .projects:
                a.projects == b.projects && a.projects.map(a.devCommand(for:)) == b.projects.map(b.devCommand(for:))
            case .windows: a.windows == b.windows
            }
        }

        private static func lines(for layout: WindowLayout) -> [String] {
            let gap = layout.gap == layout.gap.rounded() ? String(Int(layout.gap)) : String(layout.gap)
            return [
                ("windows:", nil),
                ("  builtIn: \(layout.builtInColumns)", WindowNotes.builtIn),
                ("  external: \(layout.externalColumns)", WindowNotes.external),
                ("  gap: \(gap)", WindowNotes.gap),
                ("  editor:", WindowNotes.editor),
                ("    builtIn: \(layout.editorBuiltInColumns)", nil),
                ("    external: \(layout.editorExternalColumns)", nil),
            ].map { line, comment in
                guard let comment else { return line }
                return line.padding(toLength: max(16, line.count + 1), withPad: " ", startingAt: 0) + "# \(comment)"
            }
        }

        /// What each part of `windows` is, after it in the file and in the schema.
        enum WindowNotes {
            static let builtIn = "columns on the built-in screen"
            static let external = "columns on every other screen"
            static let gap = "points around and between windows"
            static let editor = "columns the editor takes"
        }

        /// `path` with the home folder as `~`, as the user would write it.
        private static func abbreviate(_ path: String) -> String {
            let home = NSHomeDirectory()
            if path == home { return "~" }
            return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }

        /// `value` as a YAML string: as it is where YAML reads it back as the same string,
        /// and otherwise in double quotes.
        static func scalar(_ value: String) -> String {
            let plain = /[A-Za-z_.\/~(][A-Za-z0-9_.\/~()=+,@ -]*/
            let special: Set = ["~", "null", "true", "false", "yes", "no", "on", "off", "y", "n"]
            if value.wholeMatch(of: plain) != nil, !value.hasSuffix(" "), !special.contains(value.lowercased()),
                Double(value) == nil
            {
                return value
            }
            var quoted = "\""
            for character in value.unicodeScalars {
                switch character {
                case "\"": quoted += "\\\""
                case "\\": quoted += "\\\\"
                case "\n": quoted += "\\n"
                case "\t": quoted += "\\t"
                case _ where character.value < 0x20: quoted += String(format: "\\x%02X", character.value)
                default: quoted.unicodeScalars.append(character)
                }
            }
            return quoted + "\""
        }
    }
}

/// The settings file as lines, with where each setting is.
private struct Document {
    var lines: [String]

    /// A setting's place: its first and last line.
    private struct Block {
        var start: Int
        var end: Int
    }

    /// Splits `text` into lines, or nil when it holds YAML this cannot edit line by line:
    /// anything at the top level other than settings, comments and a document start, or
    /// anchors, aliases, tags and merge keys, which tie settings to each other.
    init?(_ text: String) {
        lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var seenKey = false
        for line in lines {
            if line.wholeMatch(of: /\s*(#.*)?/) != nil || line.first == " " { continue }
            if line.hasPrefix("- ") || line == "-" { continue }
            if Self.key(of: line) != nil {
                seenKey = true
                continue
            }
            if !seenKey, line.hasPrefix("---") { continue }
            return nil
        }
        let tie = /(:\s+|-\s+|[\[{,]\s*)[&*!][^\s]|<<\s*:/
        guard !lines.contains(where: { Self.content(of: $0).contains(tie) }) else { return nil }
    }

    var text: String { lines.joined(separator: "\n") + "\n" }

    /// Puts ``LauncherConfigFile/schemaComment`` at the top, unless the text points at a
    /// schema already.
    mutating func addSchemaComment() {
        guard !lines.contains(where: { $0.hasPrefix("# yaml-language-server:") }) else { return }
        lines.insert(LauncherConfigFile.schemaComment, at: 0)
    }

    /// Replaces `setting`'s lines with `new`, or comments them out when `new` is nil.
    mutating func set(_ setting: LauncherConfigFile.Setting, to new: [String]?) {
        if let block = block(of: setting) {
            guard var new else {
                for index in block.start...block.end { lines[index] = "# " + lines[index] }
                return
            }
            // A comment after the value on the setting's own line stays.
            if let comment = Self.comment(of: lines[block.start]), !new.isEmpty, Self.comment(of: new[0]) == nil {
                new[0] += comment
            }
            lines.replaceSubrange(block.start...block.end, with: new)
        } else if let new {
            if let example = example(of: setting) {
                lines.replaceSubrange(example.start...example.end, with: new)
            } else {
                insert(setting, new)
            }
        }
    }

    /// Adds `setting`, which the text does not have, in the template's order: after the
    /// setting before it in the template, with the commented-out lines right below that one,
    /// or else before the explanation of the setting after it.
    private mutating func insert(_ setting: LauncherConfigFile.Setting, _ new: [String]) {
        let all = LauncherConfigFile.Setting.allCases
        let position = all.firstIndex(of: setting)!
        let place = { [self] (setting: LauncherConfigFile.Setting) in block(of: setting) ?? example(of: setting) }
        // The explanation, unless the text has it already, such as above a setting removed by hand.
        let explanation =
            setting.explanation.first.map { first in lines.contains(first) } == true ? [] : setting.explanation
        if let previous = all[..<position].reversed().lazy.compactMap(place).first {
            var index = previous.end + 1
            while index < lines.count, lines[index].contains(/^#\s{2,}\S/) { index += 1 }
            if setting.isAttached {
                lines.insert(contentsOf: new, at: index)
            } else {
                let space = index < lines.count && !Self.isBlank(lines[index]) ? [""] : []
                lines.insert(contentsOf: [""] + explanation + new + space, at: index)
            }
        } else if let following = all[(position + 1)...].lazy.compactMap(place).first {
            var index = following.start
            while index > 0, lines[index - 1].hasPrefix("#") { index -= 1 }
            let space = index > 0 && !Self.isBlank(lines[index - 1]) ? [""] : []
            lines.insert(contentsOf: space + explanation + new + [""], at: index)
        } else {
            if let last = lines.last, !Self.isBlank(last) { lines.append("") }
            lines += explanation + new
        }
    }

    /// Where `setting` is set: its key's line, and the lines below that belong to it, up to
    /// the last before the next setting. Comments and blank lines after it are not its own.
    private func block(of setting: LauncherConfigFile.Setting) -> Block? {
        guard let start = lines.firstIndex(where: { Self.key(of: $0) == setting.key }) else { return nil }
        var end = start
        var index = start + 1
        while index < lines.count, Self.key(of: lines[index]) == nil, !lines[index].hasPrefix("---") {
            if Self.content(of: lines[index]).contains(/\S/) { end = index }
            index += 1
        }
        return Block(start: start, end: end)
    }

    /// Where `setting` is shown commented out, such as `# terminal: iTerm2`: that line and
    /// the commented-out, indented lines right below it.
    private func example(of setting: LauncherConfigFile.Setting) -> Block? {
        guard let start = lines.firstIndex(where: { $0.hasPrefix("# \(setting.key):") }) else { return nil }
        var end = start
        while end + 1 < lines.count, lines[end + 1].contains(/^#\s{2,}\S/) { end += 1 }
        return Block(start: start, end: end)
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// The setting a line starts, if it starts one.
    private static func key(of line: String) -> String? {
        line.prefixMatch(of: /([A-Za-z_][A-Za-z0-9_]*)\s*:(\s|$)/).map { String($0.1) }
    }

    /// `line` without its comment.
    private static func content(of line: String) -> Substring {
        guard let comment = comment(of: line) else { return line[...] }
        return line.dropLast(comment.count)
    }

    /// The comment at the end of `line`, with the spaces before it, if it has one.
    private static func comment(of line: String) -> String? {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return line }
        // A quoted value can hold a #; past it, a comment starts with a # after a space.
        var quote: Character?
        var previous: Character = " "
        for (offset, character) in line.enumerated() {
            if let open = quote {
                if character == open, previous != "\\" { quote = nil }
            } else if character == "\"" || character == "'", previous == " " {
                quote = character
            } else if character == "#", previous == " " || previous == "\t" {
                let start = line.index(line.startIndex, offsetBy: offset)
                let spaces = line[..<start].reversed().prefix { $0 == " " || $0 == "\t" }.count
                return String(line[line.index(start, offsetBy: -spaces)...])
            }
            previous = character
        }
        return nil
    }
}
