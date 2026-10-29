import Foundation
import PlaincontrolCore
import PlaincontrolHooks

enum AppInfo {
    /// The name of the build, which names its folder in Application Support, its socket and its
    /// settings, so the development build keeps all of them apart from the installed app.
    #if DEBUG
        static let folderName = HookSocket.developmentAppName
    #else
        static let folderName = HookSocket.releaseAppName
    #endif

    /// The name the app shows. A development build started for screenshots (`make demo`, with
    /// `PLAINCONTROL_DEMO=1`) shows the release name, while it keeps its own folders.
    static let name =
        ProcessInfo.processInfo.environment["PLAINCONTROL_DEMO"] == "1" ? HookSocket.releaseAppName : folderName

    /// The settings file of this build: the development build has its own.
    static let settingsPath = LauncherConfigFile.defaultPath(appName: folderName)

    /// The subsystem of the app's log messages: its bundle identifier.
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.martijnmul.plaincontrol"
}
