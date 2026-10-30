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

extension SFTPConflictHandlingTests {
    func testRemoteExistsDistinguishesMissingFromPresent() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_exists_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("here.txt"), atomically: true, encoding: .utf8)
        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: dir.path, authType: .sshKey)

        let present = try await SFTPService.shared.remoteExists(dir.appendingPathComponent("here.txt").path, connection: conn, password: nil)
        let missing = try await SFTPService.shared.remoteExists(dir.appendingPathComponent("gone.txt").path, connection: conn, password: nil)
        XCTAssertTrue(present)
        XCTAssertFalse(missing)
    }
}

extension SFTPConflictHandlingTests {
    func testRemoteExistsHandlesNonUTF8ErrorOutputForKoreanNames() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_utf8_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: dir.path, authType: .sshKey)
        // sftp reports this missing path with mangled bytes; it must still read as "absent".
        let missing = try await SFTPService.shared.remoteExists(dir.appendingPathComponent("업로드  테스트   파일.txt").path, connection: conn, password: nil)
        XCTAssertFalse(missing)
    }
}

extension SFTPConflictHandlingTests {
    func testDownloadIsStagedInTempAndMovedIntoPlace() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_stage_\(UUID().uuidString)")
        let remote = base.appendingPathComponent("remote"), local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "x".write(to: remote.appendingPathComponent("s.txt"), atomically: true, encoding: .utf8)
        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: remote.path, authType: .sshKey)

        let planned = local.appendingPathComponent("s.txt")
        let staged = SFTPService.stagedURL(for: planned)
        XCTAssertTrue(staged.path.hasPrefix(FileManager.default.temporaryDirectory.path), "staging lives in the app temp folder")
        XCTAssertEqual(staged, SFTPService.stagedURL(for: planned), "deterministic so the progress monitor can watch it")
        XCTAssertNotEqual(staged.deletingLastPathComponent(), SFTPService.stagedURL(for: base.appendingPathComponent("elsewhere/s.txt")).deletingLastPathComponent())

        let url = try await SFTPService.shared.download(remotePath: remote.appendingPathComponent("s.txt").path, to: local, connection: conn, password: nil)
        XCTAssertEqual(url, planned)
        XCTAssertEqual(try String(contentsOf: planned, encoding: .utf8), "x")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path), "staging folder cleaned up")

        // A missing remote file leaves nothing behind anywhere.
        do {
            _ = try await SFTPService.shared.download(remotePath: remote.appendingPathComponent("missing.txt").path, to: local, connection: conn, password: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("missing.txt").path))
        }
    }

    func testLocalAccessDenialIsRecognised() {
        func err(_ s: String) -> Error { NSError(domain: "SFTPService", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
        XCTAssertTrue(SFTPService.isLocalAccessDenied(err("Couldn't change local directory to \"/Users/me/Downloads\": Operation not permitted")))
        XCTAssertTrue(SFTPService.isLocalAccessDenied(err("Couldn't open local file \"/Users/me/Desktop/a.txt\" for reading: Permission denied")))
        XCTAssertFalse(SFTPService.isLocalAccessDenied(err("remote open(\"/srv/a.txt\"): Permission denied")))
        XCTAssertFalse(SFTPService.isLocalAccessDenied(err("Connection timed out")))
    }
}
