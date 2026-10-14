import PlaincontrolCore

enum AppInfo {
    /// The app's name, which also names its folder in Application Support.
    #if DEBUG
        static let name = HookSocket.developmentAppName
    #else
        static let name = HookSocket.releaseAppName
    #endif
}
