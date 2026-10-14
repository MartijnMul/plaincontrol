import AppKit
import PlaincontrolCore

/// Opens the launcher when its hold key, such as the right Option key, is held on its own, in
/// any app.
///
/// Watching the keyboard outside the app needs the Accessibility permission, as does the
/// launcher itself (``LauncherKeyTap``).
@MainActor
final class LauncherHotkey {
    private var trigger = HoldTrigger()
    private var monitors: [Any] = []
    private let holdKey: () -> HoldKey
    private let onHold: () -> Void

    /// - Parameters:
    ///   - holdKey: The key to hold, asked on every key event so a new setting takes effect.
    ///   - onHold: Called when the key has been held on its own.
    init(holdKey: @escaping () -> HoldKey, onHold: @escaping () -> Void) {
        self.holdKey = holdKey
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
            let key = holdKey()
            if trigger.keyCode != key.keyCode { trigger = HoldTrigger(keyCode: key.keyCode) }
            // The device-dependent bits tell the right key from the left one.
            let flags = event.modifierFlags.rawValue
            let press = trigger.modifierChanged(
                keyCode: event.keyCode,
                isDown: flags & key.deviceFlag != 0,
                othersDown: flags & HoldKey.allDeviceFlags & ~key.deviceFlag != 0
                    || event.modifierFlags.contains(.function))
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
