import AppKit
import Observation
import PlaincontrolCore
import PlaincontrolHooks
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
    /// Something to know about the actions, such as a terminal Plaincontrol cannot open yet.
    private(set) var notice: String?
    @ObservationIgnored private var panel: LauncherPanel?
    @ObservationIgnored private var keyTap: LauncherKeyTap?
    @ObservationIgnored private var config = LauncherConfig()
    @ObservationIgnored private var folders: [ProjectFolder] = []
    @ObservationIgnored private var lastScan: Date?
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var zoxide: [Zoxide.Entry] = []
    @ObservationIgnored private var isAskingZoxide = false
    @ObservationIgnored private var usage: ProjectUsage
    @ObservationIgnored private var appUsage: AppUsage
    @ObservationIgnored private let sessions: () -> [Session]
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "launcher")

    /// The app the editor action opens, if there is one.
    @ObservationIgnored private var editor: URL?
    /// The app the folder action opens, normally Finder.
    @ObservationIgnored private var folderApp: URL?
    /// The terminal the Claude Code and terminal actions open.
    @ObservationIgnored private var terminal = AppChoice.Terminal(app: nil)
    @ObservationIgnored private let terminals = TerminalControllers.standard
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    /// - Parameter sessions: The current sessions, which put their projects at the top.
    init(sessions: @escaping () -> [Session]) {
        self.sessions = sessions
        usage = Self.load(ProjectUsage.self, from: Self.usageURL) ?? ProjectUsage()
        appUsage = Self.load(AppUsage.self, from: Self.appUsageURL) ?? AppUsage()
        do {
            try LauncherConfigFile.moveOldFile()
        } catch {
            log.error("Could not rename the settings file: \(String(describing: error), privacy: .public)")
        }
        do {
            try LauncherConfigFile.writeSchema()
        } catch {
            log.error("Could not write the settings schema: \(String(describing: error), privacy: .public)")
        }
        loadConfig()
        scanFolders()
        askZoxide()
        watchActivations()
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
        chooseApps()
        let offered = ProjectAction.allCases.filter(isAvailable)
        let config = config
        let usage = usage
        launcher = Launcher(items: items()) { project in
            config.actionOrder.order(
                offered.filter { $0 != .devServer || Self.devCommand(for: project, config: config) != nil },
                for: project, usage: usage)
        } selection: { project, actions in
            config.actionOrder.selection(in: actions, for: project, usage: usage)
        }
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

    /// A Claude Code session started in `folder`, which counts as use of its project, and at
    /// `terminal`, which counts as use of the terminal or editor it runs in.
    func sessionStarted(in folder: String, at terminal: TerminalLocation?) {
        usage.record(ProjectFolders.repositoryRoot(containing: folder) ?? folder)
        saveUsage()
        appUsage.record(terminal)
        save(appUsage, to: Self.appUsageURL)
    }

    /// The key that opens the launcher when held, as last read from the settings.
    var holdKey: HoldKey { config.holdKey }

    /// What the launcher calls an action: after the app it opens, where it knows one.
    func title(of action: ProjectAction) -> String {
        switch action {
        case .claude, .devServer: terminalName.map { "\(action.title) in \($0)" } ?? action.title
        case .terminal: terminalName ?? action.title
        case .finder: folderApp.map(Apps.name(of:)) ?? action.title
        case .editor: editor.map(Apps.name(of:)) ?? action.title
        case .claudeDesktop: action.title
        }
    }

    /// The command `action` runs in `project`, to show next to it, where it depends on the project.
    func command(of action: ProjectAction, in project: Project) -> String? {
        action == .devServer ? Self.devCommand(for: project, config: config) : nil
    }

    /// The command that starts `project`'s development server: the one set, or else the one
    /// the project declares.
    private nonisolated static func devCommand(for project: Project, config: LauncherConfig) -> String? {
        config.devCommand(for: project) ?? DevServer.command(in: project.path)
    }

    /// The terminal the actions open, or the one Plaincontrol would open but cannot.
    private var terminalName: String? {
        terminal.app.flatMap { terminals.controller(forApp: $0)?.name } ?? terminal.unsupported.map(Apps.name(ofApp:))
    }

    /// Counts each editor the user brings to the front as a use, so the editor action follows
    /// the editor they work in, also when they run Claude Code in a terminal.
    private func watchActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleIdentifier = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self, self.appUsage.recordActivation(of: bundleIdentifier) else { return }
                self.save(self.appUsage, to: Self.appUsageURL)
            }
        }
    }

    /// Picks the apps the actions open: the ones set, or else from the apps the user works in
    /// and the ones macOS opens folders and code files with.
    private func chooseApps() {
        folderApp = Apps.folders
        if let setting = config.editor {
            editor = Apps.app(for: setting)
            if editor == nil {
                problem = "Cannot find the editor “\(setting)” set in \(Self.settingsFileForDisplay)."
            }
        } else {
            editor = AppChoice.editor(
                ranked: appUsage.ranked(.editor), defaults: Apps.defaults(forTypes: AppChoice.codeFileTypes),
                isInstalled: Apps.isInstalled
            ).flatMap(Apps.app(bundleIdentifier:))
        }
        var terminalSetting: String?
        if let setting = config.terminal {
            terminalSetting = Apps.app(for: setting).flatMap(Apps.bundleIdentifier(of:))
            if terminalSetting == nil {
                problem = "Cannot find the terminal “\(setting)” set in \(Self.settingsFileForDisplay)."
            }
        }
        terminal = AppChoice.terminal(
            setting: terminalSetting, ranked: appUsage.ranked(.terminal),
            supported: terminals.controllers.map(\.bundleIdentifier), isInstalled: Apps.isInstalled)
        notice = nil
        if let app = terminal.app.flatMap(terminals.controller(forApp:)), let other = terminal.unsupported {
            notice =
                "\(AppInfo.name) cannot open \(Apps.name(ofApp: other)) windows yet, so new terminal windows open in \(app.name)."
        }
    }

    /// The controller for the terminal the actions open, or nil after saying why there is none.
    private func openableTerminal() -> (any TerminalController)? {
        if let controller = terminal.app.flatMap(terminals.controller(forApp:)) { return controller }
        let supported = terminals.controllers.map(\.name).formatted(.list(type: .or))
        if let other = terminal.unsupported {
            fail("\(AppInfo.name) cannot open \(Apps.name(ofApp: other)) windows yet, only \(supported).")
        } else {
            fail("\(AppInfo.name) opens new terminal windows in \(supported), which is not installed.")
        }
        return nil
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
        // What can fail goes before any window moves to make room.
        var command: String?
        switch action {
        case .claude: command = config.claudeCommand
        case .devServer:
            command = Self.devCommand(for: project, config: config)
            if command == nil {
                fail("\(project.name) no longer has a dev server to start.")
                return
            }
        case .terminal, .finder, .editor, .claudeDesktop: break
        }
        var terminalController: (any TerminalController)?
        if [.claude, .terminal, .devServer].contains(action) {
            guard let controller = openableTerminal() else { return }
            terminalController = controller
        }
        // The desktop app's window opens after a few steps, so it makes room then.
        let placement = action == .claudeDesktop ? nil : newWindowPlacement(for: action)
        placement?.moves.forEach(WindowMover.move)
        let frame = placement?.frame
        switch action {
        case .claude, .terminal, .devServer:
            guard let terminalController else { return }
            do {
                NSApp.yieldActivation(toApplicationWithBundleIdentifier: terminalController.bundleIdentifier)
                try terminalController.openWindow(in: project.path, running: command, frame: frame)
            } catch {
                fail(
                    "Could not open \(terminalController.name): \(error.launcherMessage(for: terminalController.name))")
                return
            }
        case .finder:
            let app = folderApp.flatMap(Apps.bundleIdentifier(of:)) ?? Apps.finder
            let mover = frame.map { WindowMover(bundleIdentifier: app, frame: $0) }
            NSWorkspace.shared.open(folder)
            mover?.moveNewWindow()
        case .editor:
            guard let editor else { return }
            let mover = frame.flatMap { frame in
                Apps.bundleIdentifier(of: editor).map { WindowMover(bundleIdentifier: $0, frame: frame) }
            }
            NSWorkspace.shared.open([folder], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
            mover?.moveNewWindow()
        case .claudeDesktop:
            guard let app = Apps.app(bundleIdentifier: ClaudeDesktop.bundleIdentifier) else {
                fail("The Claude desktop app is no longer installed.")
                return
            }
            openDesktopWindow(in: project.path, app: app)
        }
        log.info("Ran \(action.rawValue, privacy: .public) on a project")
        usage.record(project.path, action: action)
        saveUsage()
        hide()
    }

    /// Opens a new session in the desktop app in a window of its own, placed as a terminal
    /// window would be. The launcher is closed by then, so a step that fails beeps and leaves
    /// the window as far as it got, for the user to go on by hand.
    private func openDesktopWindow(in folder: String, app: URL) {
        Task {
            do {
                try await ClaudeDesktopWindow.open(in: folder, app: app) { newWindowPlacement(for: .claudeDesktop) }
            } catch {
                log.notice(
                    "Could not open a desktop app window in the folder: \(String(describing: error), privacy: .public)")
                NSSound.beep()
            }
        }
    }

    /// Where the window `action` opens goes, and which windows move first to make room, when
    /// the settings arrange windows.
    private func newWindowPlacement(for action: ProjectAction) -> PlaincontrolCore.WindowPlacement.Placement? {
        guard let layout = config.windows, let main = NSScreen.screens.first else { return nil }
        // AppKit puts the origin at the bottom left of the main screen; window lists and
        // AppleScript at its top left.
        let screens = NSScreen.screens.map { screen in
            var frame = screen.visibleFrame
            frame.origin.y = main.frame.maxY - frame.maxY
            return PlaincontrolCore.WindowPlacement.Screen(visibleFrame: frame, isBuiltIn: screen.isBuiltIn)
        }
        let mouse = NSEvent.mouseLocation
        return PlaincontrolCore.WindowPlacement.placement(
            for: action, screens: screens, current: NSScreen.screens.firstIndex { $0.frame.contains(mouse) },
            windows: PlaincontrolCore.WindowPlacement.windowsOnScreen(
                excluding: ProcessInfo.processInfo.processIdentifier),
            layout: layout)
    }

    private func fail(_ message: String) {
        problem = message
        NSSound.beep()
    }

    private func isAvailable(_ action: ProjectAction) -> Bool {
        switch action {
        case .claude, .terminal, .finder, .devServer: true
        case .editor: editor != nil
        case .claudeDesktop: Apps.isInstalled(ClaudeDesktop.bundleIdentifier)
        }
    }

    // MARK: Usage

    private static var usageURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(AppInfo.name)/project-usage.json")
    }

    private static var appUsageURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(AppInfo.name)/app-usage.json")
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func saveUsage() {
        save(usage, to: Self.usageURL)
    }

    private func save(_ value: some Encodable, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            log.error(
                "Could not save \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
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
    fileprivate func launcherMessage(for terminal: String) -> String {
        switch self {
        case .notAuthorized:
            "allow \(AppInfo.name) to control \(terminal) in System Settings › Privacy & Security › Automation."
        case .failed(let reason): reason
        case .unsupported, .terminalNotRunning, .paneNotFound: "\(terminal) did not respond."
        }
    }
}
