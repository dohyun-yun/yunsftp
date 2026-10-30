import XCTest
@testable import yunsftp

final class SFTPConflictHandlingTests: XCTestCase {

    func testUniqueNameSuffixing() {
        XCTAssertEqual(SFTPService.uniqueName("a.txt", existing: []), "a.txt")
        XCTAssertEqual(SFTPService.uniqueName("a.txt", existing: ["a.txt"]), "a 2.txt")
        XCTAssertEqual(SFTPService.uniqueName("a.txt", existing: ["a.txt", "a 2.txt"]), "a 3.txt")
        XCTAssertEqual(SFTPService.uniqueName("dir", existing: ["dir"]), "dir 2")
    }

    func testUploadAndDownloadKeepBothByDefault() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else {
            throw XCTSkip("sftp-server binary not found")
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_conflict_\(UUID().uuidString)")
        let remoteRoot = base.appendingPathComponent("remote")
        let localDir = base.appendingPathComponent("local")
        let downloadDir = base.appendingPathComponent("download")
        for d in [remoteRoot, localDir, downloadDir] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: base) }

        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: remoteRoot.path, authType: .sshKey)
        let file = localDir.appendingPathComponent("dup.txt")
        try "v1".write(to: file, atomically: true, encoding: .utf8)

        // Upload twice: second upload must not clobber the first
        try await SFTPService.shared.upload(localURL: file, to: remoteRoot.path, connection: conn, password: nil)
        try "v2".write(to: file, atomically: true, encoding: .utf8)
        try await SFTPService.shared.upload(localURL: file, to: remoteRoot.path, connection: conn, password: nil)
        let remoteNames = Set(try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil).map { $0.name })
        XCTAssertTrue(remoteNames.isSuperset(of: ["dup.txt", "dup 2.txt"]), "got \(remoteNames)")
        XCTAssertEqual(try String(contentsOf: remoteRoot.appendingPathComponent("dup.txt"), encoding: .utf8), "v1")

        // Explicit overwrite replaces in place
        try "v3".write(to: file, atomically: true, encoding: .utf8)
        try await SFTPService.shared.upload(localURL: file, to: remoteRoot.path, connection: conn, password: nil, overwrite: true)
        XCTAssertEqual(try String(contentsOf: remoteRoot.appendingPathComponent("dup.txt"), encoding: .utf8), "v3")

        // Download twice: second download gets a suffix and is returned as such
        let remotePath = remoteRoot.appendingPathComponent("dup.txt").path
        let first = try await SFTPService.shared.download(remotePath: remotePath, to: downloadDir, connection: conn, password: nil)
        let second = try await SFTPService.shared.download(remotePath: remotePath, to: downloadDir, connection: conn, password: nil)
        XCTAssertEqual(first.lastPathComponent, "dup.txt")
        XCTAssertEqual(second.lastPathComponent, "dup 2.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
}
