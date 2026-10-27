import AppKit
import ApplicationServices

/// Notices a dialog in another app's window through the Accessibility API, such as one that
/// asks the user to confirm something before the app goes on. Needs the Accessibility
/// permission, which the launcher has.
@MainActor
enum AppDialog {
    /// Whether the focused window of the app with `bundleIdentifier` shows an alert dialog.
    ///
    /// Apps built on web pages, such as Electron apps, describe their pages only once asked,
    /// so this asks first.
    static func isShown(in bundleIdentifier: String) -> Bool {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        else { return false }
        let app = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
            let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return false }
        var budget = 5000
        return containsAlert(window as! AXUIElement, budget: &budget)
    }

    /// Whether `element` is or holds an alert dialog, looking at no more than `budget`
    /// elements, as a long conversation can hold many.
    private static func containsAlert(_ element: AXUIElement, budget: inout Int) -> Bool {
        budget -= 1
        guard budget > 0 else { return false }
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
            subrole as? String == "AXApplicationAlertDialog"
        {
            return true
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success else {
            return false
        }
        return (children as? [AXUIElement] ?? []).contains { containsAlert($0, budget: &budget) }
    }
}
