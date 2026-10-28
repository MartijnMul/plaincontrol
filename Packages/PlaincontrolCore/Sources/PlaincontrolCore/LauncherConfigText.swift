import Foundation

/// The settings file as text: written whole from a ``LauncherConfig``, in the order and with
/// the explanations of the template.
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

    static let header = ["# Settings for Plaincontrol. Changes apply the next time the launcher opens."]

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
                ("  builtIn: \(layout.builtInColumns)", "columns on the built-in screen"),
                ("  external: \(layout.externalColumns)", "columns on every other screen"),
                ("  gap: \(gap)", "points around and between windows"),
                ("  editor:", "columns the editor takes"),
                ("    builtIn: \(layout.editorBuiltInColumns)", nil),
                ("    external: \(layout.editorExternalColumns)", nil),
            ].map { line, comment in
                guard let comment else { return line }
                return line.padding(toLength: max(16, line.count + 1), withPad: " ", startingAt: 0) + "# \(comment)"
            }
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
