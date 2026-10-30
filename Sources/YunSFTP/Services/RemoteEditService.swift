import Foundation
import AppKit

/// "Edit in external editor": downloads a remote file to a private temp folder, opens it with the
/// default app and uploads it back whenever the editor saves. Sessions live until the app quits
/// or the user stops them in the Transfers window.
@MainActor
public final class RemoteEditService: ObservableObject {
    public static let shared = RemoteEditService()

    public struct Session: Identifiable, Sendable {
        public let id: UUID
        public let fileName: String
        public let remotePath: String
        public let connection: RemoteConnection
        public let password: String?
        public let localURL: URL
        var lastSeenModification: Date
        var changePending = false
        public var uploadCount = 0
        public var lastError: String?
    }

    @Published public private(set) var sessions: [Session] = []
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval
    private let coordinator: TransferCoordinator

    public init(pollInterval: TimeInterval = 1.0, coordinator: TransferCoordinator = .shared) {
        self.pollInterval = pollInterval
        self.coordinator = coordinator
    }

    /// Downloads and (optionally) opens the file; returns the session.
    @discardableResult
    public func edit(item: FileItem, connection: RemoteConnection, password: String?, open: Bool = true) async throws -> Session {
        let remotePath = SFTPService.normalizeRemotePath(item.url.path)
        if let existing = sessions.first(where: { $0.remotePath == remotePath && $0.connection.id == connection.id }) {
            if open { NSWorkspace.shared.open(existing.localURL) }
            return existing
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpEdit/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let localURL = try await SFTPService.shared.download(remotePath: remotePath, to: dir, connection: connection, password: password, overwrite: true)
        let mtime = Self.modificationDate(of: localURL) ?? Date()
        let session = Session(id: UUID(), fileName: item.name, remotePath: remotePath, connection: connection, password: password,
                              localURL: localURL, lastSeenModification: mtime)
        sessions.append(session)
        startPollingIfNeeded()
        if open { NSWorkspace.shared.open(localURL) }
        return session
    }

    public func stop(sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
        if sessions.isEmpty { pollTask?.cancel(); pollTask = nil }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.tick()
            }
        }
    }

    /// One poll: a changed modification date marks the session pending; the next poll with a
    /// stable date uploads (editors write in several steps, this avoids racing them).
    public func tick() async {
        // Iterate by id: a session may be stopped while an earlier one is awaiting its upload.
        for id in sessions.map(\.id) {
            guard let index = sessions.firstIndex(where: { $0.id == id }) else { continue }
            let session = sessions[index]
            guard let mtime = Self.modificationDate(of: session.localURL) else { continue }
            if mtime != session.lastSeenModification {
                sessions[index].lastSeenModification = mtime
                sessions[index].changePending = true
            } else if session.changePending {
                sessions[index].changePending = false
                await upload(sessionID: session.id)
            }
        }
    }

    private func upload(sessionID: UUID) async {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        let parent = (session.remotePath as NSString).deletingLastPathComponent
        let remoteDir = parent.isEmpty ? "/" : parent
        let batch = coordinator.runAdHoc(fileName: session.fileName, direction: .upload, totalBytes: Self.size(of: session.localURL)) { _ in
            try await SFTPService.shared.upload(localURL: session.localURL, to: remoteDir, connection: session.connection, password: session.password, overwrite: true)
        }
        await coordinator.wait(for: batch)
        if let i = sessions.firstIndex(where: { $0.id == sessionID }) {
            switch coordinator.state(ofBatch: batch) {
            case .completed?:
                sessions[i].uploadCount += 1
                sessions[i].lastError = nil
            case .failed(let message)?:
                sessions[i].lastError = message
            default:
                sessions[i].lastError = L("Upload did not complete.")
            }
        }
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0
    }
}
