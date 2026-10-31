import Foundation
import OSLog
import Sparkle

/// Updates through Sparkle, in the release build only (ADR 0006 and 0008). Sparkle asks on the
/// second launch whether to check automatically, and fetches nothing before the user says yes;
/// Check for Updates… checks once, on demand. Once checks are allowed, Sparkle also downloads
/// updates by itself, unless the user turned that off, and installs them when Plaincontrol
/// quits; until then the menu offers to restart, and no window opens.
@MainActor
@Observable
final class Updater {
    /// Whether this build updates itself: the release build, with a feed and a key to check
    /// updates against. The development build has neither.
    let isAvailable: Bool
    /// Whether a check can start now: not while one runs.
    private(set) var canCheck = false
    /// The version of an update downloaded and waiting for Plaincontrol to quit, if any.
    private(set) var readyVersion: String?

    /// Whether Sparkle checks for updates once a day, as the user chose; Sparkle keeps it.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    /// Whether Sparkle downloads and installs updates without asking, as the user chose;
    /// Sparkle keeps it.
    var installsAutomatically: Bool {
        get {
            access(keyPath: \.installsAutomatically)
            return controller.updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.installsAutomatically) {
                controller.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let reminders = GentleReminders()
    @ObservationIgnored private let quietInstall = QuietInstall()
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// Installs the downloaded update and opens Plaincontrol again.
    @ObservationIgnored private var installNow: (() -> Void)?

    init(bundle: Bundle = .main) {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: quietInstall, userDriverDelegate: reminders)
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !feed.isEmpty, !key.isEmpty else {
            isAvailable = false
            return
        }
        do {
            try controller.updater.start()
            isAvailable = true
        } catch {
            Logger(subsystem: AppInfo.subsystem, category: "updates")
                .error("Cannot start the updater: \(error, privacy: .public)")
            isAvailable = false
            return
        }
        quietInstall.onReady = { [weak self] version, install in
            self?.readyVersion = version
            self?.installNow = install
        }
        canCheck = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in self?.canCheck = canCheck }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Installs the update that is ready and opens Plaincontrol again.
    func restartToUpdate() {
        installNow?()
    }
}

/// Takes over a downloaded update: Sparkle installs it when Plaincontrol quits, and the menu
/// offers to restart sooner, instead of Sparkle showing a window about it later.
private final class QuietInstall: NSObject, SPUUpdaterDelegate {
    var onReady: (@MainActor (String, @escaping () -> Void) -> Void)?

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let version = item.displayVersionString
        MainActor.assumeIsolated { onReady?(version, immediateInstallHandler) }
        return true
    }
}

/// Tells Sparkle that a menu bar app may show a scheduled update without taking the focus
/// from the app the user is in, rather than not at all.
private final class GentleReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
