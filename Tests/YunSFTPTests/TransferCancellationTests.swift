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
            // expected: non-zero exit after SIGTERM
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "sleep 30 must not run to completion")
    }

    func testRegistryForgetsUnregisteredProcesses() throws {
        // Isolated instance: other tests may legitimately have children running in the shared one.
        let registry = ProcessRegistry()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        registry.register(p, isTransfer: true)
        try p.run()
        XCTAssertEqual(registry.terminateAll(), 1)
        p.waitUntilExit()
        XCTAssertFalse(p.isRunning)
        registry.unregister(p)
        XCTAssertEqual(registry.terminateAll(), 0)
    }

    @MainActor
    func testCancellingActiveTransferRaisesBatchCancelFlag() {
        let tm = TransferManager()
        let id = tm.addTransfer(fileName: "big.iso", direction: .upload, totalBytes: 100)
        tm.updateProgress(id: id, progress: 0.2, bytesTransferred: 20, totalBytes: 100, message: "Uploading")

        let batchStart = Date().addingTimeInterval(-1)
        tm.cancelTransfer(id: id)
        XCTAssertEqual(tm.transfers.first?.state, .cancelled)
        XCTAssertFalse(tm.consumeCancelRequest(since: Date().addingTimeInterval(60)), "a batch started after the cancel ignores it")
        XCTAssertTrue(tm.consumeCancelRequest(since: batchStart), "the running batch sees the cancel once")
        XCTAssertFalse(tm.consumeCancelRequest(since: batchStart), "flag is consumed")

        // A late success from the killed operation must not flip the state back.
        tm.markCompleted(id: id)
        XCTAssertEqual(tm.transfers.first?.state, .cancelled)

        // The terminated process reports an error afterwards; cancelled wins.
        tm.markFailed(id: id, error: "exit 15")
        XCTAssertEqual(tm.transfers.first?.state, .cancelled)
    }

    @MainActor
    func testCancellingFinishedTransferDoesNotAffectNextBatch() {
        let tm = TransferManager()
        let id = tm.addTransfer(fileName: "done.txt", direction: .download, totalBytes: 1)
        tm.markCompleted(id: id)
        tm.cancelTransfer(id: id)
        XCTAssertFalse(tm.consumeCancelRequest(since: .distantPast))
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

        XCTAssertEqual(registry.terminateAll(), 0, "listings and already-exited children are never signalled")
        XCTAssertFalse(registry.consumeTerminated(done), "a finished transfer must not be reported as cancelled")
        XCTAssertTrue(listing.isRunning)
    }

    @MainActor
    func testCancellingActiveButStillPreparingDownloadStopsTheBatch() {
        let tm = TransferManager()
        let id = tm.addTransfer(fileName: "big.iso", direction: .download, totalBytes: 100) // stays .queued until bytes land
        tm.cancelTransfer(id: id)
        XCTAssertTrue(tm.consumeCancelRequest(since: .distantPast))
    }

    @MainActor
    func testCancellingQueuedTransferDoesNotStopTheBatch() {
        let tm = TransferManager()
        let running = tm.addTransfer(fileName: "a", direction: .upload, totalBytes: 1)
        tm.updateProgress(id: running, progress: 0.5, bytesTransferred: 1, totalBytes: 2, message: "")
        let queued = tm.addTransfer(fileName: "b", direction: .upload, totalBytes: 1)
        tm.cancelTransfer(id: queued)
        XCTAssertEqual(tm.transfers.last?.state, .cancelled)
        XCTAssertEqual(tm.transfers.first?.state, .inProgress)
        XCTAssertFalse(tm.consumeCancelRequest(since: .distantPast))
    }

    func testCancelledDownloadLeavesNoPartialFile() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_cancel_\(UUID().uuidString)")
        let remote = base.appendingPathComponent("remote"); let local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // 1 GiB sparse file: cheap to create, long enough to interrupt.
        let big = remote.appendingPathComponent("big.bin")
        let fh = FileManager.default.createFile(atPath: big.path, contents: nil)
        XCTAssertTrue(fh)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 1 << 30)
        try handle.close()

        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: remote.path, authType: .sshKey)
        let task = Task { try await SFTPService.shared.download(remotePath: big.path, to: local, connection: conn, password: nil) }
        try await Task.sleep(nanoseconds: 150_000_000)
        ProcessRegistry.shared.terminateAll()

        do {
            _ = try await task.value
            throw XCTSkip("download finished before it could be cancelled on this machine")
        } catch let error where SFTPService.isCancellation(error) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("big.bin").path), "partial file must be removed")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: local.path).count, 0)
        }
    }
}
