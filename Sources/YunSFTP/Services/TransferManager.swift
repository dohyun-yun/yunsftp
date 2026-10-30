import Foundation
import SwiftUI
import Combine

public enum TransferDirection: String, Sendable {
    case download = "Download"
    case upload = "Upload"
    case localCopy = "Local Copy"
    case localMove = "Local Move"
    case remoteCopy = "Remote Copy"

    public var systemImage: String {
        switch self {
        case .download: return "arrow.down.circle.fill"
        case .upload: return "arrow.up.circle.fill"
        case .localCopy: return "doc.on.doc.fill"
        case .localMove: return "arrow.right.doc.on.clipboard"
        case .remoteCopy: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}

public enum TransferState: Equatable, Sendable {
    case queued
    case inProgress
    case completed
    case failed(String)
    case cancelled

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

public struct TransferTaskItem: Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let direction: TransferDirection
    /// Batch this item belongs to; cancelling the item cancels the batch.
    public var batchID: UUID? = nil
    public var state: TransferState
    public var progress: Double // 0.0 ... 1.0
    public var bytesTransferred: Int64
    public var totalBytes: Int64
    public var statusMessage: String

    public init(
        id: UUID = UUID(),
        fileName: String,
        direction: TransferDirection,
        state: TransferState = .queued,
        progress: Double = 0.0,
        bytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        statusMessage: String = "Queued..."
    ) {
        self.id = id
        self.fileName = fileName
        self.direction = direction
        self.state = state
        self.progress = progress
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.statusMessage = statusMessage
    }
}

@MainActor
public class TransferManager: ObservableObject {
    public static let shared = TransferManager()

    @Published public var transfers: [TransferTaskItem] = []
    @Published public var currentTransfer: TransferTaskItem? = nil
    @Published public var isVisible: Bool = false

    /// Installed by `TransferCoordinator`; cancelling an item cancels its whole batch.
    public var batchCancelHandler: ((UUID) -> Void)?

    public init() {}

    public var hasActiveTransfers: Bool {
        transfers.contains { $0.state == .inProgress || $0.state == .queued }
    }

    public var overallProgress: Double {
        let active = transfers.filter { $0.state == .inProgress || $0.state == .queued }
        guard !active.isEmpty else { return 1.0 }
        let total = active.reduce(0.0) { $0 + $1.progress }
        return total / Double(active.count)
    }

    public func addTransfer(fileName: String, direction: TransferDirection, totalBytes: Int64 = 0, batchID: UUID? = nil) -> UUID {
        // Batches add items one at a time right before working on them, so an item is
        // in progress from the moment it exists (the cancel button must be able to act on it).
        var item = TransferTaskItem(
            fileName: fileName,
            direction: direction,
            state: .inProgress,
            progress: 0.0,
            bytesTransferred: 0,
            totalBytes: totalBytes,
            statusMessage: "Preparing..."
        )
        item.batchID = batchID
        transfers.append(item)
        trimHistory()
        currentTransfer = item
        isVisible = true
        return item.id
    }

    public func updateProgress(id: UUID, progress: Double, bytesTransferred: Int64, totalBytes: Int64, message: String) {
        if let idx = transfers.firstIndex(where: { $0.id == id }) {
            // Do not overwrite completed, failed, or cancelled transfers
            guard transfers[idx].state != .completed && transfers[idx].state != .cancelled && !transfers[idx].state.isFailed else {
                return
            }
            transfers[idx].state = .inProgress
            transfers[idx].progress = min(1.0, max(0.0, progress))
            transfers[idx].bytesTransferred = bytesTransferred
            if totalBytes > 0 {
                transfers[idx].totalBytes = totalBytes
            }
            transfers[idx].statusMessage = message

            currentTransfer = transfers[idx]
            isVisible = true
        }
    }

    public func markCompleted(id: UUID) {
        if let idx = transfers.firstIndex(where: { $0.id == id }) {
            guard transfers[idx].state != .cancelled else { updateCurrentTransfer(); return }
            transfers[idx].state = .completed
            transfers[idx].progress = 1.0
            if transfers[idx].totalBytes > 0 {
                transfers[idx].bytesTransferred = transfers[idx].totalBytes
            }
            transfers[idx].statusMessage = "Completed"
            currentTransfer = transfers[idx]
        }
        updateCurrentTransfer()
    }

    public func markFailed(id: UUID, error: String) {
        if let idx = transfers.firstIndex(where: { $0.id == id }) {
            // A terminated process reports an error; keep the user's "cancelled" state.
            guard transfers[idx].state != .cancelled else { updateCurrentTransfer(); return }
            transfers[idx].state = .failed(error)
            transfers[idx].statusMessage = error
            currentTransfer = transfers[idx]
            isVisible = true
        }
        updateCurrentTransfer()
    }

    /// Conflict dialog "Skip": the item ends without work, shown as cancelled with a reason.
    public func markSkipped(id: UUID) {
        if let idx = transfers.firstIndex(where: { $0.id == id }) {
            transfers[idx].state = .cancelled
            transfers[idx].statusMessage = "Skipped"
            currentTransfer = transfers[idx]
        }
        updateCurrentTransfer()
    }

    public func cancelTransfer(id: UUID) {
        guard let idx = transfers.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = transfers[idx].state == .inProgress || transfers[idx].state == .queued
        transfers[idx].state = .cancelled
        transfers[idx].statusMessage = "Cancelled"
        currentTransfer = transfers[idx]
        if wasActive, let batch = transfers[idx].batchID {
            batchCancelHandler?(batch)
        }
        updateCurrentTransfer()
    }

    /// Marks every unfinished item of a batch cancelled (the batch task itself is cancelled by the coordinator).
    public func markBatchCancelled(_ batch: UUID) {
        for i in transfers.indices where transfers[i].batchID == batch && (transfers[i].state == .inProgress || transfers[i].state == .queued) {
            transfers[i].state = .cancelled
            transfers[i].statusMessage = "Cancelled"
        }
        updateCurrentTransfer()
    }

    public func cancelAll() {
        let batches = Set(transfers.filter { $0.state == .inProgress || $0.state == .queued }.compactMap { $0.batchID })
        for i in 0..<transfers.count {
            if transfers[i].state == .inProgress || transfers[i].state == .queued {
                transfers[i].state = .cancelled
                transfers[i].statusMessage = "Cancelled"
            }
        }
        for b in batches { batchCancelHandler?(b) }
        updateCurrentTransfer()
    }

    public func clearCompleted() {
        transfers.removeAll { $0.state == .completed || $0.state == .cancelled || $0.state.isFailed }
        updateCurrentTransfer()
        if transfers.isEmpty {
            withAnimation {
                isVisible = false
            }
        }
    }

    public func remove(id: UUID) {
        transfers.removeAll { $0.id == id }
        updateCurrentTransfer()
    }

    /// Finished rows stay for the Transfers window; only the oldest are dropped past this size.
    public static let historyLimit = 200

    private func trimHistory() {
        var finished = transfers.filter { $0.state == .completed || $0.state == .cancelled || $0.state.isFailed }.count
        guard finished > Self.historyLimit else { return }
        transfers.removeAll { item in
            guard finished > Self.historyLimit, item.state == .completed || item.state == .cancelled || item.state.isFailed else { return false }
            finished -= 1
            return true
        }
    }

    private func updateCurrentTransfer() {
        if let inProg = transfers.first(where: { $0.state == .inProgress }) {
            currentTransfer = inProg
            isVisible = true
        } else if let queued = transfers.first(where: { $0.state == .queued }) {
            currentTransfer = queued
            isVisible = true
        } else if let failed = transfers.last(where: { $0.state.isFailed }) {
            currentTransfer = failed
            isVisible = true
        } else if let completed = transfers.last(where: { $0.state == .completed }) {
            currentTransfer = completed
            isVisible = true
            // Auto-hide the banner after 2.0 seconds; rows stay for the Transfers window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if !self.hasActiveTransfers {
                    withAnimation {
                        self.isVisible = false
                    }
                }
            }
        } else {
            currentTransfer = nil
            withAnimation {
                isVisible = false
            }
        }
    }
}
