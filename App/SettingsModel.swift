import AppKit
import Observation
import PlaincontrolCore
import os

/// The settings as the settings window shows them, read from the settings file and written
/// back to it a setting at a time (``LauncherConfigFile/update(at:_:)``), so the user's own
/// text and comments stay.
@MainActor
@Observable
final class SettingsModel {
    /// The settings as last read.
    private(set) var config = LauncherConfig()
    /// Why the file cannot be read, while it cannot; nothing is written meanwhile.
    private(set) var problem: String?
    /// Where the file was copied before it was written whole, until the user has seen it.
    var backup: String?
    @ObservationIgnored let launcher: LauncherController
    /// Watchers of the file's folder and of the file, while the window is open.
    @ObservationIgnored private var folderWatcher: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private var fileWatcher: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "settings")

    init(launcher: LauncherController) {
        self.launcher = launcher
        reload()
    }

    /// Reads the file again.
    func reload() {
        do {
            let config = try LauncherConfigFile.load(from: AppInfo.settingsPath)
            if config != self.config { self.config = config }
            problem = nil
        } catch {
            problem = error.message
        }
    }

    /// Applies `change` to the settings in the file as it is now, and lets the launcher know.
    func change(_ change: (inout LauncherConfig) -> Void) {
        do {
            let update = try LauncherConfigFile.update(at: AppInfo.settingsPath, change)
            config = update.config
            problem = nil
            if let backup = update.backup {
                log.notice("Wrote the settings file whole, keeping the old one as a backup")
                self.backup = backup
            }
        } catch {
            problem = error.message
            NSSound.beep()
        }
        launcher.reloadSettings()
    }

    /// Opens the file in the app that opens YAML files, creating it from the template first.
    func openFile() {
        do {
            try LauncherConfigFile.createIfMissing(at: AppInfo.settingsPath)
            NSWorkspace.shared.open(URL(filePath: AppInfo.settingsPath))
        } catch {
            log.error("Could not create the settings file: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    /// Reads the file again whenever it changes, until ``stopWatching()``: written in place,
    /// or replaced, as many editors save, which changes its folder.
    func startWatching() {
        guard folderWatcher == nil else { return }
        reload()
        folderWatcher = watch((AppInfo.settingsPath as NSString).deletingLastPathComponent)
        fileWatcher = watch(AppInfo.settingsPath)
    }

    func stopWatching() {
        folderWatcher?.cancel()
        fileWatcher?.cancel()
        folderWatcher = nil
        fileWatcher = nil
    }

    private func watch(_ path: String) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        watcher.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.folderWatcher != nil else { return }
                self.reload()
                self.launcher.reloadSettings()
                // A file that was replaced is a new file: watch that one from now on.
                self.fileWatcher?.cancel()
                self.fileWatcher = self.watch(AppInfo.settingsPath)
            }
        }
        watcher.setCancelHandler { close(descriptor) }
        watcher.resume()
        return watcher
    }
}
