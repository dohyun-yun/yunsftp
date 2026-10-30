import XCTest
@testable import yunsftp

@MainActor
final class RemoteEditAndUndoTests: XCTestCase {

    func testExternalEditUploadsAfterSaveSettles() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_edit_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let remoteFile = base.appendingPathComponent("notes.txt")
        try "v1".write(to: remoteFile, atomically: true, encoding: .utf8)
        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: base.path, authType: .sshKey)
        let item = FileItem(virtualURL: SFTPService.sftpURL(host: conn.host, port: conn.port, path: remoteFile.path), name: "notes.txt", isDirectory: false, size: 2, modificationDate: Date(), permissions: "")

        let service = RemoteEditService(pollInterval: 3600, coordinator: TransferCoordinator(manager: TransferManager()))
        let session = try await service.edit(item: item, connection: conn, password: nil, open: false)
        XCTAssertEqual(try String(contentsOf: session.localURL, encoding: .utf8), "v1")

        // Editor saves: first tick sees the change, second tick (stable) uploads.
        try await Task.sleep(nanoseconds: 1_100_000_000)   // mtime resolution
        try "v2 edited".write(to: session.localURL, atomically: true, encoding: .utf8)
        await service.tick()
        XCTAssertEqual(try String(contentsOf: remoteFile, encoding: .utf8), "v1", "not uploaded while the write may still be in flight")
        await service.tick()
        XCTAssertEqual(try String(contentsOf: remoteFile, encoding: .utf8), "v2 edited")
        XCTAssertEqual(service.sessions.first?.uploadCount, 1)

        service.stop(sessionID: session.id)
        XCTAssertTrue(service.sessions.isEmpty)
    }

    func testMoveAndTrashReturnWhatUndoNeeds() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_undo_\(UUID().uuidString)")
        let dst = base.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let f = base.appendingPathComponent("f.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        try "old".write(to: dst.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)

        let moved = try await FileSystemService.shared.move(urls: [f], to: dst)
        XCTAssertEqual(moved.map(\.lastPathComponent), ["f 2.txt"])

        let pairs = try await FileSystemService.shared.moveToTrash(urls: moved)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved[0].path))
        try await FileSystemService.shared.restoreFromTrash(pairs[0])
        XCTAssertEqual(try String(contentsOf: moved[0], encoding: .utf8), "x")
    }

    func testUndoManagerRunsTheRegisteredInverse() async throws {
        let um = UndoManager()
        let done = expectation(description: "inverse ran")
        LocalUndo.register(um, actionName: "Rename") { done.fulfill() }
        XCTAssertTrue(um.canUndo)
        XCTAssertEqual(um.undoActionName, "Rename")
        um.undo()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertFalse(um.canUndo)
        XCTAssertFalse(um.canRedo, "redo is deliberately not offered")
    }
}
