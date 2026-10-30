import XCTest
@testable import yunsftp

final class TransferCancellationTests: XCTestCase {

    func testTerminateAllStopsRunningChildProcess() async throws {
        let start = Date()
        let task = Task {
            try await SFTPService.shared.runProcess(executable: "/bin/sleep", arguments: ["30"], password: nil)
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
        registry.register(p)
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

        tm.cancelTransfer(id: id)
        XCTAssertEqual(tm.transfers.first?.state, .cancelled)
        XCTAssertTrue(tm.consumeCancelRequest(), "batch loop must see the cancel once")
        XCTAssertFalse(tm.consumeCancelRequest(), "flag is consumed")

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
        XCTAssertFalse(tm.consumeCancelRequest())
    }
}
