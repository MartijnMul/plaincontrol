import AppKit
import Observation
import PlaincontrolCore
import SwiftUI
import os

/// Shows the launcher panel, answers its keys and runs the chosen action on a project.
@MainActor
@Observable
final class LauncherController {
    private(set) var launcher = Launcher(projects: [])
    /// Why the projects could not be read or the last action failed, while the panel is open.
    private(set) var problem: String?
    @ObservationIgnored private var panel: LauncherPanel?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var recency: ProjectRecency
    @ObservationIgnored private let sessions: () -> [Session]
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "launcher")

    static let vsCode = "com.microsoft.VSCode"

    /// - Parameter sessions: The current sessions, which count as use of their project.
    init(sessions: @escaping () -> [Session]) {
        self.sessions = sessions
        recency = Self.loadRecency()
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func show() {
        let projects: [Project]
        do {
            projects = try ProjectsFile.load()
            problem = nil
        } catch {
            projects = []
            problem = "Cannot read \(Self.projectsFileForDisplay): \(error.message)"
        }
        launcher = Launcher(
            projects: recency.ordered(projects, sessions: sessions()),
            actions: ProjectAction.allCases.filter(isAvailable))

        let panel = panel ?? LauncherPanel(content: LauncherView(controller: self)) { [weak self] in self?.hide() }
        self.panel = panel
        panel.present()
        keyMonitor =
            keyMonitor
            ?? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
            }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
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

    /// Handles a key while the panel is open, and returns whether it was the launcher's.
    private func handle(_ event: NSEvent) -> Bool {
        guard isShown, let key = Launcher.Key(event) else { return false }
        switch launcher.press(key) {
        case .stay: break
        case .close: hide()
        case .run(let action, let project): run(action, on: project)
        }
        return true
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
        recency.markUsed(project)
        saveRecency()
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

    // MARK: Recency

    private static var recencyURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(AppInfo.name)/recent-projects.json")
    }

    private static func loadRecency() -> ProjectRecency {
        guard let data = try? Data(contentsOf: recencyURL) else { return ProjectRecency() }
        return (try? JSONDecoder().decode(ProjectRecency.self, from: data)) ?? ProjectRecency()
    }

    private func saveRecency() {
        do {
            let url = Self.recencyURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(recency).write(to: url, options: .atomic)
        } catch {
            log.error("Could not save recent projects: \(String(describing: error), privacy: .public)")
        }
    }
}

extension Launcher.Key {
    /// The launcher key for a key press, if it is one; shortcuts with Command or Control are not.
    init?(_ event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return nil }
        switch event.keyCode {
        case 126: self = .up
        case 125: self = .down
        case 36, 76: self = .enter
        case 53: self = .escape
        default:
            guard let character = event.charactersIgnoringModifiers?.first else { return nil }
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

/// A floating panel that takes the keyboard without activating the app, like Spotlight.
final class LauncherPanel: NSPanel, NSWindowDelegate {
    private let onResign: () -> Void

    init(content: some View, onResign: @escaping () -> Void) {
        self.onResign = onResign
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        // The window is transparent; the SwiftUI view draws the card and its shadow, and clicks
        // on the transparent part pass through to the windows below.
        contentView = NSHostingView(rootView: content)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    /// Shows the panel near the top of the screen with the mouse pointer, and gives it the keyboard.
    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameTopLeftPoint(
                NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - visible.height * 0.18))
        }
        makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        onResign()
    }
}
