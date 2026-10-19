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

/// What the user configures about the launcher, in `launcher.yaml`:
///
/// ```yaml
/// holdKey: rightOption  # rightOption, rightCommand, rightControl or rightShift
/// terminal: iTerm2      # the app for 1 and 2, by name or bundle identifier
/// editor: Cursor        # the app for 4, by name or bundle identifier
/// claudeCommand: claude # what 1 runs in the new terminal window
/// zoxide: true          # also list and rank by zoxide's folders, when it is installed
/// roots:                # folders whose subfolders are projects
///   - ~/Developer
/// activeDays: 90        # a project is listed this long after its last change or use
/// projects:             # always listed, with an optional name
///   - name: My App
///     path: ~/Developer/my-app
/// windows:              # put new windows in free columns, nearest the user first
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
    /// The terminal for the Claude Code and terminal actions, by app name or bundle
    /// identifier, or nil to pick one (``AppChoice``).
    public var terminal: String?
    /// The editor for the editor action, by app name or bundle identifier, or nil to pick one
    /// (``AppChoice``).
    public var editor: String?
    /// The command the Claude Code action runs in the project's folder.
    public var claudeCommand = "claude"
    /// Whether to also list and rank by the folders the user visits with zoxide, when installed.
    public var zoxide = true
    /// Folders whose subfolders are projects, by their absolute paths.
    public var roots: [String] = []
    /// How long a project stays in the list after its last change or use.
    public var activeDays = 90
    /// Projects that are always listed, in the order of the file.
    public var projects: [Project] = []
    /// How to arrange the windows the launcher opens, or nil to leave it to each app.
    public var windows: WindowLayout?

    public init(
        holdKey: HoldKey = .rightOption, terminal: String? = nil, editor: String? = nil,
        claudeCommand: String = "claude", zoxide: Bool = true, roots: [String] = [], activeDays: Int = 90,
        projects: [Project] = [], windows: WindowLayout? = nil
    ) {
        self.holdKey = holdKey
        self.terminal = terminal
        self.editor = editor
        self.claudeCommand = claudeCommand
        self.zoxide = zoxide
        self.roots = roots.map { ($0 as NSString).standardizingPath }
        self.activeDays = activeDays
        self.projects = projects
        self.windows = windows
    }
}

/// The file in which the user configures the launcher, by hand.
public enum LauncherConfigFile {
    /// `~/.config/plaincontrol/launcher.yaml`, shared by the release and development builds.
    public static var defaultPath: String {
        URL.homeDirectory.appending(path: ".config/plaincontrol/launcher.yaml").path(percentEncoded: false)
    }

    /// What a new settings file starts with: every setting at its default.
    public static let template = """
        # Settings for the Plaincontrol launcher. Changes apply the next time it opens.

        # The key that opens the launcher when you hold it on its own:
        # rightOption, rightCommand, rightControl or rightShift.
        holdKey: rightOption

        # The terminal for 1 and 2, by app name or bundle identifier. Without one, it is the
        # terminal you run Claude Code in most. Plaincontrol can open iTerm2 windows so far.
        # terminal: iTerm2

        # The editor for 4, by app name (such as Cursor or Zed) or bundle identifier. Without
        # one, it is the editor you run Claude Code in most; if you don't, the app your Mac
        # opens code files with, or else Visual Studio Code.
        # editor: Visual Studio Code

        # What 1 runs in a new terminal window in the project's folder.
        claudeCommand: claude

        # The launcher lists the folders where you start Claude Code or open projects from the
        # launcher. If you use zoxide (https://github.com/ajeetdsouza/zoxide), it also lists the
        # folders you visit most, and ranks by both. zoxide's data is only read, never changed.
        zoxide: true

        # Folders whose subfolders are projects, such as a folder of git repositories. A project
        # is listed while you work on it: a commit (in a git repository) or a changed file (in
        # any other folder), or a Claude Code session or launcher action in it, within
        # activeDays. Older ones show up when you search for them.
        roots:
        #  - ~/Developer
        activeDays: 90

        # Projects that are always listed, with an optional name; without one, a project is
        # named after its folder.
        projects:
        #  - name: My App
        #    path: ~/Developer/my-app

        # Where the windows the launcher opens go. Without this, each app decides. With it,
        # every screen is split into columns, as a window manager such as Rectangle does, and a
        # new window takes a free column: on the screen with the pointer first, then on the
        # other external screens, then on the built-in one. Each screen fills from the columns
        # nearest you, taking you to sit in front of the built-in screen: a screen in front of
        # you from its middle, then from left to right; one to your left from right to left.
        # The editor takes several columns side by side. Finder and the editor are moved once
        # their window appears.
        # windows:
        #   builtIn: 2    # columns on the built-in screen
        #   external: 3   # columns on every other screen
        #   gap: 10       # points around and between windows
        #   editor:       # columns the editor takes
        #     builtIn: 2
        #     external: 2

        """

