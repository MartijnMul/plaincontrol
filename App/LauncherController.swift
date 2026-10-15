import AppKit
import Observation
import PlaincontrolCore
import SwiftUI
import os

/// Shows the launcher panel, answers its keys and runs the chosen action on a project.
///
/// The projects come from Plaincontrol's own history (sessions started and launcher actions),
/// the projects file and its roots, and zoxide when the user has it. zoxide is read in the
/// background at start-up and whenever the launcher opens; when each folder last changed is
/// looked up at most once a minute. The list updates as answers come.
@MainActor
@Observable
final class LauncherController {
    private(set) var launcher = Launcher(items: [])
    /// The folder search to add a project, while it is open.
    private(set) var pathFinder: PathFinder?
    /// Why the projects could not be read or the last action failed, while the panel is open.
    private(set) var problem: String?
    @ObservationIgnored private var panel: LauncherPanel?
    @ObservationIgnored private var keyTap: LauncherKeyTap?
    @ObservationIgnored private var config = LauncherConfig()
    @ObservationIgnored private var folders: [ProjectFolder] = []
    @ObservationIgnored private var lastScan: Date?
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var zoxide: [Zoxide.Entry] = []
    @ObservationIgnored private var isAskingZoxide = false
    @ObservationIgnored private var usage: ProjectUsage
    @ObservationIgnored private let sessions: () -> [Session]
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "launcher")

    /// The app the editor action opens, if one is set or Visual Studio Code is installed.
    @ObservationIgnored private var editor: URL?

    /// - Parameter sessions: The current sessions, which put their projects at the top.
    init(sessions: @escaping () -> [Session]) {
        self.sessions = sessions
        usage = Self.loadUsage()
        loadConfig()
        scanFolders()
        askZoxide()
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// Shows the launcher, or the Accessibility settings when it may not take the keyboard.
    func show() {
        let keyTap =
            keyTap
            ?? LauncherKeyTap(
                onKey: { [weak self] key in self?.handle(key) },
                onClick: { [weak self] in self?.hide() })
        self.keyTap = keyTap
        guard keyTap.start() else {
            log.notice("The launcher may not take the keyboard; asking for Accessibility")
            NSWorkspace.shared.open(LauncherHotkey.accessibilitySettings)
            return
        }

        loadConfig()
        pathFinder = nil
        editor = EditorApp.url(for: config.editor)
        if let name = config.editor, editor == nil {
            problem = "Cannot find the editor “\(name)” set in \(Self.settingsFileForDisplay)."
        }
        launcher = Launcher(items: items(), actions: ProjectAction.allCases.filter(isAvailable))
        let panel = panel ?? LauncherPanel(content: LauncherView(controller: self))
        self.panel = panel
        panel.present()
        scanFolders()
        askZoxide()
    }

    func hide() {
        keyTap?.stop()
        panel?.orderOut(nil)
    }

    /// A Claude Code session started in `folder`, which counts as use of its project.
    func sessionStarted(in folder: String) {
        usage.record(ProjectFolders.repositoryRoot(containing: folder) ?? folder)
        saveUsage()
    }

    /// The key that opens the launcher when held, as last read from the settings.
    var holdKey: HoldKey { config.holdKey }

    /// What the launcher calls an action; the editor action is named after the editor.
    func title(of action: ProjectAction) -> String {
        switch action {
        case .editor: editor.map(EditorApp.name(of:)) ?? action.title
        case .claude, .terminal, .finder: action.title
        }
    }

    /// Opens the settings file, creating it from a template first if needed.
    func editSettings() {
        do {
            try LauncherConfigFile.createIfMissing()
            NSWorkspace.shared.open(URL(filePath: LauncherConfigFile.defaultPath))
        } catch {
            log.error("Could not create the settings file: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    static var settingsFileForDisplay: String {
        (LauncherConfigFile.defaultPath as NSString).abbreviatingWithTildeInPath
    }

    private func loadConfig() {
        do {
            config = try LauncherConfigFile.load()
            problem = nil
        } catch {
            problem = "Cannot read \(Self.settingsFileForDisplay): \(error.message)"
        }
    }

    private func items() -> [LauncherItem] {
        ProjectCatalog.items(
            config: config, folders: folders, zoxide: config.zoxide ? zoxide : [], usage: usage, sessions: sessions())
    }

    /// Looks up when every project folder last changed, unless it did less than a minute ago.
    /// A folder seen for the first time is listed undated, so only a search finds it, until
    /// its date comes in.
    private func scanFolders() {
        guard !isScanning, lastScan.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true else { return }
        isScanning = true
        let paths = ProjectCatalog.folderPaths(config: config, usage: usage)
        let known = Dictionary(folders.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        folders = paths.map { known[$0] ?? ProjectFolder(path: $0, lastChange: nil) }
        Task {
            for await folder in ProjectFolders.scan(paths) {
                if let index = folders.firstIndex(where: { $0.path == folder.path }) { folders[index] = folder }
                if isShown { launcher.update(items: items()) }
            }
            lastScan = .now
            isScanning = false
        }
    }

    /// Reads the folders zoxide ranks and turns them into projects, off the main thread: finding
    /// where a folder really is may wait for macOS to grant access to it.
    private func askZoxide() {
        guard config.zoxide, !isAskingZoxide, let executable = Zoxide.executable() else { return }
        isAskingZoxide = true
        Task {
            let projects = await Task.detached {
                Zoxide.query(executable: executable).map { Zoxide.projects(from: $0, resolve: Zoxide.location(of:)) }
            }.value
            isAskingZoxide = false
            guard let projects else {
                // The launcher works without zoxide; keep what it said last time.
                log.error("Could not read zoxide's folders")
                return
            }
            zoxide = projects
            if isShown { launcher.update(items: items()) }
        }
    }

    private func handle(_ key: Launcher.Key) {
        guard isShown else { return }
        if var finder = pathFinder {
            let outcome = finder.press(key, list: ProjectFolders.subfolders(of:))
            pathFinder = finder
            switch outcome {
            case .stay: break
            case .cancel: pathFinder = nil
            case .add(let path): add(path)
            }
            return
        }
        switch launcher.press(key) {
        case .stay: break
        case .close: hide()
        case .run(let action, let project): run(action, on: project)
        case .findFolder:
            pathFinder = PathFinder(
                folder: NSHomeDirectory(), home: NSHomeDirectory(), list: ProjectFolders.subfolders(of:))
        }
    }

    /// Adds the folder at `path` as a project, by counting it as used, and opens it.
    private func add(_ path: String) {
        usage.record(path)
        saveUsage()
        if !folders.contains(where: { $0.path == path }) {
            folders.append(ProjectFolder(path: path, lastChange: nil))
        }
        launcher.update(items: items())
        let added = Project(path: path)
        let project = launcher.items.first { $0.project.resolvedPath == added.resolvedPath }?.project ?? added
        log.info("Added a project from the launcher")
        pathFinder = nil
        launcher.open(project)
    }

    private func run(_ action: ProjectAction, on project: Project) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            fail("The folder of \(project.name) does not exist.")
            return
        }
        let folder = URL(filePath: project.path, directoryHint: .isDirectory)
        let frame = newWindowFrame(for: action)
        switch action {
        case .claude, .terminal:
            do {
                NSApp.yieldActivation(toApplicationWithBundleIdentifier: ITerm2Controller().bundleIdentifier)
                let command = action == .claude ? config.claudeCommand : nil
                try ITerm2Controller().openWindow(in: project.path, running: command, frame: frame)
            } catch {
                fail("Could not open iTerm2: \(error.launcherMessage)")
                return
            }
        case .finder:
            let mover = frame.map { WindowMover(bundleIdentifier: "com.apple.finder", frame: $0) }
            NSWorkspace.shared.open(folder)
            mover?.moveNewWindow()
        case .editor:
            guard let editor else { return }
            let mover = frame.flatMap { frame in
                Bundle(url: editor)?.bundleIdentifier.map { WindowMover(bundleIdentifier: $0, frame: frame) }
            }
            NSWorkspace.shared.open([folder], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
            mover?.moveNewWindow()
        }
        log.info("Ran \(action.rawValue, privacy: .public) on a project")
        usage.record(project.path)
        saveUsage()
        hide()
    }

    /// Where the window `action` opens goes, when the settings arrange windows.
    private func newWindowFrame(for action: ProjectAction) -> CGRect? {
        guard let layout = config.windows, let main = NSScreen.screens.first else { return nil }
        // AppKit puts the origin at the bottom left of the main screen; window lists and
        // AppleScript at its top left.
        let screens = NSScreen.screens.map { screen in
            var frame = screen.visibleFrame
            frame.origin.y = main.frame.maxY - frame.maxY
            return WindowPlacement.Screen(visibleFrame: frame, isBuiltIn: screen.isBuiltIn)
        }
        let mouse = NSEvent.mouseLocation
        return WindowPlacement.frame(
            for: action, screens: screens, current: NSScreen.screens.firstIndex { $0.frame.contains(mouse) },
            windows: WindowPlacement.windowsOnScreen(excluding: ProcessInfo.processInfo.processIdentifier),
            layout: layout)
    }

    private func fail(_ message: String) {
        problem = message
        NSSound.beep()
    }

    private func isAvailable(_ action: ProjectAction) -> Bool {
        switch action {
        case .claude, .terminal, .finder: true
        case .editor: editor != nil
        }
    }

    // MARK: Usage

    private static var usageURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(AppInfo.name)/project-usage.json")
    }

    private static func loadUsage() -> ProjectUsage {
        guard let data = try? Data(contentsOf: usageURL) else { return ProjectUsage() }
        return (try? JSONDecoder().decode(ProjectUsage.self, from: data)) ?? ProjectUsage()
    }

    private func saveUsage() {
        do {
            let url = Self.usageURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(usage).write(to: url, options: .atomic)
        } catch {
            log.error("Could not save project usage: \(String(describing: error), privacy: .public)")
        }
    }
}

extension Launcher.Key {
    /// The launcher key for a key press, if it is one.
    init?(keyCode: UInt16, characters: String?) {
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 36, 76: self = .enter
        case 53: self = .escape
        case 51: self = .backspace
        default:
            guard let character = characters?.first else { return nil }
            self = .character(character)
        }
    }
}

extension NSScreen {
    /// Whether this is the Mac's own display, such as a laptop's.
    fileprivate var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }
}

extension TerminalControlError {
    fileprivate var launcherMessage: String {
        switch self {
        case .notAuthorized:
            "allow \(AppInfo.name) to control iTerm2 in System Settings › Privacy & Security › Automation."
        case .failed(let reason): reason
        case .unsupported, .terminalNotRunning, .paneNotFound: "iTerm2 did not respond."
        }
    }
}
