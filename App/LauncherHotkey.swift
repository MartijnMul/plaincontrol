import AppKit
import PlaincontrolCore

/// Opens the launcher when the right Option key is held on its own, in any app.
///
/// Watching the keyboard outside the app needs the Accessibility permission; until it is
/// granted, the launcher only opens from the menu.
@MainActor
final class LauncherHotkey {
    private var trigger = HoldTrigger()
    private var monitors: [Any] = []
    private let onHold: () -> Void

    /// The right and left Option keys in `NSEvent.modifierFlags`, below the public flags.
    private static let rightOptionFlag: UInt = 0x40
    private static let leftOptionFlag: UInt = 0x20
    private static let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .shift, .function]

    init(onHold: @escaping () -> Void) {
        self.onHold = onHold
    }

    static var isAllowed: Bool { AXIsProcessTrusted() }

    static let accessibilitySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Starts watching the keyboard, asking for the Accessibility permission first if needed.
    func start() {
        guard monitors.isEmpty else { return }
        guard Self.isAllowed else {
            // The value of `kAXTrustedCheckOptionPrompt`, a global Swift 6 cannot read safely.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            waitForPermission()
            return
        }
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: events,
            handler: { [weak self] event in MainActor.assumeIsolated { self?.handle(event) } })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: events,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            })
        {
            monitors.append(local)
        }
    }

    /// Starts once the user grants the permission in System Settings.
    private func waitForPermission() {
        Task { [weak self] in
            while !Self.isAllowed {
                try? await Task.sleep(for: .seconds(2))
            }
            self?.start()
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            trigger.keyPressed()
        case .flagsChanged:
            let flags = event.modifierFlags
            let press = trigger.modifierChanged(
                keyCode: event.keyCode,
                isDown: flags.rawValue & Self.rightOptionFlag != 0,
                othersDown: !flags.intersection(Self.otherModifiers).isEmpty
                    || flags.rawValue & Self.leftOptionFlag != 0)
            if let press { fire(after: press) }
        default:
            break
        }
    }

    private func fire(after press: Int) {
        Task { [weak self, duration = trigger.duration] in
            try? await Task.sleep(for: duration)
            guard let self, self.trigger.holdElapsed(press) else { return }
            self.onHold()
        }
    }
}
