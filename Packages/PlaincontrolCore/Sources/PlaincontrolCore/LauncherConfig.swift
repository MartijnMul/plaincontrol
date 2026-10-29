import Foundation
import Yams

/// A modifier key that opens the launcher when held on its own.
public enum HoldKey: String, CaseIterable, Sendable {
    case rightOption, rightCommand, rightControl, rightShift

    /// The virtual key code of the key.
    public var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .rightControl: 62
        case .rightShift: 60
        }
    }

    /// The key's bit in the device-dependent part of a key event's modifier flags, which tells
    /// the right key from the left one.
    public var deviceFlag: UInt {
        switch self {
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightControl: 0x2000
        case .rightShift: 0x04
        }
    }

    /// The device-dependent bits of every modifier key, left and right.
    public static let allDeviceFlags: UInt = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x2000
}

/// What the user configures about the launcher, in `settings.yaml`:
///
/// ```yaml
/// holdKey: rightOption  # rightOption, rightCommand, rightControl or rightShift
/// terminal: iTerm2      # the app for Claude Code, Terminal and the dev server, by name or bundle id
/// editor: Cursor        # the app for Editor, by name or bundle identifier
/// browser: Firefox      # the app for a dev server's page and an empty browser window
/// claudeCommand: claude # what Claude Code runs in the new terminal window
/// actionOrder: fixed    # fixed, selected (the most used selected) or usage (most used first)
/// zoxide: true          # also list and rank by zoxide's folders, when it is installed
/// roots:                # folders whose subfolders are projects
///   - ~/Developer
/// activeDays: 90        # a project is listed this long after its last change or use
/// projects:             # always listed, with an optional name and dev server command
///   - name: My App
///     path: ~/Developer/my-app
///     devCommand: uv run fastapi dev
/// windows:              # new windows in free columns, nearest the user first; false: each app places them
///   builtIn: 2          # columns on the built-in screen
///   external: 3         # columns on every other screen
///   gap: 10             # points around and between windows
///   editor:             # columns the editor takes, side by side
///     builtIn: 2
///     external: 2
/// ```
public struct LauncherConfig: Sendable, Equatable {
    /// The key that opens the launcher when held on its own.
    public var holdKey = HoldKey.rightOption
    /// The terminal for the Claude Code, terminal and dev server actions, by app name or bundle
    /// identifier, or nil to pick one (``AppChoice``).
    public var terminal: String?
    /// The editor for the editor action, by app name or bundle identifier, or nil to pick one
    /// (``AppChoice``).
    public var editor: String?
    /// The browser for a dev server's page and an empty browser window, by app name or bundle
    /// identifier, or nil for the one macOS opens web pages with.
    public var browser: String?
    /// The command the Claude Code action runs in the project's folder.
    public var claudeCommand = "claude"
    /// How a project's actions are ordered.
    public var actionOrder = ActionOrder.fixed
    /// Whether to also list and rank by the folders the user visits with zoxide, when installed.
    public var zoxide = true
    /// Folders whose subfolders are projects, by their absolute paths.
    public var roots: [String] = []
    /// How long a project stays in the list after its last change or use.
    public var activeDays = 90
    /// Projects that are always listed, in the order of the file.
    public var projects: [Project] = []
    /// The commands that start the development servers of projects, by their resolved paths,
    /// where the user sets one instead of leaving it to ``DevServer``.
    public var devCommands: [String: String] = [:]
    /// How to arrange the windows the launcher opens, or nil to leave it to each app. Without
    /// the setting, they go in columns of the default layout.
    public var windows: WindowLayout? = WindowLayout()

    public init(
        holdKey: HoldKey = .rightOption, terminal: String? = nil, editor: String? = nil, browser: String? = nil,
        claudeCommand: String = "claude", actionOrder: ActionOrder = .fixed, zoxide: Bool = true, roots: [String] = [],
        activeDays: Int = 90,
        projects: [Project] = [], devCommands: [String: String] = [:], windows: WindowLayout? = WindowLayout()
    ) {
        self.holdKey = holdKey
        self.terminal = terminal
        self.editor = editor
        self.browser = browser
        self.claudeCommand = claudeCommand
        self.actionOrder = actionOrder
        self.zoxide = zoxide
        self.roots = roots.map { ($0 as NSString).standardizingPath }
        self.activeDays = activeDays
        self.projects = projects
        self.devCommands = devCommands
        self.windows = windows
    }

    /// The command set for `project`'s development server, if any.
    public func devCommand(for project: Project) -> String? {
        devCommands[project.resolvedPath]
    }
}

/// The settings file, which the user edits by hand or through the settings window.
public enum LauncherConfigFile {
    /// `~/.config/plaincontrol/settings.yaml`, shared by the release and development builds.
    public static var defaultPath: String {
        URL.homeDirectory.appending(path: ".config/plaincontrol/settings.yaml").path(percentEncoded: false)
    }

