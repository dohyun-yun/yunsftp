import XCTest
@testable import yunsftp

/// Runs only when YUNSFTP_TEST_SSH_PORT points at an sshd on 127.0.0.1 that accepts the user's key.
@MainActor
final class RealSSHReproTests: XCTestCase {
    func testDownloadAndUploadOverRealSSH() async throws {
        guard let portString = ProcessInfo.processInfo.environment["YUNSFTP_TEST_SSH_PORT"], let port = Int(portString) else { throw XCTSkip("no sshd") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("realssh_\(UUID().uuidString)")
        let remote = base.appendingPathComponent("remote"), local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "down".write(to: remote.appendingPathComponent("r.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: remote.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try "in dir".write(to: remote.appendingPathComponent("dir/inner.txt"), atomically: true, encoding: .utf8)

        let conn = RemoteConnection(name: "real", host: "127.0.0.1", port: port, username: NSUserName(), remotePath: remote.path, authType: .sshKey, keyFilePath: "~/.ssh/id_ed25519")
        let items = try await SFTPService.shared.listDirectory(path: remote.path, connection: conn, password: nil)
        XCTAssertEqual(Set(items.map(\.name)), ["r.txt", "dir"])

        let manager = TransferManager(); let coordinator = TransferCoordinator(manager: manager)
        let file = try XCTUnwrap(items.first { $0.name == "r.txt" }).toFileItem(connection: conn)
        let dir = try XCTUnwrap(items.first { $0.name == "dir" }).toFileItem(connection: conn)
        let batch = coordinator.start(TransferRequest(items: [file, dir], source: .remote(conn, password: nil, path: remote.path), destination: .local(local), mode: .copy))
        await coordinator.wait(for: batch)
        for row in manager.transfers { print("ROW", row.fileName, row.state, row.statusMessage) }
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("r.txt"), encoding: .utf8), "down")
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("dir/inner.txt"), encoding: .utf8), "in dir")

        try "up".write(to: local.appendingPathComponent("l.txt"), atomically: true, encoding: .utf8)
        let up = coordinator.start(TransferRequest(items: [FileItem(url: local.appendingPathComponent("l.txt"))], source: .local(local), destination: .remote(conn, password: nil, path: remote.path), mode: .copy))
        await coordinator.wait(for: up)
        for row in manager.transfers { print("ROW", row.fileName, row.state, row.statusMessage) }
        XCTAssertEqual(try String(contentsOf: remote.appendingPathComponent("l.txt"), encoding: .utf8), "up")
    }
}
