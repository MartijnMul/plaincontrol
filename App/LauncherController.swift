import AppKit
import Observation
import PlaincontrolCore
import SwiftUI
import os

/// Shows the launcher panel, answers its keys and runs the chosen action on a project.
///
/// The projects come from the projects file and the git repositories in its folders. Git is
/// asked for their last commits in the background, at start-up and when the launcher opens,
/// at most once a minute; the list updates when the answer comes.
@MainActor
@Observable
final class LauncherController {
    private(set) var launcher = Launcher(items: [])
    /// Why the projects could not be read or the last action failed, while the panel is open.
    private(set) var problem: String?
    @ObservationIgnored private var panel: LauncherPanel?
    @ObservationIgnored private var keyTap: LauncherKeyTap?
    @ObservationIgnored private var config = ProjectsConfig()
    @ObservationIgnored private var repositories: [Repository] = []
    @ObservationIgnored private var lastScan: Date?
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var usage: ProjectUsage
    @ObservationIgnored private let sessions: () -> [Session]
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "launcher")

    static let vsCode = "com.microsoft.VSCode"

    /// - Parameter sessions: The current sessions, which put their projects at the top.
    init(sessions: @escaping () -> [Session]) {
        self.sessions = sessions
        usage = Self.loadUsage()
        loadConfig()
        scanRepositories()
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
        launcher = Launcher(items: items(), actions: ProjectAction.allCases.filter(isAvailable))
        let panel = panel ?? LauncherPanel(content: LauncherView(controller: self))
        self.panel = panel
        panel.present()
        scanRepositories()
    }

    func hide() {
        keyTap?.stop()
        panel?.orderOut(nil)
    }

    /// A Claude Code session started in `folder`, which counts as use of its project.
    func sessionStarted(in folder: String) {
        usage.record(Repositories.root(containing: folder) ?? folder)
        saveUsage()
    }

    /// Opens the projects file, creating it from a template first if needed.
    func editProjects() {
        do {
            try ProjectsFile.createIfMissing()
            NSWorkspace.shared.open(URL(filePath: ProjectsFile.defaultPath))
        } catch {
            log.error("Could not create the projects file: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    static var projectsFileForDisplay: String {
        (ProjectsFile.defaultPath as NSString).abbreviatingWithTildeInPath
    }

    private func loadConfig() {
        do {
            config = try ProjectsFile.load()
            problem = nil
        } catch {
            problem = "Cannot read \(Self.projectsFileForDisplay): \(error.message)"
        }
    }

    private func items() -> [LauncherItem] {
        ProjectCatalog.items(config: config, repositories: repositories, usage: usage, sessions: sessions())
    }

    /// Asks git for the last commit of every repository, unless it did less than a minute ago.
    private func scanRepositories() {
        guard !isScanning, lastScan.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true else { return }
        isScanning = true
        let paths = ProjectCatalog.repositoryPaths(config: config, usage: usage)
        Task {
            let found = await Repositories.scan(paths)
            repositories = found
            lastScan = .now
            isScanning = false
            if isShown { launcher.update(items: items()) }
        }
    }

    private func handle(_ key: Launcher.Key) {
        guard isShown else { return }
        switch launcher.press(key) {
        case .stay: break
        case .close: hide()
        case .run(let action, let project): run(action, on: project)
        }
    }

    private func run(_ action: ProjectAction, on project: Project) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            fail("The folder of \(project.name) does not exist.")
            return
        }
        let folder = URL(filePath: project.path, directoryHint: .isDirectory)
        switch action {
        case .claude:
            do {
                NSApp.yieldActivation(toApplicationWithBundleIdentifier: ITerm2Controller().bundleIdentifier)
                try ITerm2Controller().openWindow(in: project.path, running: "claude")
            } catch {
                fail("Could not open iTerm2: \(error.launcherMessage)")
                return
            }
        case .finder:
            NSWorkspace.shared.open(folder)
        case .vsCode:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.vsCode) else { return }
            NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
        log.info("Ran \(action.rawValue, privacy: .public) on a project")
        usage.record(project.path)
        saveUsage()
        hide()
    }

    private func fail(_ message: String) {
        problem = message
        NSSound.beep()
    }

    private func isAvailable(_ action: ProjectAction) -> Bool {
        switch action {
        case .claude, .finder: true
        case .vsCode: NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.vsCode) != nil
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

/// A floating panel over every app and Space, which never takes the focus from the app in
/// front; ``LauncherKeyTap`` brings it the keys.
final class LauncherPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        // The window is transparent; the SwiftUI view draws the card and its shadow.
        contentView = NSHostingView(rootView: content)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// Shows the panel near the top of the screen with the mouse pointer.
    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameTopLeftPoint(
                NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - visible.height * 0.18))
        }
        orderFrontRegardless()
    }
}
