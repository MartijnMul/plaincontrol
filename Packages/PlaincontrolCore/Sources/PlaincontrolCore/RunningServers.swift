import Darwin
import Foundation
import PlaincontrolHooks

/// A process of the user's that accepts connections on a TCP port, as the kernel reports it.
public struct ListeningProcess: Sendable, Equatable {
    public var pid: Int32
    /// The parent process; 1 when the process that started it is gone and launchd took it over.
    public var parent: Int32
    /// The process group: a terminal job, such as `pnpm dev` and everything it started.
    public var group: Int32
    /// The name of the program, such as `node`.
    public var name: String
    /// The folder the process runs in, when the kernel tells it.
    public var folder: String?
    /// The ports it listens on, lowest first.
    public var ports: [Int]
    public var started: Date
    /// The terminal pane it was started in, from the same few variables of its environment that
    /// the hook passes on for a session, and its terminal device.
    public var terminal: TerminalLocation?

    public init(
        pid: Int32, parent: Int32, group: Int32, name: String, folder: String?, ports: [Int], started: Date,
        terminal: TerminalLocation? = nil
    ) {
        self.pid = pid
        self.parent = parent
        self.group = group
        self.name = name
        self.folder = folder
        self.ports = ports
        self.started = started
        self.terminal = terminal
    }
}

/// A server running in one of the user's projects, such as a dev server.
public struct RunningServer: Sendable, Equatable, Identifiable {
    public var process: ListeningProcess
    public var project: Project

    public var id: Int32 { process.pid }

    /// The port its page is on: the lowest it listens on.
    public var port: Int? { process.ports.first }

    /// Whether what started it is gone, such as a closed terminal or a finished Claude Code
    /// session, so nothing shows it any more and it was most likely forgotten.
    public var isOrphaned: Bool { process.parent == 1 }
}

/// What the launcher can do with a running server.
public enum ServerAction: CaseIterable, Sendable {
    /// Its page, `localhost` on its port, in the browser.
    case openPage
    /// The terminal pane it runs in, brought to the front.
    case showTerminal
    /// Ends it, with the terminal job it belongs to (``RunningServers/stop(_:)``).
    case stop

    public var title: String {
        switch self {
        case .openPage: "Open page"
        case .showTerminal: "Terminal tab"
        case .stop: "Stop"
        }
    }
}

/// Finds the servers running in the user's projects, and stops them.
///
/// A server is a process that listens on a TCP port from inside a project folder, so the apps
/// that listen on ports of their own, which run elsewhere, are left out without a list of them.
/// The kernel tells this about the user's own processes without any permission.
public enum RunningServers {
    /// Programs that listen in a project folder without being one of its servers: an `ssh -L`
    /// tunnel listens where it was started.
    static let ignoredPrograms: Set<String> = ["ssh"]

    /// The servers listening now in `projects`.
    public static func scan(in projects: [Project]) -> [RunningServer] {
        servers(from: listeningProcesses(), in: projects)
    }

    /// The processes that run in one of `projects`, each with the innermost project it runs in:
    /// orphaned ones first, as they are the ones forgotten, then the newest.
    static func servers(from processes: [ListeningProcess], in projects: [Project]) -> [RunningServer] {
        processes.compactMap { process in
            guard !ignoredPrograms.contains(process.name), let folder = process.folder,
                let project = projects.filter({ $0.contains(folder) }).max(by: { $0.path.count < $1.path.count })
            else { return nil }
            return RunningServer(process: process, project: project)
        }
        .sorted { a, b in
            a.isOrphaned != b.isOrphaned ? a.isOrphaned : a.process.started > b.process.started
        }
    }

    /// Asks `server` to end, as Control-C in its terminal would, with the processes of its terminal
    /// job, such as the package manager that started it; false when it was already gone or may
    /// not be stopped.
    @discardableResult
    public static func stop(_ server: RunningServer) -> Bool {
        let process = server.process
        // The process ID may have gone to a new process since the scan.
        guard let now = info(pid: process.pid), now.started == process.started else { return false }
        let members = groupMembers(process.group)
        let stopsGroup = stopsGroup(
            process.group, ownGroup: getpgrp(), leadsSession: getsid(process.group) == process.group,
            memberNames: members.compactMap { info(pid: $0)?.name })
        return kill(stopsGroup ? -process.group : process.pid, SIGTERM) == 0
    }

