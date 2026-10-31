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
    /// Whether the launcher has opened since Plaincontrol started.
    private(set) var hasOpened = false
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
    /// The browser for a dev server's page and an empty browser window.
    @ObservationIgnored private var browser: URL?
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
            try LauncherConfigFile.writeSchema(nextTo: AppInfo.settingsPath)
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
                onKey: { [weak self] key, isRepeat in self?.handle(key, isRepeat: isRepeat) },
                onClick: { [weak self] in
                    self?.log.info("Closed the launcher on a click")
                    self?.hide()
                })
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
        let terminals = terminals
        launcher = Launcher(items: items(), apps: AppWindow.allCases.filter(canOpen)) { project in
            config.actionOrder.order(
                offered.filter { $0 != .devServer || Self.devCommand(for: project, config: config) != nil },
                for: project, usage: usage)
        } selection: { project, actions in
            config.actionOrder.selection(in: actions, for: project, usage: usage)
        } devServerQuestion: { project in
            DevServerQuestion(
                hasPage: Self.pagePort(of: project, config: config) != nil,
                selected: usage.lastDevServerStart(in: project) ?? .standard)
        } serverActions: { server in
            // An orphaned server's terminal pane is gone.
            ServerAction.allCases.filter {
                $0 != .showTerminal || (!server.isOrphaned && terminals.canFocus(server.process.terminal))
            }
        }
        let panel = panel ?? LauncherPanel(content: LauncherView(controller: self))
        self.panel = panel
        panel.present()
        hasOpened = true
        scanFolders()
        askZoxide()
        scanServers()
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

    /// Whether the launcher has no history yet, as on the first start.
    var isNew: Bool { usage.uses.isEmpty }

    /// Adds the sessions in Claude Code's own history to the launcher's, so the projects worked
    /// on before Plaincontrol came appear and rank by that work. Returns how many projects that
    /// gives; reading the folders may wait for macOS to ask for access to them.
    func addClaudeCodeHistory() async -> Int {
        let sessions = await Task.detached { ClaudeCodeHistory.sessions() }.value
        usage.merge(sessions.map { (path: $0.folder, date: $0.date) })
        saveUsage()
        lastScan = nil
        scanFolders()
        log.info("Added \(sessions.count, privacy: .public) sessions from Claude Code's history")
        return Set(sessions.map(\.folder)).count
    }

    /// The key that opens the launcher when held, as last read from the settings.
    var holdKey: HoldKey { config.holdKey }

    /// Reads the settings again, so a change in them applies at once, the hold key included.
    func reloadSettings() {
        loadConfig()
    }

    /// The app the launcher picks for `role` without a setting, by bundle identifier: for the
    /// terminal, one it can open windows in.
    func automaticApp(_ role: AppRole) -> String? {
        switch role {
        case .terminal:
            AppChoice.terminal(
                setting: nil, ranked: appUsage.ranked(.terminal),
                supported: terminals.controllers.map(\.bundleIdentifier), isInstalled: Apps.isInstalled
            ).app
        case .editor:
            AppChoice.editor(
                ranked: appUsage.ranked(.editor), defaults: Apps.defaults(forTypes: AppChoice.codeFileTypes),
                isInstalled: Apps.isInstalled)
        case .browser: Apps.browser.flatMap(Apps.bundleIdentifier(of:))
        }
    }

    /// The installed apps that could be the terminal, the editor or the browser, by bundle
    /// identifier: the ones the user works in first, then the known ones; for the browser, the
    /// apps that open web pages.
    func installedApps(_ role: AppRole) -> [String] {
        var seen = Set<String>()
        let known = role == .browser ? Apps.browsers : role.knownApps.sorted()
        return (appUsage.ranked(role) + known).filter {
            seen.insert($0).inserted && Apps.isInstalled($0)
        }
    }

    /// Whether the launcher can ask the browser with `bundleIdentifier` for a window of its own.
    func canOpenWindows(inBrowser bundleIdentifier: String) -> Bool {
        BrowserWindow.arguments(in: bundleIdentifier) != nil
    }

    /// Whether Plaincontrol can open windows in the terminal with `bundleIdentifier`.
    func canOpenWindows(in bundleIdentifier: String) -> Bool {
        terminals.controller(forApp: bundleIdentifier) != nil
    }

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

    /// What the launcher calls something to do with a running server: its terminal pane by the
    /// terminal's name.
    func title(of action: ServerAction, for server: RunningServer) -> String {
        guard action == .showTerminal, let controller = terminals.controller(for: server.process.terminal) else {
            return action.title
        }
        return "\(controller.name) tab"
    }

    /// What the launcher calls an app it opens an empty window of: by its name.
    func title(of app: AppWindow) -> String {
        switch app {
        case .terminal: terminalName ?? "Terminal"
        case .browser: browser.map(Apps.name(of:)) ?? "Browser"
        case .finder: folderApp.map(Apps.name(of:)) ?? "Finder"
        }
    }

    /// Whether the launcher can open an empty window of `app`.
    private func canOpen(_ app: AppWindow) -> Bool {
        switch app {
        case .terminal: terminal.app.flatMap(terminals.controller(forApp:)) != nil
        case .browser: browserWindowArguments(for: nil) != nil
        case .finder: true
        }
    }

    /// What the launcher calls a place for the dev server's window, such as `Minimised in iTerm2`.
    func title(of window: DevServerWindow) -> String {
        let terminal = terminalName ?? "the terminal"
        switch window {
        case .shown: return "Window in \(terminal)"
        case .minimized: return "Minimised in \(terminal)"
        }
    }

    /// What the launcher calls opening the dev server's page too, or only the server.
    func title(ofPage opensPage: Bool) -> String {
        opensPage ? "And its page in \(browser.map(Apps.name(of:)) ?? "the browser")" : "Only the server"
    }

    /// The address of the page of `project`'s dev server, to show next to it.
    func pageAddress(in project: Project) -> String? {
        Self.pagePort(of: project, config: config).map { "localhost:\($0)" }
    }

    /// The port of the page of `project`'s development server, if the launcher can tell it.
    private nonisolated static func pagePort(of project: Project, config: LauncherConfig) -> Int? {
        devCommand(for: project, config: config).flatMap { DevServer.port(in: project.path, command: $0) }
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
        if let setting = config.browser {
            browser = Apps.app(for: setting)
            if browser == nil {
                problem = "Cannot find the browser “\(setting)” set in \(Self.settingsFileForDisplay)."
            }
        } else {
            browser = Apps.browser
        }
        if let setting = config.editor {
            editor = Apps.app(for: setting)
            if editor == nil {
                problem = "Cannot find the editor “\(setting)” set in \(Self.settingsFileForDisplay)."
            }
        } else {
            editor = automaticApp(.editor).flatMap(Apps.app(bundleIdentifier:))
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

    static var settingsFileForDisplay: String {
        (AppInfo.settingsPath as NSString).abbreviatingWithTildeInPath
    }

    private func loadConfig() {
        do {
            config = try LauncherConfigFile.load(from: AppInfo.settingsPath)
            problem = nil
        } catch {
            problem =
                "Cannot read \(Self.settingsFileForDisplay): \(error.message) Choose Settings… in the menu bar to fix it."
        }
    }

    /// The projects the launcher lists that the settings do not name, in its order.
    func foundProjects() -> [Project] {
        ProjectCatalog.found(in: items(), config: config)
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

    /// Looks for the servers running in the projects, off the main thread.
    private func scanServers() {
        let projects = launcher.items.map(\.project)
        Task {
            let servers = await Task.detached { RunningServers.scan(in: projects) }.value
            if isShown { launcher.update(servers: servers) }
        }
    }

    private func handle(_ key: Launcher.Key, isRepeat: Bool) {
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
        switch launcher.press(key, isRepeat: isRepeat) {
        case .stay: break
        case .close:
            log.info("Closed the launcher on a key")
            hide()
        case .run(let action, let project): run(action, on: project)
        case .runDevServer(let project, let start): run(.devServer, on: project, devServer: start)
        case .openApp(let app): open(app)
        case .findFolder:
            pathFinder = PathFinder(
                folder: NSHomeDirectory(), home: NSHomeDirectory(), list: ProjectFolders.subfolders(of:))
        case .serverAction(let action, let server): run(action, on: server)
        }
    }

    private func run(_ action: ServerAction, on server: RunningServer) {
        switch action {
        case .openPage:
            guard let port = server.port else { return }
            openPage(at: port)
            log.info("Opened the page of a running server")
            hide()
        case .showTerminal:
            guard let controller = terminals.controller(for: server.process.terminal) else { return }
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: controller.bundleIdentifier)
            do {
                try terminals.focus(server.process.terminal)
            } catch .paneNotFound, .terminalNotRunning {
                fail("The \(controller.name) tab of this server is gone.")
                return
            } catch {
                fail("Could not open \(controller.name): \(error.launcherMessage(for: controller.name))")
                return
            }
            log.info("Showed the terminal of a running server")
            hide()
        case .stop:
            guard RunningServers.stop(server) else {
                fail("Could not stop the server of \(server.project.name); it may have stopped already.")
                scanServers()
                return
            }
            log.info("Stopped a running server")
            launcher.update(servers: launcher.servers.filter { $0.id != server.id })
            // The rest of its job may take a moment to end, or a server may start again.
            Task {
                try? await Task.sleep(for: .seconds(1))
                scanServers()
            }
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

    /// - Parameter devServer: How to start the dev server: its window in a column or in the Dock,
    ///   and whether to open its page once the server listens.
    private func run(_ action: ProjectAction, on project: Project, devServer: DevServerStart? = nil) {
        let minimized = devServer?.window == .minimized
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
        let placement = action == .claudeDesktop || minimized ? nil : newWindowPlacement(for: action)
        placement?.moves.forEach(WindowMover.move)
        let frame = placement?.frame
        switch action {
        case .claude, .terminal, .devServer:
            guard let terminalController else { return }
            do {
                try openTerminalWindow(
                    with: terminalController, in: project.path, running: command, frame: frame, minimized: minimized)
            } catch {
                fail(
                    "Could not open \(terminalController.name): \(error.launcherMessage(for: terminalController.name))")
                return
            }
        case .finder:
            openFolderWindow(folder, frame: frame)
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
        if devServer?.opensPage == true, let port = Self.pagePort(of: project, config: config) { openPage(at: port) }
        log.info("Ran \(action.rawValue, privacy: .public) on a project")
        usage.record(project.path, action: action, devServer: devServer)
        saveUsage()
        hide()
    }

    /// Opens an empty window of `app`, in a free column as a project's windows: the terminal's as
    /// it opens new windows, with nothing typed in it, and Finder's on the home folder.
    private func open(_ app: AppWindow) {
        let home = URL.homeDirectory
        // The browser's window takes a column, as a terminal window does.
        let placed: ProjectAction = app == .finder ? .finder : .terminal
        switch app {
        case .terminal:
            guard let controller = openableTerminal() else { return }
            let placement = newWindowPlacement(for: placed)
            placement?.moves.forEach(WindowMover.move)
            do {
                try openTerminalWindow(with: controller, in: nil, running: nil, frame: placement?.frame)
            } catch {
                fail("Could not open \(controller.name): \(error.launcherMessage(for: controller.name))")
                return
            }
        case .browser:
            guard openBrowserWindow(nil) else {
                fail("Your browser cannot be asked for a new window.")
                return
            }
        case .finder:
            let placement = newWindowPlacement(for: placed)
            placement?.moves.forEach(WindowMover.move)
            openFolderWindow(home, frame: placement?.frame)
        }
        log.info("Opened an empty \(app.rawValue, privacy: .public) window")
        hide()
    }

    /// Opens a window of the terminal at `frame`, moving it there once it shows when the terminal
    /// cannot place it itself, or minimised in the Dock.
    private func openTerminalWindow(
        with controller: any TerminalController, in directory: String?, running command: String?, frame: CGRect?,
        minimized: Bool = false
    ) throws(TerminalControlError) {
        let mover =
            controller.placesWindows
            ? nil : frame.map { WindowMover(bundleIdentifier: controller.bundleIdentifier, frame: $0) }
        if !minimized { NSApp.yieldActivation(toApplicationWithBundleIdentifier: controller.bundleIdentifier) }
        try controller.openWindow(
            in: directory, running: command, frame: controller.placesWindows ? frame : nil, minimized: minimized)
        mover?.moveNewWindow()
    }

    /// Opens `folder` in the app the user opens folders with, moving its new window to `frame`.
    private func openFolderWindow(_ folder: URL, frame: CGRect?) {
        let app = folderApp.flatMap(Apps.bundleIdentifier(of:)) ?? Apps.finder
        let mover = frame.map { WindowMover(bundleIdentifier: app, frame: $0) }
        NSWorkspace.shared.open(folder)
        mover?.moveNewWindow()
    }

    /// Opens the page at `port` on this Mac in the browser, once a server listens there.
    private func openPage(at port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        Task {
            guard await Task.detached(operation: { await DevServer.waitUntilListening(on: port) }).value else {
                log.notice("Nothing listened on the dev server's port in time")
                return
            }
            if !openBrowserWindow(url) {
                if let browser {
                    NSWorkspace.shared.open(
                        [url], withApplicationAt: browser, configuration: .init(), completionHandler: nil)
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
            log.info("Opened the dev server's page")
        }
    }

    /// The browser, and the arguments that open `url` in a new window of it, or an
    /// empty one; nil when it cannot be asked for a window.
    private func browserWindowArguments(for url: URL?) -> (browser: URL, id: String, arguments: [String])? {
        guard let browser, let id = Apps.bundleIdentifier(of: browser),
            let arguments = BrowserWindow.arguments(opening: url, in: id)
        else { return nil }
        return (browser, id, arguments)
    }

    /// Opens `url`, or nothing, in a new window of the browser, in a free column as a
    /// terminal window; false when the browser cannot be asked for a window.
    private func openBrowserWindow(_ url: URL?) -> Bool {
        guard let (browser, id, arguments) = browserWindowArguments(for: url) else { return false }
        let placement = newWindowPlacement(for: .terminal)
        placement?.moves.forEach(WindowMover.move)
        let mover = placement.map { WindowMover(bundleIdentifier: id, frame: $0.frame) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        // A running browser only takes the arguments from an instance of its own.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: browser, configuration: configuration)
        mover?.moveNewWindow()
        return true
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
        URL.applicationSupportDirectory.appending(path: "\(AppInfo.folderName)/project-usage.json")
    }

    private static var appUsageURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(AppInfo.folderName)/app-usage.json")
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
