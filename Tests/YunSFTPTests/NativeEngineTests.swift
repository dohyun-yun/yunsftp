import XCTest
@testable import yunsftp

/// End-to-end tests of the Citadel-based engine against a real sshd (see TestSSHServer).
final class NativeEngineTests: XCTestCase {
    private var server: TestSSHServer!
    private var base: URL!
    private var remote: URL!
    private var local: URL!
    private var savedKnownHosts: URL!
    private var savedOverride: TransferEngine?

    override func setUpWithError() throws {
        server = try TestSSHServer.start()
        base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_native_\(UUID().uuidString)")
        remote = base.appendingPathComponent("remote"); local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        savedKnownHosts = NativeSFTPEngine.knownHostsURL
        NativeSFTPEngine.knownHostsURL = base.appendingPathComponent("known_hosts")
        savedOverride = SFTPService.engineOverride
        SFTPService.engineOverride = .native
    }

    override func tearDown() async throws {
        await NativeSFTPEngine.shared.disconnectAll()
        await SFTPService.shared.forgetFallbacks()
        NativeSFTPEngine.knownHostsURL = savedKnownHosts
        SFTPService.engineOverride = savedOverride
        server?.stop()
        if let base { try? FileManager.default.removeItem(at: base) }
    }

    private func connection(keyPath: String? = nil) -> RemoteConnection {
        RemoteConnection(name: "native", host: "127.0.0.1", port: server.port, username: NSUserName(), remotePath: remote.path,
                         authType: .sshKey, keyFilePath: keyPath ?? server.clientKeyPath)
    }

    func testListUploadDownloadRenameRemoveChmodThroughSFTPService() async throws {
        let conn = connection()
        try "r".write(to: remote.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: remote.appendingPathComponent("한글 폴더"), withIntermediateDirectories: true)

        // list: no `ls` parsing, attributes straight from the protocol
        let items = try await SFTPService.shared.listDirectory(path: remote.path, connection: conn, password: nil)
        XCTAssertEqual(Set(items.map(\.name)), ["existing.txt", "한글 폴더"])
        XCTAssertTrue(items.first { $0.name == "한글 폴더" }!.isDirectory)
        XCTAssertEqual(items.first { $0.name == "existing.txt" }!.size, 1)
        let used = await SFTPService.shared.lastEngineUsed[conn.id]
        XCTAssertEqual(used, .native)

        // upload with byte-level progress
        let big = local.appendingPathComponent("big.bin")
        try Data((0..<(1_500_000)).map { UInt8(truncatingIfNeeded: $0) }).write(to: big)
        let uploadTicks = Ticks()
        try await SFTPService.shared.upload(localURL: big, to: remote.path, connection: conn, password: nil) { uploadTicks.record($0) }
        XCTAssertEqual(try Data(contentsOf: remote.appendingPathComponent("big.bin")).count, 1_500_000)
        XCTAssertGreaterThanOrEqual(uploadTicks.values.count, 3)
        XCTAssertEqual(uploadTicks.values.last, 1_500_000)
        XCTAssertEqual(uploadTicks.values, uploadTicks.values.sorted())

        // keep-both on conflict still works through the native exists() probe
        try await SFTPService.shared.upload(localURL: big, to: remote.path, connection: conn, password: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: remote.appendingPathComponent("big 2.bin").path))