    /// Whether to end the whole process `group` of a server, or only the server.
    ///
    /// A terminal job has a group of its own, so ending the group ends what started the server
    /// too. A group led by a shell, or one with a Claude Code session in it, is not the server's
    /// alone, so then only the server ends.
    static func stopsGroup(_ group: Int32, ownGroup: Int32, leadsSession: Bool, memberNames: [String]) -> Bool {
        group > 1 && group != ownGroup && !leadsSession && !memberNames.contains("claude")
    }

    // MARK: Reading the kernel

    /// Every process of the user's that listens on a TCP port.
    static func listeningProcesses() -> [ListeningProcess] {
        allProcesses().compactMap { pid in
            guard let info = info(pid: pid), info.user == getuid() else { return nil }
            let ports = listeningPorts(of: pid)
            guard !ports.isEmpty else { return nil }
            var terminal = TerminalLocation(environment: environment(of: pid))
            terminal?.tty = info.terminalDevice
            return ListeningProcess(
                pid: pid, parent: info.parent, group: info.group, name: info.name, folder: folder(of: pid),
                ports: ports, started: info.started, terminal: terminal)
        }
    }

    /// The variables of a process's environment that say which terminal pane it runs in. The
    /// environment can hold secrets, such as those a secrets manager passes on, so nothing else
    /// in it is kept.
    private static func environment(of pid: Int32) -> [String: String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return [:] }
        return environment(fromArguments: buffer.prefix(size), keeping: terminalVariables)
    }

    /// The environment variables ``TerminalLocation`` reads.
    static let terminalVariables: Set<String> =
        Set(TerminalLocation.paneVariables).union(["TERM_PROGRAM", "__CFBundleIdentifier"])

    /// The variables named in `names` from what the kernel reports as a process's arguments: the
    /// argument count, the path it was started from, padding, the arguments and then the
    /// environment, each ending in a zero byte, and an empty string after the environment.
    static func environment(fromArguments bytes: some Collection<UInt8>, keeping names: Set<String>) -> [String: String]
    {
        let bytes = Array(bytes)
        guard bytes.count > 4 else { return [:] }
        let count = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = 4
        func nextString() -> String? {
            guard index < bytes.count else { return nil }
            let end = bytes[index...].firstIndex(of: 0) ?? bytes.count
            defer { index = end + 1 }
            return String(decoding: bytes[index..<end], as: UTF8.self)
        }
        _ = nextString()
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        for _ in 0..<max(count, 0) { _ = nextString() }
        var environment: [String: String] = [:]
        while let entry = nextString(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let name = String(entry[..<equals])
            if names.contains(name) { environment[name] = String(entry[entry.index(after: equals)...]) }
        }
        return environment
    }

    private static func allProcesses() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes that start in between.
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(max(Int(found), 0)))
    }

    private static func groupMembers(_ group: Int32) -> [Int32] {
        guard group > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: 1024)
        let found = pids.withUnsafeMutableBytes { proc_listpgrppids(group, $0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(max(Int(found), 0)))
    }

    private struct Info {
        var parent: Int32
        var group: Int32
        var user: uid_t
        var name: String
        var started: Date
        /// Such as `/dev/ttys003`, or nil without a terminal.
        var terminalDevice: String?
    }

    private static func info(pid: Int32) -> Info? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let started = Date(
            timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
        return Info(
            parent: Int32(info.pbi_ppid), group: Int32(info.pbi_pgid), user: info.pbi_uid,
            name: string(from: info.pbi_name).nonEmpty ?? string(from: info.pbi_comm), started: started,
            terminalDevice: terminalDevice(info.e_tdev))
    }

    private static func terminalDevice(_ device: UInt32) -> String? {
        guard device != UInt32.max, let name = devname(dev_t(bitPattern: device), S_IFCHR).map({ String(cString: $0) }),
            name != "??"
        else { return nil }
        return "/dev/\(name)"
    }

    private static func folder(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return string(from: info.pvi_cdir.vip_path).nonEmpty
    }

    private static func listeningPorts(of pid: Int32) -> [Int] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var files = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
        let read = files.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        var ports = Set<Int>()
        for file in files.prefix(max(Int(read), 0) / stride) where file.proc_fdtype == PROX_FDTYPE_SOCKET {
            var socket = socket_fdinfo()
            let socketSize = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, file.proc_fd, PROC_PIDFDSOCKETINFO, &socket, socketSize) == socketSize,
                socket.psi.soi_kind == SOCKINFO_TCP,
                socket.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
            else { continue }
            let port = UInt16(truncatingIfNeeded: socket.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            ports.insert(Int(UInt16(bigEndian: port)))
        }
        return ports.sorted()
    }

    /// The text in a fixed-size C string field, which Swift sees as a tuple.
    private static func string<T>(from field: T) -> String {
        withUnsafeBytes(of: field) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
