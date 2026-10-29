import Foundation
import PlaincontrolCore
import PlaincontrolHooks

enum AppInfo {
    /// The app's name, which also names its folder in Application Support.
    #if DEBUG
        static let name = HookSocket.developmentAppName
    #else
        static let name = HookSocket.releaseAppName
    #endif

    /// The settings file of this build: the development build has its own.
    static let settingsPath = LauncherConfigFile.defaultPath(appName: name)

    /// The subsystem of the app's log messages: its bundle identifier.
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.martijnmul.plaincontrol"
}
