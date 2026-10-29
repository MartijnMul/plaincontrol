import Darwin

/// The Claude Code process a session runs in.
///
/// Identified by its process ID and the time it started, so a later process that is given
/// the same ID is not mistaken for it.
public struct SessionProcess: Sendable, Equatable, Codable {
    public var pid: Int32
    /// When the process started, in microseconds since 1970, as the kernel reports it.
    public var startTime: Int64

    /// The environment variable in which Claude Code passes its process ID to hook commands.
    public static let environmentVariable = "CLAUDE_PID"

    private enum CodingKeys: String, CodingKey {
        case pid
        case startTime = "start_time"
    }

    public init(pid: Int32, startTime: Int64) {
        self.pid = pid
        self.startTime = startTime
    }

    /// The running process with this ID, or nil when there is none.
    public init?(pid: Int32) {
        guard let info = Self.info(pid: pid) else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        self.init(pid: pid, startTime: Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec))
    }

    /// The Claude Code process that ran the hook command, from its environment.
    public init?(environment: [String: String]) {
        guard let value = environment[Self.environmentVariable], let pid = Int32(value) else { return nil }
        self.init(pid: pid)
    }

    /// Whether this process is still running.
    public var isRunning: Bool {
        SessionProcess(pid: pid) == self
    }

    /// The terminal the process runs in, such as `/dev/ttys003`, or nil when it has none.
    ///
    /// Claude Code runs in the foreground of the shell in its terminal tab, so this is the
    /// tab's terminal device, which some terminals show to AppleScript.
    public var terminalDevice: String? {
        guard let device = Self.info(pid: pid)?.kp_eproc.e_tdev, device != -1,
            let name = devname(device, S_IFCHR).map({ String(cString: $0) }), name != "??"
        else { return nil }
        return "/dev/\(name)"
    }

    /// What the kernel reports about the running process with this ID.
    private static func info(pid: Int32) -> kinfo_proc? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // For a process that does not exist, sysctl succeeds and returns nothing.
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0,
            info.kp_proc.p_stat != SZOMB
        else { return nil }
        return info
    }
}
