import Darwin

/// A failure of a Unix domain socket call.
public enum UnixSocketError: Error, Equatable {
    /// The path does not fit in a socket address (about 100 bytes).
    case pathTooLong(String)
    /// Another process already listens on the path.
    case alreadyListening(String)
    /// A system call failed with `errno`.
    case system(call: String, errno: Int32)
}

enum UnixSocket {
    /// A new stream socket that does not raise SIGPIPE when the other end is gone.
    static func make() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.system(call: "socket", errno: errno) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func setTimeouts(_ fd: Int32, seconds: Double) {
        var time = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Calls `body` with the socket address for `path`.
    static func withAddress<T>(
        _ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
    ) throws -> T {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw UnixSocketError.pathTooLong(path)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return try withUnsafePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func connect(_ fd: Int32, to path: String) throws {
        let result = try withAddress(path) { Darwin.connect(fd, $0, $1) }
        guard result == 0 else { throw UnixSocketError.system(call: "connect", errno: errno) }
    }

    /// Writes all bytes, retrying after interruptions and short writes.
    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                throw UnixSocketError.system(call: "write", errno: errno)
            }
            offset += written
        }
    }

    /// Reads until the other end closes, the timeout passes, or `limit` bytes have arrived.
    static func readAll(_ fd: Int32, limit: Int) -> [UInt8] {
        var result: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while result.count < limit {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                result += buffer[..<count]
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        return result
    }
}