    /// The configuration in `text`; a project listed twice counts once.
    public static func parse(_ text: String) throws(LauncherConfigError) -> LauncherConfig {
        let file: File
        do {
            guard let node = try Yams.compose(yaml: text) else { return LauncherConfig() }
            file = try YAMLDecoder().decode(File.self, from: node)
        } catch {
            throw LauncherConfigError(message: String(describing: error))
        }
        if let days = file.activeDays, days < minimumActiveDays {
            throw LauncherConfigError(message: "activeDays must be at least \(minimumActiveDays).")
        }
        var holdKey = HoldKey.rightOption
        if let name = file.holdKey {
            guard let key = HoldKey(rawValue: name) else {
                let names = HoldKey.allCases.map(\.rawValue).joined(separator: ", ")
                throw LauncherConfigError(message: "holdKey must be one of \(names).")
            }
            holdKey = key
        }
        var actionOrder = ActionOrder.fixed
        if let name = file.actionOrder {
            guard let order = ActionOrder(rawValue: name) else {
                let names = ActionOrder.allCases.map(\.rawValue).joined(separator: ", ")
                throw LauncherConfigError(message: "actionOrder must be one of \(names).")
            }
            actionOrder = order
        }
        let claudeCommand = file.claudeCommand?.trimmingCharacters(in: .whitespaces) ?? "claude"
        if claudeCommand.isEmpty {
            throw LauncherConfigError(message: "claudeCommand cannot be empty.")
        }
        let terminal = file.terminal?.trimmingCharacters(in: .whitespaces)
        let editor = file.editor?.trimmingCharacters(in: .whitespaces)
        let browser = file.browser?.trimmingCharacters(in: .whitespaces)
        var windows: WindowLayout? = WindowLayout()
        if case .on(false) = file.windows {
            windows = nil
        } else if case .layout(let section) = file.windows {
            let layout = WindowLayout(
                builtInColumns: section.builtIn ?? 2, externalColumns: section.external ?? 3, gap: section.gap ?? 10,
                editorBuiltInColumns: section.editor?.builtIn ?? 2, editorExternalColumns: section.editor?.external ?? 2
            )
            let columns = [
                layout.builtInColumns, layout.externalColumns, layout.editorBuiltInColumns,
                layout.editorExternalColumns,
            ]
            guard columns.allSatisfy(columnRange.contains) else {
                throw LauncherConfigError(
                    message:
                        "windows: every number of columns must be from \(columnRange.lowerBound) to \(columnRange.upperBound)."
                )
            }
            guard gapRange.contains(layout.gap) else {
                throw LauncherConfigError(
                    message: "windows: gap must be from \(Int(gapRange.lowerBound)) to \(Int(gapRange.upperBound)).")
            }
            windows = layout
        }
        var seen = Set<String>()
        var devCommands: [String: String] = [:]
        let projects = (file.projects ?? []).compactMap { entry -> Project? in
            let project = Project(path: entry.path, name: entry.name)
            if let command = entry.devCommand?.trimmingCharacters(in: .whitespaces), !command.isEmpty {
                devCommands[project.resolvedPath] = command
            }
            return seen.insert(project.path).inserted ? project : nil
        }
        return LauncherConfig(
            holdKey: holdKey, terminal: terminal?.isEmpty == false ? terminal : nil,
            editor: editor?.isEmpty == false ? editor : nil, browser: browser?.isEmpty == false ? browser : nil,
            claudeCommand: claudeCommand, actionOrder: actionOrder,
            zoxide: file.zoxide ?? true, roots: file.roots ?? [], activeDays: file.activeDays ?? 90,
            projects: projects, devCommands: devCommands, windows: windows)
    }

    /// Reads the configuration at `path`, or the defaults when there is no file yet.
    public static func load(from path: String = defaultPath) throws(LauncherConfigError) -> LauncherConfig {
        guard FileManager.default.fileExists(atPath: path) else { return LauncherConfig() }
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw LauncherConfigError(message: error.localizedDescription)
        }
        return try parse(text)
    }

    /// Creates the file at `path` from ``template``, unless it exists already.
    public static func createIfMissing(at path: String = defaultPath) throws {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try template.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The fewest days `activeDays` can be.
    public static let minimumActiveDays = 1
    /// The numbers of columns a screen and the editor can have.
    public static let columnRange = 1...6
    /// The gaps around and between windows there can be, in points.
    public static let gapRange: ClosedRange<Double> = 0...100

    /// What the file holds, as YAML reads it: every setting there is.
    struct File: Decodable {
        var holdKey: String?
        var terminal: String?
        var editor: String?
        var browser: String?
        var claudeCommand: String?
        var actionOrder: String?
        var zoxide: Bool?
        var roots: [String]?
        var activeDays: Int?
        var projects: [Entry]?
        var windows: WindowsSetting?
    }

    /// The `windows` setting: `false` to leave the windows to each app, or the section; `true`
    /// and an empty section mean the default layout.
    enum WindowsSetting: Decodable {
        case on(Bool)
        case layout(Windows)

        init(from decoder: any Decoder) throws {
            if let isOn = try? decoder.singleValueContainer().decode(Bool.self) {
                self = .on(isOn)
            } else {
                self = .layout(try Windows(from: decoder))
            }
        }
    }

    struct Windows: Decodable {
        var builtIn: Int?
        var external: Int?
        var gap: Double?
        var editor: Columns?
    }

    struct Columns: Decodable {
        var builtIn: Int?
        var external: Int?
    }

    struct Entry: Decodable {
        var name: String?
        var path: String
        var devCommand: String?
    }
}

/// The settings file could not be read, with a description for the user.
public struct LauncherConfigError: Error, Equatable, Sendable {
    public var message: String
}
