import AppKit
import ApplicationServices

/// Chooses an item in another app's menu bar through the Accessibility API, as a click on it
/// would, for what an app offers in its menus only. Needs the Accessibility permission, which
/// the launcher has.
@MainActor
enum MenuItem {
    /// The item at `path` in the menu bar of the app with `bundleIdentifier`: the title of its
    /// menu, of any submenus, and of the item itself, such as `["File", "New Window"]`.
    static func find(_ path: [String], in bundleIdentifier: String) -> AXUIElement? {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
            var menu = element(kAXMenuBarAttribute, of: AXUIElementCreateApplication(process.processIdentifier))
        else { return nil }
        for (index, title) in path.enumerated() {
            guard let item = children(of: menu).first(where: { self.title(of: $0) == title }) else { return nil }
            if index == path.count - 1 { return item }
            // A menu bar item, or an item with a submenu, holds its menu as its only child.
            guard let submenu = children(of: item).first else { return nil }
            menu = submenu
        }
        return nil
    }

    /// Chooses `item`, and says whether the app took it.
    static func choose(_ item: AXUIElement) -> Bool {
        AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
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

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
