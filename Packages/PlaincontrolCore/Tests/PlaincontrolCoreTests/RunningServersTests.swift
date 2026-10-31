import Darwin
import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct RunningServersTests {
    let app = Project(path: "/work/app")
    let site = Project(path: "/work/site")

    func process(
        _ pid: Int32, name: String = "node", in folder: String?, parent: Int32 = 500, started: TimeInterval = 0
    ) -> ListeningProcess {
        ListeningProcess(
            pid: pid, parent: parent, group: pid, name: name, folder: folder, ports: [3000],
            started: Date(timeIntervalSince1970: started))
    }

    @Test func keepsOnlyTheProcessesInAProject() {
        let processes = [
            process(1, in: "/work/app"), process(2, name: "Spotify", in: "/"), process(3, in: "/work/app/web"),
            process(4, in: nil), process(5, in: "/work/apple"),
        ]
        let servers = RunningServers.servers(from: processes, in: [app, site])
        #expect(Set(servers.map(\.id)) == [1, 3])
        #expect(servers.allSatisfy { $0.project == app })
    }

    @Test func picksTheInnermostProject() {
        let web = Project(path: "/work/app/web")
        let servers = RunningServers.servers(from: [process(1, in: "/work/app/web/src")], in: [app, web])
        #expect(servers.map(\.project) == [web])
    }

    @Test func leavesOutTunnels() {
        let servers = RunningServers.servers(from: [process(1, name: "ssh", in: "/work/app")], in: [app])
        #expect(servers.isEmpty)
    }

    @Test func listsOrphanedServersFirstThenTheNewest() {
        let processes = [
            process(1, in: "/work/app", started: 10), process(2, in: "/work/site", started: 30),
            process(3, in: "/work/app", parent: 1, started: 0),
        ]
        let servers = RunningServers.servers(from: processes, in: [app, site])
        #expect(servers.map(\.id) == [3, 2, 1])
        #expect(servers.map(\.isOrphaned) == [true, false, false])
    }

    @Test func stopsTheTerminalJobButNeverAShellOrAClaudeCodeSession() {
        #expect(RunningServers.stopsGroup(80, ownGroup: 10, leadsSession: false, memberNames: ["pnpm", "node"]))
        #expect(!RunningServers.stopsGroup(80, ownGroup: 10, leadsSession: true, memberNames: ["zsh", "node"]))
        #expect(!RunningServers.stopsGroup(80, ownGroup: 10, leadsSession: false, memberNames: ["claude", "node"]))
        #expect(!RunningServers.stopsGroup(10, ownGroup: 10, leadsSession: false, memberNames: ["node"]))
        #expect(!RunningServers.stopsGroup(1, ownGroup: 10, leadsSession: false, memberNames: ["node"]))
    }

    @Test func findsAPortThisProcessListensOn() throws {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        try #require(socket >= 0)
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0)
        try #require(listen(socket, 1) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))

        let me = RunningServers.listeningProcesses().first { $0.pid == getpid() }
        #expect(me?.ports.contains(port) == true)
        #expect(me?.folder == FileManager.default.currentDirectoryPath)
        #expect(me?.parent == getppid())
    }
}
