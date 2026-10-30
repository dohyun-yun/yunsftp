import XCTest
@testable import yunsftp

@MainActor
final class TransferCoordinatorTests: XCTestCase {

    private var base: URL!
    private var remote: URL!
    private var local: URL!
    private var conn: RemoteConnection!
    private var manager: TransferManager!
    private var coordinator: TransferCoordinator!

    override func setUp() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_coord_\(UUID().uuidString)")
        remote = base.appendingPathComponent("remote"); local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: remote.path, authType: .sshKey)
        manager = TransferManager()
        coordinator = TransferCoordinator(manager: manager)
    }

    override func tearDown() async throws {
        if let base { try? FileManager.default.removeItem(at: base) }
    }

    private func write(_ text: String, _ url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private func run(_ request: TransferRequest) async {
        let id = coordinator.start(request)
        await coordinator.wait(for: id)
    }

    func testLocalCopyAsksOnceWhenApplyToAllAndKeepsBoth() async throws {
        let src = base.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try write("new1", src.appendingPathComponent("a.txt")); try write("new2", src.appendingPathComponent("b.txt"))
        try write("old1", local.appendingPathComponent("a.txt")); try write("old2", local.appendingPathComponent("b.txt"))
        var asked = 0
        coordinator.conflictResolver = { _, _ in asked += 1; return ConflictDecision(.keepBoth, applyToAll: true) }

        await run(TransferRequest(items: [FileItem(url: src.appendingPathComponent("a.txt")), FileItem(url: src.appendingPathComponent("b.txt"))],
                                  source: .local(src), destination: .local(local), mode: .copy))
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(try read(local.appendingPathComponent("a.txt")), "old1")
        XCTAssertEqual(try read(local.appendingPathComponent("a 2.txt")), "new1")
        XCTAssertEqual(try read(local.appendingPathComponent("b 2.txt")), "new2")
        XCTAssertEqual(manager.transfers.map(\.state), [.completed, .completed])
    }

    func testUploadReplaceAndSkip() async throws {
        let src = base.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try write("fresh", src.appendingPathComponent("r.txt")); try write("fresh", src.appendingPathComponent("s.txt"))
        try write("stale", remote.appendingPathComponent("r.txt")); try write("stale", remote.appendingPathComponent("s.txt"))
        var calls: [String] = []
        coordinator.conflictResolver = { name, _ in
            calls.append(name)
            return ConflictDecision(name == "r.txt" ? .replace : .skip)
        }
        await run(TransferRequest(items: [FileItem(url: src.appendingPathComponent("r.txt")), FileItem(url: src.appendingPathComponent("s.txt"))],
                                  source: .local(src), destination: .remote(conn, password: nil, path: remote.path), mode: .copy))
        XCTAssertEqual(calls, ["r.txt", "s.txt"])
        XCTAssertEqual(try read(remote.appendingPathComponent("r.txt")), "fresh")
        XCTAssertEqual(try read(remote.appendingPathComponent("s.txt")), "stale")
        XCTAssertEqual(manager.transfers[0].state, .completed)
        XCTAssertEqual(manager.transfers[1].state, .cancelled)
        XCTAssertEqual(manager.transfers[1].statusMessage, "Skipped")
    }

    func testRemoteToLocalMoveRemovesSource() async throws {
        try write("payload", remote.appendingPathComponent("m.txt"))
        let item = FileItem(virtualURL: SFTPService.sftpURL(host: conn.host, port: conn.port, path: remote.appendingPathComponent("m.txt").path),
                            name: "m.txt", isDirectory: false, size: 7, modificationDate: Date(), permissions: "rw-r--r--")
        await run(TransferRequest(items: [item], source: .remote(conn, password: nil, path: remote.path), destination: .local(local), mode: .move))
        XCTAssertEqual(try read(local.appendingPathComponent("m.txt")), "payload")
        XCTAssertFalse(FileManager.default.fileExists(atPath: remote.appendingPathComponent("m.txt").path))
        XCTAssertEqual(manager.transfers.first?.state, .completed)
    }

    func testConflictCancelStopsTheBatch() async throws {
        let src = base.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try write("x", src.appendingPathComponent("c1.txt")); try write("y", src.appendingPathComponent("c2.txt"))
        try write("old", local.appendingPathComponent("c1.txt"))
        coordinator.conflictResolver = { _, _ in ConflictDecision(.cancel) }
        await run(TransferRequest(items: [FileItem(url: src.appendingPathComponent("c1.txt")), FileItem(url: src.appendingPathComponent("c2.txt"))],
                                  source: .local(src), destination: .local(local), mode: .copy))
        XCTAssertEqual(try read(local.appendingPathComponent("c1.txt")), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("c2.txt").path), "nothing after Cancel runs")
        XCTAssertEqual(manager.transfers.count, 1)
        XCTAssertTrue(coordinator.activeBatchIDs.isEmpty)
    }

    func testCancellingBatchStopsRemainingItemsAndLeavesOtherBatchAlone() async throws {
        // Batch A: a big download we cancel. Batch B: a small copy that must still complete.
        let big = remote.appendingPathComponent("big.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: big.path, contents: nil))
        let h = try FileHandle(forWritingTo: big); try h.truncate(atOffset: 1 << 30); try h.close()
        try write("tail", remote.appendingPathComponent("after.txt"))
        let bigItem = FileItem(virtualURL: SFTPService.sftpURL(host: conn.host, port: conn.port, path: big.path), name: "big.bin", isDirectory: false, size: 1 << 30, modificationDate: Date(), permissions: "")
        let afterItem = FileItem(virtualURL: SFTPService.sftpURL(host: conn.host, port: conn.port, path: remote.appendingPathComponent("after.txt").path), name: "after.txt", isDirectory: false, size: 4, modificationDate: Date(), permissions: "")
        let a = coordinator.start(TransferRequest(items: [bigItem, afterItem], source: .remote(conn, password: nil, path: remote.path), destination: .local(local), mode: .copy))

        let src = base.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try write("b", src.appendingPathComponent("other.txt"))
        let b = coordinator.start(TransferRequest(items: [FileItem(url: src.appendingPathComponent("other.txt"))], source: .local(src), destination: .local(local), mode: .copy))

        try await Task.sleep(nanoseconds: 200_000_000)
        guard let firstItem = manager.transfers.first(where: { $0.batchID == a }), firstItem.state == .inProgress else {
            throw XCTSkip("download finished before it could be cancelled on this machine")
        }
        manager.cancelTransfer(id: firstItem.id)      // what the status bar X does
        await coordinator.wait(for: a)
        await coordinator.wait(for: b)

        let aStates = manager.transfers.filter { $0.batchID == a }.map(\.state)
        XCTAssertEqual(aStates.count, 1, "second item of the cancelled batch never starts")
        XCTAssertEqual(aStates.first, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("after.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("big.bin").path), "partial file removed")
        XCTAssertEqual(manager.transfers.first { $0.batchID == b }?.state, .completed)
        XCTAssertEqual(try read(local.appendingPathComponent("other.txt")), "b")
    }

    func testDirectionDerivedFromEndpoints() {
        let l = TransferLocation.local(local), r = TransferLocation.remote(conn, password: nil, path: "/")
        XCTAssertEqual(TransferRequest(items: [], source: l, destination: l, mode: .copy).direction, .localCopy)
        XCTAssertEqual(TransferRequest(items: [], source: l, destination: l, mode: .move).direction, .localMove)
        XCTAssertEqual(TransferRequest(items: [], source: r, destination: l, mode: .copy).direction, .download)
        XCTAssertEqual(TransferRequest(items: [], source: l, destination: r, mode: .copy).direction, .upload)
        XCTAssertEqual(TransferRequest(items: [], source: r, destination: r, mode: .move).direction, .remoteCopy)
    }
}

extension TransferCoordinatorTests {
    func testRetryRerunsAFailedRowAfterTheCauseIsFixed() async throws {
        let src = base.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try write("v", src.appendingPathComponent("r.txt"))
        let missingDir = local.appendingPathComponent("not-yet")
        await run(TransferRequest(items: [FileItem(url: src.appendingPathComponent("r.txt"))], source: .local(src), destination: .local(missingDir), mode: .copy))
        let failed = try XCTUnwrap(manager.transfers.first)
        XCTAssertTrue(failed.state.isFailed)
        XCTAssertTrue(coordinator.canRetry(taskID: failed.id))

        try FileManager.default.createDirectory(at: missingDir, withIntermediateDirectories: true)
        let batch = try XCTUnwrap(coordinator.retry(taskID: failed.id))
        await coordinator.wait(for: batch)
        XCTAssertEqual(manager.transfers.count, 1, "the failed row is replaced by the retried one")
        XCTAssertEqual(manager.transfers.first?.state, .completed)
        XCTAssertEqual(try read(missingDir.appendingPathComponent("r.txt")), "v")
        XCTAssertNil(coordinator.retry(taskID: manager.transfers[0].id), "completed rows are not retryable")
    }

    func testFinishedRowsStayForHistoryUntilCleared() async throws {
        let src = base.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try write("v", src.appendingPathComponent("h.txt"))
        await run(TransferRequest(items: [FileItem(url: src.appendingPathComponent("h.txt"))], source: .local(src), destination: .local(local), mode: .copy))
        try await Task.sleep(nanoseconds: 2_300_000_000)   // past the banner auto-hide
        XCTAssertFalse(manager.isVisible)
        XCTAssertEqual(manager.transfers.count, 1)
        manager.clearCompleted()
        XCTAssertTrue(manager.transfers.isEmpty)
    }
}

extension TransferCoordinatorTests {
    func testReplaceOntoItselfFailsWithoutDeletingTheSourceEvenThroughSymlinks() async throws {
        let f = local.appendingPathComponent("same.txt")
        try write("keep me", f)
        let link = base.appendingPathComponent("local-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: local)
        coordinator.conflictResolver = { _, _ in ConflictDecision(.replace) }
        await run(TransferRequest(items: [FileItem(url: f)], source: .local(local), destination: .local(link), mode: .copy))
        XCTAssertEqual(try read(f), "keep me")
        XCTAssertTrue(manager.transfers.first?.state.isFailed ?? false)

        // Keep Both in the same folder is the normal "paste a copy" and must still work.
        coordinator.conflictResolver = { _, _ in ConflictDecision(.keepBoth) }
        await run(TransferRequest(items: [FileItem(url: f)], source: .local(local), destination: .local(local), mode: .copy))
        XCTAssertEqual(try read(local.appendingPathComponent("same 2.txt")), "keep me")

        // Remote → same remote folder, same connection, move with replace: nothing is removed.
        try write("remote keep", remote.appendingPathComponent("r.txt"))
        let item = FileItem(virtualURL: SFTPService.sftpURL(host: conn.host, port: conn.port, path: remote.appendingPathComponent("r.txt").path), name: "r.txt", isDirectory: false, size: 1, modificationDate: Date(), permissions: "")
        var duplicateConn = conn!; duplicateConn.id = UUID()   // same server through another saved connection
        await run(TransferRequest(items: [item], source: .remote(conn, password: nil, path: remote.path), destination: .remote(duplicateConn, password: nil, path: remote.path), mode: .move))
        XCTAssertEqual(try read(remote.appendingPathComponent("r.txt")), "remote keep")
    }

    func testRetryDataIsDroppedWhenRowsAreCleared() async throws {
        let src = base.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try write("v", src.appendingPathComponent("p.txt"))
        await run(TransferRequest(items: [FileItem(url: src.appendingPathComponent("p.txt"))], source: .local(src), destination: .local(local.appendingPathComponent("missing")), mode: .copy))
        let id = try XCTUnwrap(manager.transfers.first?.id)
        XCTAssertTrue(coordinator.canRetry(taskID: id))
        manager.clearCompleted()
        XCTAssertFalse(coordinator.canRetry(taskID: id))
    }
}
