import AppKit
import ApplicationServices
import OSLog
import PlaincontrolCore

/// Opens a new Claude Code session in the Claude desktop app in a window of its own, in a
/// project's folder, through the Accessibility API, as the user would by hand: File › New
/// Session in New Window, then the folder picker in the new window. The app's links cannot
/// open a window of their own and ask to trust the folder each time (``ClaudeDesktop``).
///
/// Every step is found by what it is, not by English text: the menu item by its title in each
/// language the app comes in, the folder button by its label in each language or, once it has
/// a folder, by its help text, a path, and the folder in the picker by that path. A folder the
/// picker doesn't know, one Claude Code has never worked in, opens through the link instead,
/// which asks whether to trust it.
/// Needs the Accessibility permission, which the launcher has.
@MainActor
enum ClaudeDesktopWindow {
    /// Why the window could not be opened in the folder; the session then stays as far as it
    /// got, so the user can go on by hand.
    enum Failure: Error {
        case noMenuItem
        case noWindow
        case noFolderButton
        case noFolderPicker
        case folderNotChosen
    }

    private static let log = Logger(subsystem: AppInfo.subsystem, category: "desktop")

    /// Opens the window in `folder`, in the desktop app at `app`.
    ///
    /// - Parameter makeRoom: Where the new window goes and which windows move first, asked for
    ///   just before the window opens, so the windows on screen then count. Without a
    ///   placement, the app places the window.
    static func open(
        in folder: String, app: URL, makeRoom: () -> PlaincontrolCore.WindowPlacement.Placement?
    ) async throws(Failure) {
        let titles = ClaudeDesktop.newWindowMenuTitles(inAppAt: app)
        // The labels take a moment to read, so they are read while the window opens.
        let labels = Task.detached { ClaudeDesktop.folderButtonLabels(inAppAt: app) }

        // The item is in the File menu only while the main window shows the Code tab, which a
        // link without a folder goes to without asking anything. It also starts the app.
        var item = menuItem(titledAnyOf: titles)
        if item == nil {
            NSWorkspace.shared.open(
                [ClaudeDesktop.codeURL], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil)
            item = await poll(seconds: 20) { menuItem(titledAnyOf: titles) }
        }
        guard let item else { throw .noMenuItem }

        let placement = makeRoom()
        placement?.moves.forEach(WindowMover.move)
        let existing = windows()
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success,
            let window = await poll(seconds: 5, { windows().first { w in !existing.contains { CFEqual($0, w) } } })
        else { throw .noWindow }
        if let placement { WindowMover.place(window, at: placement.frame) }

        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let wanted = Set([folder, URL(filePath: folder).resolvingSymlinksInPath().path(percentEncoded: false)])
        func shown(_ button: AXUIElement) -> String? {
            string(button, kAXHelpAttribute).flatMap { ClaudeDesktop.folder(shownAs: $0, home: home) }
        }
        // Before version 4.29 a new window had the last folder, and so a path as help text; now
        // it starts without one, and only the label tells the button apart.
        let folderLabels = await labels.value
        func folderButton() -> AXUIElement? {
            first(in: window) {
                string($0, kAXRoleAttribute) == kAXPopUpButtonRole
                    && (shown($0) != nil
                        || string($0, kAXDescriptionAttribute).map {
                            ClaudeDesktop.isFolderButton(described: $0, labels: folderLabels)
                        } == true)
            }
        }
        guard let button = await poll(seconds: 5, folderButton) else { throw .noFolderButton }
        if shown(button).map(wanted.contains) == true { return }

        // A press right after the window appears can come before the page listens to it.
        var field: AXUIElement?
        for _ in 0..<5 where field == nil {
            AXUIElementPerformAction(folderButton() ?? button, kAXPressAction as CFString)
            field = await poll(seconds: 0.6) { first(in: window) { string($0, kAXRoleAttribute) == kAXTextFieldRole } }
        }
        guard let field else { throw .noFolderPicker }
        let name = URL(filePath: folder).lastPathComponent
        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, name as CFString)
        let entry = await poll(seconds: 3) {
            first(in: window) {
                string($0, kAXRoleAttribute) == kAXMenuItemRole
                    && string($0, kAXHelpAttribute).map(wanted.contains) == true
            }
        }
        guard let entry else {
            // Claude Code has not worked in the folder yet, so the app asks to trust it.
            log.info("The desktop app's folder picker does not know the folder; opening it through a link")
            close(window)
            NSWorkspace.shared.open(
                [ClaudeDesktop.newSessionURL(in: folder)], withApplicationAt: app,
                configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return
        }
        AXUIElementPerformAction(entry, kAXPressAction as CFString)
        let chosen = await poll(seconds: 3) {
            folderButton().flatMap { shown($0).map(wanted.contains) == true ? $0 : nil }
        }
        guard chosen != nil else { throw .folderNotChosen }
        // The app may restore its own size for the window once it shows it.
        if let placement { WindowMover.place(window, at: placement.frame) }
    }

    private static func menuItem(titledAnyOf titles: Set<String>) -> AXUIElement? {
        guard let menuBar = application().flatMap({ element(kAXMenuBarAttribute, of: $0) }) else { return nil }
        for menuBarItem in children(of: menuBar) {
            // A menu bar item holds its menu as its only child.
            guard let menu = children(of: menuBarItem).first else { continue }
            if let item = children(of: menu).first(where: {
                string($0, kAXTitleAttribute).map(titles.contains) ?? false
            }) {
                return item
            }
        }
        return nil
    }

    private static func close(_ window: AXUIElement) {
        if let button = element(kAXCloseButtonAttribute, of: window) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    /// The desktop app, set up to describe its pages: an app built on web pages, such as an
    /// Electron app, describes them only once asked.
    private static func application() -> AXUIElement? {
        guard
            let process = NSRunningApplication.runningApplications(
                withBundleIdentifier: ClaudeDesktop.bundleIdentifier
            ).first
        else { return nil }
        let app = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return app
    }

    private static func windows() -> [AXUIElement] {
        guard let app = application() else { return [] }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// The first element in `root`, or below it, that `matches`, looking at no more than a few
    /// thousand elements, as a page can hold many.
    private static func first(in root: AXUIElement, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        var budget = 5000
        func search(_ element: AXUIElement) -> AXUIElement? {
            budget -= 1
            guard budget > 0 else { return nil }
            if matches(element) { return element }
            for child in children(of: element) {
                if let found = search(child) { return found }
            }
            return nil
        }
        return search(root)
    }

    /// Asks `get` every tenth of a second until it gives something, for at most `seconds`.
    private static func poll<T>(seconds: Double, _ get: () -> T?) async -> T? {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while true {
            if let value = get() { return value }
            guard ContinuousClock.now < deadline else { return nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
