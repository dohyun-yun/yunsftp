import Foundation
import AppKit

/// Where a transfer reads from or writes to. For sources only the kind and connection matter
/// (items carry absolute URLs); for destinations the directory is used.
public enum TransferLocation: Sendable {
    case local(URL)
    case remote(RemoteConnection, password: String?, path: String)

    public var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    public var connection: RemoteConnection? {
        if case .remote(let c, _, _) = self { return c }
        return nil
    }

    public var password: String? {
        if case .remote(_, let p, _) = self { return p }
        return nil
    }

    public var description: String {
        switch self {
        case .local(let url): return url.path
        case .remote(let c, _, let path): return "\(c.displayTitle):\(path)"
        }
    }

    @MainActor
    public static func from(pane: PaneModel, subfolder: FileItem? = nil) -> TransferLocation? {
        if pane.isRemote {
            guard let conn = pane.remoteConnection else { return nil }
            let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            let dir = subfolder.map { SFTPService.normalizeRemotePath($0.url.path) } ?? SFTPService.normalizeRemotePath(pane.remotePath)
            return .remote(conn, password: pwd, path: dir)
        }
        return .local(subfolder?.url ?? pane.currentURL)
    }
}

public enum TransferMode: Sendable { case copy, move }

public enum ConflictChoice: Sendable, Equatable { case replace, keepBoth, skip, cancel }

public struct ConflictDecision: Sendable {
    public var choice: ConflictChoice
    public var applyToAll: Bool
    public init(_ choice: ConflictChoice, applyToAll: Bool = false) { self.choice = choice; self.applyToAll = applyToAll }
}

/// Asked once per conflicting item (unless the user chose "apply to all").
public typealias ConflictResolver = @MainActor (_ fileName: String, _ destination: String) async -> ConflictDecision

public struct TransferRequest: Sendable {
    public var items: [FileItem]
    public var source: TransferLocation
    public var destination: TransferLocation
    public var mode: TransferMode
    /// Fixed policy for name conflicts; nil asks the resolver.
    public var conflictPolicy: ConflictChoice?

    public init(items: [FileItem], source: TransferLocation, destination: TransferLocation, mode: TransferMode, conflictPolicy: ConflictChoice? = nil) {
        self.items = items
        self.source = source
        self.destination = destination
        self.mode = mode
        self.conflictPolicy = conflictPolicy
    }

    public var direction: TransferDirection {
        switch (source.isRemote, destination.isRemote) {
        case (false, false): return mode == .move ? .localMove : .localCopy
        case (true, false): return .download
        case (false, true): return .upload
        case (true, true): return .remoteCopy
        }
    }
}

/// Runs every copy/move/paste/drop as a batch: one `Task`, one task-local batch id that tags the
/// ssh/sftp/scp children it spawns, so cancelling a batch stops exactly that batch.
@MainActor
public final class TransferCoordinator {
    public static let shared = TransferCoordinator(manager: TransferManager.shared)

    private let manager: TransferManager
    private var batches: [UUID: Task<Void, Never>] = [:]
    /// Single-item requests kept per transfer row so a failed row can be retried.
    private var retryRequests: [UUID: TransferRequest] = [:]
    /// Replaceable for tests; defaults to an NSAlert.
    public var conflictResolver: ConflictResolver = ConflictAlert.present
    /// Called after a local→local move with (from, to) so the window can register an undo.
    public var localMoveRecorder: ((_ actionName: String, _ moves: [(from: URL, to: URL)]) -> Void)?

    public init(manager: TransferManager) {
        self.manager = manager
        manager.batchCancelHandler = { [weak self] batch in self?.cancel(batch: batch) }
        manager.rowsRemovedHandler = { [weak self] ids in for id in ids { self?.retryRequests[id] = nil } }
    }

    public var activeBatchIDs: Set<UUID> { Set(batches.keys) }

    @discardableResult
    public func start(_ request: TransferRequest, onFinished: @escaping @MainActor () -> Void = {}) -> UUID {
        let batchID = UUID()
        let task = Task { [weak self] in
            await SFTPService.$currentBatch.withValue(batchID) {
                await self?.run(request, batchID: batchID)
            }
            self?.batches[batchID] = nil
            onFinished()
        }
        batches[batchID] = task
        return batchID
    }

