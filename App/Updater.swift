import Foundation
import OSLog
import Sparkle

/// Updates through Sparkle, in the release build only (ADR 0006). Sparkle asks on the second
/// launch whether to check automatically, and fetches nothing before the user says yes; Check
/// for Updates… checks once, on demand.
@MainActor
@Observable
final class Updater {
    /// Whether this build updates itself: the release build, with a feed and a key to check
    /// updates against. The development build has neither.
    let isAvailable: Bool
    /// Whether a check can start now: not while one runs.
    private(set) var canCheck = false

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

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let reminders = GentleReminders()
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: reminders)
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
        canCheck = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in self?.canCheck = canCheck }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Tells Sparkle that a menu bar app may show a scheduled update without taking the focus
/// from the app the user is in, rather than not at all.
private final class GentleReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
