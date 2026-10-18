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

    public func addTransfer(fileName: String, direction: TransferDirection, totalBytes: Int64 = 0) -> UUID {
        let item = TransferTaskItem(
            fileName: fileName,
            direction: direction,
            state: .queued,
            progress: 0.0,
            bytesTransferred: 0,
            totalBytes: totalBytes,
            statusMessage: "Preparing..."
        )
        transfers.append(item)
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
            transfers[idx].state = .failed(error)
            transfers[idx].statusMessage = error
            currentTransfer = transfers[idx]
            isVisible = true
        }
        updateCurrentTransfer()
    }

    public func cancelTransfer(id: UUID) {
        if let idx = transfers.firstIndex(where: { $0.id == id }) {
            transfers[idx].state = .cancelled
            transfers[idx].statusMessage = "Cancelled"
            currentTransfer = transfers[idx]
        }
        updateCurrentTransfer()
    }

    public func cancelAll() {
        for i in 0..<transfers.count {
            if transfers[i].state == .inProgress || transfers[i].state == .queued {
                transfers[i].state = .cancelled
                transfers[i].statusMessage = "Cancelled"
            }
        }
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
            // Auto-hide after 2.0 seconds if no new transfers
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if !self.hasActiveTransfers {
                    withAnimation {
                        self.isVisible = false
                        self.clearCompleted()
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
