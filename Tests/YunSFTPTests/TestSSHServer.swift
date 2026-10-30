import Foundation
import XCTest

/// A throwaway OpenSSH server running as the current user on a free localhost port, with its own
/// host key and a fresh client key pair. Lets tests exercise the real SSH path without sudo.
final class TestSSHServer {
    let directory: URL
    let port: Int
    let clientKeyPath: String
    let clientKeyWithPassphrasePath: String
    private let process: Process

    static func start() throws -> TestSSHServer {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_sshd_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        func keygen(_ args: [String]) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen"); p.arguments = args
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
        }
        try keygen(["-q", "-t", "ed25519", "-N", "", "-f", dir.appendingPathComponent("hostkey").path])
        try keygen(["-q", "-t", "ed25519", "-N", "", "-f", dir.appendingPathComponent("client").path])
        try keygen(["-q", "-t", "ed25519", "-N", "correct horse", "-f", dir.appendingPathComponent("client_pw").path])
        try FileManager.default.copyItem(at: dir.appendingPathComponent("client.pub"), to: dir.appendingPathComponent("authorized_keys"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent("authorized_keys").path)

        let port = try freePort()
        let config = """
        Port \(port)
        ListenAddress 127.0.0.1
        HostKey \(dir.path)/hostkey
        PidFile \(dir.path)/sshd.pid
        UsePAM no
        StrictModes no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PubkeyAuthentication yes
        AuthorizedKeysFile \(dir.path)/authorized_keys
        Subsystem sftp /usr/libexec/sftp-server
        LogLevel QUIET
        """
        try config.write(to: dir.appendingPathComponent("sshd_config"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        process.arguments = ["-f", dir.appendingPathComponent("sshd_config").path, "-D", "-e"]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if portAccepts(port) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard portAccepts(port) else {
            process.terminate()
            throw XCTSkip("sshd did not start on port \(port)")
        }
        return TestSSHServer(directory: dir, port: port, process: process)
    }

    private init(directory: URL, port: Int, process: Process) {
        self.directory = directory
        self.port = port
        self.process = process
        self.clientKeyPath = directory.appendingPathComponent("client").path
        self.clientKeyWithPassphrasePath = directory.appendingPathComponent("client_pw").path
    }

    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = 0; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard bound == 0 else { throw NSError(domain: "TestSSHServer", code: 1) }
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    private static func portAccepts(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = in_port_t(port).bigEndian; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        return result == 0
    }
}
