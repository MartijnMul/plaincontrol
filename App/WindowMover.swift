import AppKit
import ApplicationServices
import PlaincontrolCore

/// Moves windows through the Accessibility API: one that is on screen, or the one an app is
/// about to open.
///
/// Apps such as Finder and editors cannot be told where to open a window, so the mover notes
/// the app's windows before it is asked to open one, then waits for a window that was not
/// there and moves it. When the app shows a window it had already, such as an editor that
/// has the folder open, nothing appears and nothing moves. Needs the Accessibility permission,
/// which the launcher has.
@MainActor
struct WindowMover {
    private let bundleIdentifier: String
    private let frame: CGRect
    private let existing: [AXUIElement]

    /// Notes the windows of the app with `bundleIdentifier`, before it is asked to open one.
    ///
    /// - Parameter frame: Where the new window goes, in global coordinates from the top left of
    ///   the main screen.
    init(bundleIdentifier: String, frame: CGRect) {
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        existing = Self.app(bundleIdentifier).map(Self.windows(of:)) ?? []
    }

    /// Waits a few seconds, long enough for the app to start, for its new window, and moves it.
    func moveNewWindow() {
        Task {
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let app = Self.app(bundleIdentifier) else { continue }
                if let window = Self.windows(of: app).first(where: { window in
                    !existing.contains { CFEqual($0, window) }
                }) {
                    move(window)
                    // Some apps restore their own size and place once the window is shown.
                    try? await Task.sleep(for: .milliseconds(500))
                    move(window)
                    return
                }
            }
        }
    }

    /// Moves a window that is on screen now, found by its process and frame.
    static func move(_ move: PlaincontrolCore.WindowPlacement.Move) {
        let app = AXUIElementCreateApplication(move.window.processIdentifier)
        let target = windows(of: app).first { window in
            guard let frame = frame(of: window) else { return false }
            let edges = [
                frame.minX - move.window.frame.minX, frame.minY - move.window.frame.minY,
                frame.width - move.window.frame.width, frame.height - move.window.frame.height,
            ]
            return edges.allSatisfy { abs($0) < 1 }
        }
        if let target { place(target, at: move.frame) }
    }

    private func move(_ window: AXUIElement) {
        Self.place(window, at: frame)
    }

    /// Moves `window` to `frame`, in global coordinates from the top left of the main screen.
    static func place(_ window: AXUIElement, at frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else {
            return
        }
        // Moving first lets the window grow on its new screen; macOS caps the size to the
        // screen it is on.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func app(_ bundleIdentifier: String) -> AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first.map {
            AXUIElementCreateApplication($0.processIdentifier)
        }
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
