import XCTest
@testable import yunsftp

@MainActor
final class TransferManagerTests: XCTestCase {
    var transferManager: TransferManager!

    override func setUp() async throws {
        try await super.setUp()
        transferManager = TransferManager()
    }

    func testAddTransferAndQueueState() {
        XCTAssertFalse(transferManager.hasActiveTransfers)
        XCTAssertEqual(transferManager.transfers.count, 0)

        let taskId = transferManager.addTransfer(
            fileName: "test_video.mp4",
            direction: .download,
            totalBytes: 10485760 // 10 MB
        )

        XCTAssertTrue(transferManager.hasActiveTransfers)
        XCTAssertEqual(transferManager.transfers.count, 1)
        XCTAssertTrue(transferManager.isVisible)

        guard let first = transferManager.transfers.first else {
            XCTFail("Transfer should be in queue")
            return
        }

        XCTAssertEqual(first.id, taskId)
        XCTAssertEqual(first.fileName, "test_video.mp4")
        XCTAssertEqual(first.direction, .download)
        XCTAssertEqual(first.state, .inProgress)
        XCTAssertEqual(first.progress, 0.0)
    }

    func testProgressUpdateAndOverallProgress() {
        let task1 = transferManager.addTransfer(fileName: "file1.txt", direction: .upload, totalBytes: 1000)
        let task2 = transferManager.addTransfer(fileName: "file2.txt", direction: .upload, totalBytes: 2000)

        transferManager.updateProgress(id: task1, progress: 0.5, bytesTransferred: 500, totalBytes: 1000, message: "Uploading...")
        transferManager.updateProgress(id: task2, progress: 0.25, bytesTransferred: 500, totalBytes: 2000, message: "Uploading...")

        let current1 = transferManager.transfers.first(where: { $0.id == task1 })
        XCTAssertEqual(current1?.progress, 0.5)
        XCTAssertEqual(current1?.state, .inProgress)
        XCTAssertEqual(current1?.bytesTransferred, 500)

        // Overall progress: (0.5 + 0.25) / 2 = 0.375
        XCTAssertEqual(transferManager.overallProgress, 0.375, accuracy: 0.001)
    }

    func testMarkCompletedAndCancel() {
        let task1 = transferManager.addTransfer(fileName: "file1.txt", direction: .localCopy, totalBytes: 500)
        let task2 = transferManager.addTransfer(fileName: "file2.txt", direction: .localMove, totalBytes: 500)

        transferManager.markCompleted(id: task1)
        let completedTask = transferManager.transfers.first(where: { $0.id == task1 })
        XCTAssertEqual(completedTask?.state, .completed)
        XCTAssertEqual(completedTask?.progress, 1.0)

        transferManager.cancelTransfer(id: task2)
        let cancelledTask = transferManager.transfers.first(where: { $0.id == task2 })
        XCTAssertEqual(cancelledTask?.state, .cancelled)

        XCTAssertFalse(transferManager.hasActiveTransfers)
    }

    func testClearCompleted() {
        let task1 = transferManager.addTransfer(fileName: "completed.txt", direction: .download, totalBytes: 100)
        transferManager.markCompleted(id: task1)

        transferManager.clearCompleted()
        XCTAssertEqual(transferManager.transfers.count, 0)
        XCTAssertFalse(transferManager.isVisible)
    }

    func testCompletedTransferDoesNotRevertTo98Percent() {
        let task = transferManager.addTransfer(fileName: "remote_video.mp4", direction: .download, totalBytes: 1000)
        transferManager.updateProgress(id: task, progress: 0.5, bytesTransferred: 500, totalBytes: 1000, message: "Downloading...")

        // Mark as completed
        transferManager.markCompleted(id: task)

        var current = transferManager.transfers.first(where: { $0.id == task })
        XCTAssertEqual(current?.state, .completed)
        XCTAssertEqual(current?.progress, 1.0)
        XCTAssertEqual(current?.statusMessage, "Completed")

        // Simulate a late/delayed monitor update attempting to set 98%
        transferManager.updateProgress(id: task, progress: 0.98, bytesTransferred: 980, totalBytes: 1000, message: "Downloading...")

        current = transferManager.transfers.first(where: { $0.id == task })
        XCTAssertEqual(current?.state, .completed, "Completed transfer must never be reverted back to inProgress")
        XCTAssertEqual(current?.progress, 1.0, "Completed transfer must remain at 100% progress")
        XCTAssertEqual(current?.statusMessage, "Completed")
    }

    func testFailedOrCancelledTransferDoesNotRevertToInProgress() {
        let task = transferManager.addTransfer(fileName: "failed_doc.pdf", direction: .download, totalBytes: 500)
        transferManager.markFailed(id: task, error: "Network error")

        // Attempt late update
        transferManager.updateProgress(id: task, progress: 0.8, bytesTransferred: 400, totalBytes: 500, message: "Downloading...")
        var current = transferManager.transfers.first(where: { $0.id == task })
        XCTAssertTrue(current?.state.isFailed == true)

        let cancelTask = transferManager.addTransfer(fileName: "cancelled.pdf", direction: .upload, totalBytes: 500)
        transferManager.cancelTransfer(id: cancelTask)
        transferManager.updateProgress(id: cancelTask, progress: 0.8, bytesTransferred: 400, totalBytes: 500, message: "Uploading...")
        current = transferManager.transfers.first(where: { $0.id == cancelTask })
        XCTAssertEqual(current?.state, .cancelled)
    }
}


extension TransferManagerTests {
    @MainActor
    func testHistoryIsCappedToTheNewestFinishedRows() {
        let tm = TransferManager()
        for i in 0..<(TransferManager.historyLimit + 5) {
            let id = tm.addTransfer(fileName: "f\(i)", direction: .localCopy, totalBytes: 1)
            tm.markCompleted(id: id)
        }
        XCTAssertEqual(tm.transfers.count, TransferManager.historyLimit + 1, "trim runs on add, so the newest row is kept on top of the cap")
        XCTAssertEqual(tm.transfers.first?.fileName, "f4")
    }
}

extension TransferManagerTests {
    @MainActor
    func testDismissHidesBannerWithoutTouchingHistoryAndOldRowsDoNotResurface() {
        let tm = TransferManager()
        let old = tm.addTransfer(fileName: "old.zip", direction: .download, totalBytes: 1)
        tm.markCompleted(id: old)
        tm.hideBanner()
        XCTAssertFalse(tm.isVisible)
        XCTAssertEqual(tm.transfers.count, 1, "Dismiss keeps history")

        // Removing an unrelated row while nothing is active must not bring the banner back.
        let gone = tm.addTransfer(fileName: "x", direction: .upload, totalBytes: 1)
        tm.markFailed(id: gone, error: "boom")
        tm.hideBanner()
        tm.remove(id: gone)
        XCTAssertFalse(tm.isVisible)
    }
}