    /// The configuration in `text`; a project listed twice counts once.
    public static func parse(_ text: String) throws(LauncherConfigError) -> LauncherConfig {
        let file: File
        do {
            guard let node = try Yams.compose(yaml: text) else { return LauncherConfig() }
            file = try YAMLDecoder().decode(File.self, from: node)
        } catch {
            throw LauncherConfigError(message: String(describing: error))
        }
        if let days = file.activeDays, days < 1 {
            throw LauncherConfigError(message: "activeDays must be at least 1.")
        }
        var holdKey = HoldKey.rightOption
        if let name = file.holdKey {
            guard let key = HoldKey(rawValue: name) else {
                let names = HoldKey.allCases.map(\.rawValue).joined(separator: ", ")
                throw LauncherConfigError(message: "holdKey must be one of \(names).")
            }
            holdKey = key
        }
        let claudeCommand = file.claudeCommand?.trimmingCharacters(in: .whitespaces) ?? "claude"
        if claudeCommand.isEmpty {
            throw LauncherConfigError(message: "claudeCommand cannot be empty.")
        }
        let terminal = file.terminal?.trimmingCharacters(in: .whitespaces)
        let editor = file.editor?.trimmingCharacters(in: .whitespaces)
        var windows: WindowLayout?
        if let section = file.windows {
            let layout = WindowLayout(
                builtInColumns: section.builtIn ?? 2, externalColumns: section.external ?? 3, gap: section.gap ?? 10,
                editorBuiltInColumns: section.editor?.builtIn ?? 2, editorExternalColumns: section.editor?.external ?? 2
            )
            let columns = [
                layout.builtInColumns, layout.externalColumns, layout.editorBuiltInColumns,
                layout.editorExternalColumns,
            ]
            guard columns.allSatisfy((1...6).contains) else {
                throw LauncherConfigError(message: "windows: every number of columns must be from 1 to 6.")
            }
            guard (0...100).contains(layout.gap) else {
                throw LauncherConfigError(message: "windows: gap must be from 0 to 100.")
            }
            windows = layout
        }
        var seen = Set<String>()
        let projects = (file.projects ?? [])
            .map { Project(path: $0.path, name: $0.name) }
            .filter { seen.insert($0.path).inserted }
        return LauncherConfig(
            holdKey: holdKey, terminal: terminal?.isEmpty == false ? terminal : nil,
            editor: editor?.isEmpty == false ? editor : nil, claudeCommand: claudeCommand,
            zoxide: file.zoxide ?? true, roots: file.roots ?? [], activeDays: file.activeDays ?? 90,
            projects: projects, windows: windows)
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

    private struct File: Decodable {
        var holdKey: String?
        var terminal: String?
        var editor: String?
        var claudeCommand: String?
        var zoxide: Bool?
        var roots: [String]?
        var activeDays: Int?
        var projects: [Entry]?
        var windows: Windows?
    }

    private struct Windows: Decodable {
        var builtIn: Int?
        var external: Int?
        var gap: Double?
        var editor: Columns?
    }

    private struct Columns: Decodable {
        var builtIn: Int?
        var external: Int?
    }

    private struct Entry: Decodable {
        var name: String?
        var path: String
    }
}

/// The settings file could not be read, with a description for the user.
public struct LauncherConfigError: Error, Equatable, Sendable {
    public var message: String
}