    /// One-off operation (e.g. download-and-open) that still shows up and cancels like a batch.
    @discardableResult
    public func runAdHoc(fileName: String, direction: TransferDirection, totalBytes: Int64,
                         work: @escaping @Sendable (_ taskID: UUID) async throws -> Void,
                         onFinished: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }) -> UUID {
        let batchID = UUID()
        let taskID = manager.addTransfer(fileName: fileName, direction: direction, totalBytes: totalBytes, batchID: batchID)
        let task = Task { [weak self] in
            let outcome: Result<Void, Error>
            do {
                try await SFTPService.$currentBatch.withValue(batchID) { try await work(taskID) }
                self?.manager.markCompleted(id: taskID)
                outcome = .success(())
            } catch {
                self?.finish(taskID: taskID, with: error)
                outcome = .failure(error)
            }
            self?.batches[batchID] = nil
            onFinished(outcome)   // the row may already be trimmed; the outcome is authoritative
        }
        batches[batchID] = task
        return batchID
    }

    public func canRetry(taskID: UUID) -> Bool { retryRequests[taskID] != nil }

    /// State of the (single) row a batch produced; nil when the row is gone.
    public func state(ofBatch batch: UUID) -> TransferState? {
        manager.transfers.last { $0.batchID == batch }?.state
    }

    /// Re-runs a failed or cancelled row as a new one-item batch.
    @discardableResult
    public func retry(taskID: UUID, onFinished: @escaping @MainActor () -> Void = {}) -> UUID? {
        guard let request = retryRequests[taskID],
              let state = manager.transfers.first(where: { $0.id == taskID })?.state,
              state.isFailed || state == .cancelled else { return nil }
        manager.remove(id: taskID)          // rowsRemovedHandler drops the retry entry
        return start(request, onFinished: onFinished)
    }

    public func cancel(batch: UUID) {
        batches[batch]?.cancel()
        ProcessRegistry.shared.terminate(batch: batch)
        manager.markBatchCancelled(batch)
    }

    public func cancelAll() {
        for id in Array(batches.keys) { cancel(batch: id) }
    }

    /// Waits for a batch to finish (tests and callers that need completion).
    public func wait(for batch: UUID) async {
        await batches[batch]?.value
    }

    // MARK: - Execution

    private func run(_ request: TransferRequest, batchID: UUID) async {
        var applyToAll: ConflictChoice? = request.conflictPolicy
        for item in request.items {
            if Task.isCancelled { break }
            let name = SFTPService.decodeLsEscapes(item.name).precomposedStringWithCanonicalMapping
            let taskID = manager.addTransfer(fileName: name, direction: request.direction, totalBytes: item.size, batchID: batchID)
            retryRequests[taskID] = TransferRequest(items: [item], source: request.source, destination: request.destination, mode: request.mode, conflictPolicy: request.conflictPolicy)
            do {
                let samePlace = Self.isSamePlace(item: item, name: name, request: request)
                if samePlace && request.mode == .move {
                    throw Self.alreadyInFolderError(name)
                }
                var overwrite = false
                if try await destinationExists(name: name, at: request.destination) {
                    let choice: ConflictChoice
                    if let fixed = applyToAll {
                        choice = fixed
                    } else {
                        let decision = await conflictResolver(name, request.destination.description)
                        choice = decision.choice
                        if decision.applyToAll { applyToAll = decision.choice }
                    }
                    switch choice {
                    case .skip:
                        manager.markSkipped(id: taskID)
                        continue
                    case .cancel:
                        manager.markSkipped(id: taskID)
                        cancel(batch: batchID)
                        return
                    case .replace:
                        // Replacing a file with itself would delete it; Keep Both is the only safe copy here.
                        if samePlace { throw Self.alreadyInFolderError(name) }
                        overwrite = true
                    case .keepBoth: overwrite = false
                    }
                }
                try await perform(item: item, name: name, request: request, overwrite: overwrite, taskID: taskID)
                manager.markCompleted(id: taskID)
            } catch {
                finish(taskID: taskID, with: error)
                if error is CancellationError || SFTPService.isCancellation(error) { return }
            }
        }
    }

    private func finish(taskID: UUID, with error: Error) {
        if error is CancellationError || SFTPService.isCancellation(error) {
            manager.cancelTransfer(id: taskID)
        } else {
            manager.markFailed(id: taskID, error: error.localizedDescription)
        }
    }

    static func alreadyInFolderError(_ name: String) -> NSError {
        NSError(domain: "TransferCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: L("\"%@\" is already in that folder.", name)])
    }

    /// True when the item already lives in the destination folder (copying a file onto itself).
    /// Local folders are compared by file-system identity (symlinks, case-insensitive volumes);
    /// servers by host, port and user, since two saved connections may point at one server.
    static func isSamePlace(item: FileItem, name: String, request: TransferRequest) -> Bool {
        switch (request.source, request.destination) {
        case (.local, .local(let dir)):
            // Resolve links first: the resource identifier of a symlink URL is the link's own.
            let a = item.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            let b = dir.resolvingSymlinksInPath().standardizedFileURL
            if let ia = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
               let ib = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier {
                return ia.isEqual(ib)
            }
            return a.path.caseInsensitiveCompare(b.path) == .orderedSame
        case (.remote(let src, _, _), .remote(let dst, _, let dir)):
            let parent = (SFTPService.normalizeRemotePath(item.url.path) as NSString).deletingLastPathComponent
            return src.isSameServer(as: dst) && SFTPService.normalizeRemotePath(parent.isEmpty ? "/" : parent) == SFTPService.normalizeRemotePath(dir)
        default:
            return false
        }
    }

    func destinationExists(name: String, at destination: TransferLocation) async throws -> Bool {
        switch destination {
        case .local(let dir):
            return (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)) != nil
        case .remote(let conn, let pwd, let dir):
            let path = dir == "/" ? "/\(name)" : "\(dir)/\(name)"
            return try await SFTPService.shared.remoteExists(path, connection: conn, password: pwd)
        }
    }

    private func perform(item: FileItem, name: String, request: TransferRequest, overwrite: Bool, taskID: UUID) async throws {
        let size = item.size
        switch (request.source, request.destination) {

        case (.local, .local(let destDir)):
            let plannedURL = overwrite ? destDir.appendingPathComponent(name) : FileSystemService.plannedDestinationURL(fileName: name, in: destDir)
            let monitor = monitorGrowth(of: plannedURL, expected: size, taskID: taskID, verb: request.mode == .move ? "Moving" : "Copying", name: name)
            defer { monitor.cancel() }
            if request.mode == .move {
                let moved = try await FileSystemService.shared.move(urls: [item.url], to: destDir, overwrite: overwrite)
                if let to = moved.first { localMoveRecorder?("Move \(name)", [(from: item.url, to: to)]) }
            } else {
                try await FileSystemService.shared.copy(urls: [item.url], to: destDir, overwrite: overwrite)
            }

        case (.remote(let conn, let pwd, _), .local(let destDir)):
            let remotePath = SFTPService.normalizeRemotePath(item.url.path)
            let plannedURL = overwrite ? destDir.appendingPathComponent(name) : FileSystemService.plannedDestinationURL(fileName: name, in: destDir)
            let monitor = monitorGrowth(of: SFTPService.stagedURL(for: plannedURL), expected: size, taskID: taskID, verb: "Downloading", name: name)
            defer { monitor.cancel() }
            _ = try await SFTPService.shared.download(remotePath: remotePath, to: destDir, connection: conn, password: pwd, overwrite: overwrite,
                                                      progress: progressReporter(taskID: taskID, expected: size, verb: "Downloading", name: name))
            if request.mode == .move {
                try await SFTPService.shared.remove(remotePath: remotePath, isDirectory: item.isDirectory, connection: conn, password: pwd)
            }

        case (.local, .remote(let conn, let pwd, let destDir)):
            manager.updateProgress(id: taskID, progress: 0.05, bytesTransferred: 0, totalBytes: size, message: "Uploading \(name)...")
            try await SFTPService.shared.upload(localURL: item.url, to: destDir, connection: conn, password: pwd, overwrite: overwrite,
                                                progress: progressReporter(taskID: taskID, expected: size, verb: "Uploading", name: name))
            if request.mode == .move {
                try await FileSystemService.shared.moveToTrash(urls: [item.url])
            }

        case (.remote(let srcConn, let srcPwd, _), .remote(let dstConn, let dstPwd, let destDir)):
            let srcPath = SFTPService.normalizeRemotePath(item.url.path)
            manager.updateProgress(id: taskID, progress: 0.1, bytesTransferred: 0, totalBytes: size, message: "Transferring \(name)...")
            if request.mode == .move && srcConn.isSameServer(as: dstConn) {
                var targetName = name
                let targetPath = { (n: String) in destDir == "/" ? "/\(n)" : "\(destDir)/\(n)" }
                if overwrite {
                    try? await SFTPService.shared.remove(remotePath: targetPath(name), isDirectory: false, connection: dstConn, password: dstPwd)
                } else {
                    targetName = try await SFTPService.shared.uniqueRemoteName(name, in: destDir, connection: dstConn, password: dstPwd)
                }
                try await SFTPService.shared.rename(remotePath: srcPath, to: targetPath(targetName), connection: dstConn, password: dstPwd)
            } else {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpTransfer_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }
                let downloaded = try await SFTPService.shared.download(remotePath: srcPath, to: tempDir, connection: srcConn, password: srcPwd, overwrite: true)
                try await SFTPService.shared.upload(localURL: downloaded, to: destDir, connection: dstConn, password: dstPwd, overwrite: overwrite)
                if request.mode == .move {
                    try await SFTPService.shared.remove(remotePath: srcPath, isDirectory: item.isDirectory, connection: srcConn, password: srcPwd)
                }
            }
        }
    }

    /// Byte-level progress from the native engine (the OpenSSH transport never calls it).
    private func progressReporter(taskID: UUID, expected: Int64, verb: String, name: String) -> @Sendable (Int64) -> Void {
        let manager = self.manager
        let throttle = ProgressThrottle()
        return { bytes in
            guard throttle.shouldReport(bytes: bytes, expected: expected) else { return }
            Task { @MainActor in
                let fraction = expected > 0 ? min(0.99, Double(bytes) / Double(expected)) : 0.5
                manager.updateProgress(id: taskID, progress: fraction, bytesTransferred: bytes, totalBytes: expected, message: "\(verb) \(name)...")
            }
        }
    }

    /// Limits UI updates to one per 1% or 200 ms, whichever comes first; the final byte count always passes.
    final class ProgressThrottle: @unchecked Sendable {
        private let lock = NSLock()
        private var lastBytes: Int64 = -1
        private var lastTime = Date.distantPast
        func shouldReport(bytes: Int64, expected: Int64, now: Date = Date()) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let complete = expected > 0 && bytes >= expected
            let step = max(expected / 100, 64 * 1024)
            guard complete || bytes - lastBytes >= step || now.timeIntervalSince(lastTime) >= 0.2 else { return false }
            lastBytes = bytes; lastTime = now
            return true
        }
    }

    /// Polls the growing destination file for byte-level progress (sftp/cp give none).
    private func monitorGrowth(of url: URL, expected: Int64, taskID: UUID, verb: String, name: String) -> Task<Void, Never> {
        let manager = self.manager
        return Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { break }
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let current = attrs[.size] as? Int64 {
                    let progress = expected > 0 ? min(0.98, max(0.01, Double(current) / Double(expected))) : 0.5
                    manager.updateProgress(id: taskID, progress: progress, bytesTransferred: current, totalBytes: expected, message: "\(verb) \(name)...")
                }
            }
        }
    }
}

/// Replace / Keep Both / Skip / Cancel sheet with an "apply to all" checkbox.
public enum ConflictAlert {
    @MainActor
    public static func present(fileName: String, destination: String) async -> ConflictDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("\"%@\" already exists in %@", fileName, destination)
        alert.informativeText = L("Replace it, keep both files, or skip this item?")
        alert.addButton(withTitle: L("Replace"))
        alert.addButton(withTitle: L("Keep Both"))
        alert.addButton(withTitle: L("Skip"))
        alert.addButton(withTitle: L("Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("Apply to all remaining items")
        let response = alert.runModal()
        let applyToAll = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn: return ConflictDecision(.replace, applyToAll: applyToAll)
        case .alertSecondButtonReturn: return ConflictDecision(.keepBoth, applyToAll: applyToAll)
        case .alertThirdButtonReturn: return ConflictDecision(.skip, applyToAll: applyToAll)
        default: return ConflictDecision(.cancel)
        }
    }
}
