import AppKit
import ApplicationServices

/// Moves the window an app is about to open to a frame, through the Accessibility API.
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

    private func move(_ window: AXUIElement) {
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