        // download with progress, staged and moved into place
        let downloadTicks = Ticks()
        let url = try await SFTPService.shared.download(remotePath: remote.appendingPathComponent("big.bin").path, to: local.appendingPathComponent("dl"), connection: conn, password: nil) { downloadTicks.record($0) }
        XCTAssertEqual(url.lastPathComponent, "big.bin")
        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: big))
        XCTAssertEqual(downloadTicks.values.last, 1_500_000)

        // directory tree round trip
        let tree = local.appendingPathComponent("tree")
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "a".write(to: tree.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: tree.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
        try await SFTPService.shared.upload(localURL: tree, to: remote.path, connection: conn, password: nil)
        XCTAssertEqual(try String(contentsOf: remote.appendingPathComponent("tree/sub/b.txt"), encoding: .utf8), "b")
        _ = try await SFTPService.shared.download(remotePath: remote.appendingPathComponent("tree").path, to: local.appendingPathComponent("dl"), connection: conn, password: nil)
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("dl/tree/sub/b.txt"), encoding: .utf8), "b")

        // mkdir / rename / chmod / remove
        try await SFTPService.shared.createDirectory(remotePath: remote.appendingPathComponent("made").path, connection: conn, password: nil)
        try await SFTPService.shared.rename(remotePath: remote.appendingPathComponent("made").path, to: remote.appendingPathComponent("renamed").path, connection: conn, password: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: remote.appendingPathComponent("renamed").path))
        try await SFTPService.shared.chmod(remotePath: remote.appendingPathComponent("existing.txt").path, mode: "600", connection: conn, password: nil)
        let perms = (try FileManager.default.attributesOfItem(atPath: remote.appendingPathComponent("existing.txt").path))[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        try await SFTPService.shared.remove(remotePath: remote.appendingPathComponent("tree").path, isDirectory: true, connection: conn, password: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: remote.appendingPathComponent("tree").path))
        let treeExists = try await SFTPService.shared.remoteExists(remote.appendingPathComponent("tree").path, connection: conn, password: nil)
        let renamedExists = try await SFTPService.shared.remoteExists(remote.appendingPathComponent("renamed").path, connection: conn, password: nil)
        XCTAssertFalse(treeExists)
        XCTAssertTrue(renamedExists)
    }

    func testHostKeyIsRememberedThenEnforced() async throws {
        let conn = connection()
        let knownHosts = NativeSFTPEngine.knownHostsURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: knownHosts.path))
        _ = try await SFTPService.shared.listDirectory(path: remote.path, connection: conn, password: nil)
        let saved = try String(contentsOf: knownHosts, encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("[127.0.0.1]:\(server.port) ssh-ed25519 "), saved)

        // Tamper: same host, different key -> connection refused with the known_hosts hint.
        var fields = saved.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        let otherKey = try String(contentsOfFile: server.clientKeyPath + ".pub", encoding: .utf8).split(separator: " ").map(String.init)[1]
        fields[2] = otherKey
        try (fields.joined(separator: " ") + "\n").write(to: knownHosts, atomically: true, encoding: .utf8)
        await NativeSFTPEngine.shared.disconnectAll()
        var fresh = conn; fresh.id = UUID()
        do {
            _ = try await SFTPService.shared.listDirectory(path: remote.path, connection: fresh, password: nil)
            XCTFail("mismatching host key must be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("known_hosts"), error.localizedDescription)
        }
    }

    func testPassphraseProtectedKeyFallsBackToOpenSSH() async throws {
        let conn = connection(keyPath: server.clientKeyWithPassphrasePath)
        // The native engine cannot decrypt the key; OpenSSH (no agent here) fails too, but the
        // routing must have switched engines rather than surfacing the native parse error.
        _ = try? await SFTPService.shared.listDirectory(path: remote.path, connection: conn, password: nil)
        let used = await SFTPService.shared.lastEngineUsed[conn.id]
        XCTAssertEqual(used, .openSSH)
    }

    func testLegacyAlgorithmConnectionsUseOpenSSH() async throws {
        var conn = connection(); conn.allowLegacyAlgorithms = true
        let useNative = await SFTPService.shared.useNative(for: conn)
        XCTAssertFalse(useNative)
    }

    final class Ticks: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Int64] = []
        var values: [Int64] { lock.lock(); defer { lock.unlock() }; return _values }
        func record(_ v: Int64) { lock.lock(); _values.append(v); lock.unlock() }
    }
}
