import XCTest
@testable import yunsftp

final class TransferCancellationTests: XCTestCase {

    func testTerminateAllStopsRunningChildProcess() async throws {
        let start = Date()
        let task = Task {
            try await SFTPService.shared.runProcess(executable: "/bin/sleep", arguments: ["30"], password: nil, isTransfer: true)
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThanOrEqual(ProcessRegistry.shared.terminateAll(), 1)
        do {
            _ = try await task.value
            XCTFail("terminated process should surface as an error")
        } catch {
            XCTAssertTrue(SFTPService.isCancellation(error))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testTerminateBatchOnlySignalsThatBatch() async throws {
        let a = UUID(), b = UUID()
        let taskA = Task { try await SFTPService.$currentBatch.withValue(a) {
            try await SFTPService.shared.runProcess(executable: "/bin/sleep", arguments: ["30"], password: nil, isTransfer: true) } }
        let taskB = Task { try await SFTPService.$currentBatch.withValue(b) {
            try await SFTPService.shared.runProcess(executable: "/bin/sleep", arguments: ["1"], password: nil, isTransfer: true) } }
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(ProcessRegistry.shared.terminate(batch: a), 1)
        do { _ = try await taskA.value; XCTFail("batch A must be cancelled") } catch { XCTAssertTrue(SFTPService.isCancellation(error)) }
        // Batch B was not touched and finishes normally.
        _ = try await taskB.value
    }

    func testRegistryForgetsUnregisteredProcesses() throws {
        let registry = ProcessRegistry()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep"); p.arguments = ["30"]
        registry.register(p, isTransfer: true, batch: nil)
        try p.run()
        XCTAssertEqual(registry.terminateAll(), 1)
        p.waitUntilExit()
        XCTAssertTrue(registry.consumeTerminated(p))
        registry.unregister(p)
        XCTAssertEqual(registry.terminateAll(), 0)
    }

    func testTerminateAllSkipsNonTransferAndExitedProcesses() throws {
        let registry = ProcessRegistry()
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/bin/sleep"); listing.arguments = ["30"]
        registry.register(listing, isTransfer: false)
        try listing.run()
        defer { listing.terminate() }

        let done = Process()
        done.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        registry.register(done, isTransfer: true)
        try done.run(); done.waitUntilExit()

        XCTAssertEqual(registry.terminateAll(), 0)
        XCTAssertFalse(registry.consumeTerminated(done))
        XCTAssertTrue(listing.isRunning)
    }

    func testTransferProcessDoesNotStartInsideCancelledTask() async throws {
        let task = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000)   // cancelled before this returns
            return try await SFTPService.shared.runProcess(executable: "/usr/bin/true", arguments: [], password: nil, isTransfer: true)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("must not run")
        } catch {
            // CancellationError from sleep or our cancellation code: either way nothing ran.
            XCTAssertTrue(error is CancellationError || SFTPService.isCancellation(error))
        }
    }

    @MainActor
    func testCancellingAnItemCancelsItsBatchAndKeepsFinalState() {
        let tm = TransferManager()
        var cancelledBatches: [UUID] = []
        tm.batchCancelHandler = { cancelledBatches.append($0) }
        let batch = UUID()
        let a = tm.addTransfer(fileName: "a", direction: .upload, totalBytes: 1, batchID: batch)
        let b = tm.addTransfer(fileName: "b", direction: .upload, totalBytes: 1, batchID: batch)
        tm.updateProgress(id: a, progress: 0.2, bytesTransferred: 0, totalBytes: 1, message: "")

        tm.cancelTransfer(id: a)
        XCTAssertEqual(cancelledBatches, [batch])
        tm.markBatchCancelled(batch)
        XCTAssertEqual(tm.transfers.map(\.state), [.cancelled, .cancelled])

        // Late results from killed work never flip the state back.
        tm.markCompleted(id: a)
        tm.markFailed(id: b, error: "exit 15")
        XCTAssertEqual(tm.transfers.map(\.state), [.cancelled, .cancelled])

        // Cancelling something already finished touches no batch.
        let c = tm.addTransfer(fileName: "c", direction: .download, totalBytes: 1, batchID: UUID())
        tm.markCompleted(id: c)
        tm.cancelTransfer(id: c)
        XCTAssertEqual(cancelledBatches.count, 1)
    }

    func testCancelledDownloadLeavesNoPartialFile() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_cancel_\(UUID().uuidString)")
        let remote = base.appendingPathComponent("remote"); let local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let big = remote.appendingPathComponent("big.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: big.path, contents: nil))
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 1 << 30)
        try handle.close()

        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: remote.path, authType: .sshKey)
        let batch = UUID()
        let task = Task { try await SFTPService.$currentBatch.withValue(batch) {
            try await SFTPService.shared.download(remotePath: big.path, to: local, connection: conn, password: nil) } }
        try await Task.sleep(nanoseconds: 150_000_000)
        ProcessRegistry.shared.terminate(batch: batch)

        do {
            _ = try await task.value
            throw XCTSkip("download finished before it could be cancelled on this machine")
        } catch let error where SFTPService.isCancellation(error) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("big.bin").path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: local.path).count, 0)
        }
    }
}
