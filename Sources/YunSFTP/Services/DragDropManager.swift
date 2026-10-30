import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public class DragDropManager: ObservableObject {
    public static let shared = DragDropManager()

    @Published public var draggedItems: [FileItem] = []
    @Published public var sourcePaneId: UUID? = nil
    @Published public var sourceIsRemote: Bool = false
    @Published public var sourceConnection: RemoteConnection? = nil
    @Published public var sourceRemotePassword: String? = nil

    public func startDrag(items: [FileItem], from pane: PaneModel) {
        self.draggedItems = items
        self.sourcePaneId = pane.id
        self.sourceIsRemote = pane.isRemote
        self.sourceConnection = pane.remoteConnection
        self.sourceRemotePassword = pane.remotePassword
    }

    public func endDrag() {
        self.draggedItems = []
        self.sourcePaneId = nil
        self.sourceIsRemote = false
        self.sourceConnection = nil
        self.sourceRemotePassword = nil
    }

    /// Process drop onto a destination pane (optionally onto a specific subfolder inside the pane)
    public func handleDrop(
        onto targetPane: PaneModel,
        targetSubfolder: FileItem? = nil,
        externalProviders: [NSItemProvider] = [],
        completion: @escaping () -> Void
    ) {
        // If we have items from an internal drag
        if !draggedItems.isEmpty {
            let items = self.draggedItems
            let srcRemote = self.sourceIsRemote
            let srcConn = self.sourceConnection
            let srcPwd = self.sourceRemotePassword
            self.endDrag()

            executeTransfer(
                items: items,
                sourceIsRemote: srcRemote,
                sourceConn: srcConn,
                sourcePwd: srcPwd,
                targetPane: targetPane,
                targetSubfolder: targetSubfolder,
                completion: completion
            )
            return
        }

        // Otherwise handle external providers (e.g. from macOS Finder)
        guard !externalProviders.isEmpty else { return }

        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in externalProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            collectedURLs.append(url)
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            collectedURLs.append(url)
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                _ = provider.loadObject(ofClass: NSString.self) { str, _ in
                    if let str = str as? String, let url = URL(string: str) {
                        DispatchQueue.main.async {
                            collectedURLs.append(url)
                        }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            guard !collectedURLs.isEmpty else { return }
            let items = collectedURLs.map { FileItem(url: $0) }
            self.executeTransfer(
                items: items,
                sourceIsRemote: false,
                sourceConn: nil,
                sourcePwd: nil,
                targetPane: targetPane,
                targetSubfolder: targetSubfolder,
                completion: completion
            )
        }
    }

    private func executeTransfer(
        items: [FileItem],
        sourceIsRemote: Bool,
        sourceConn: RemoteConnection?,
        sourcePwd: String?,
        targetPane: PaneModel,
        targetSubfolder: FileItem?,
        completion: @escaping () -> Void
    ) {
        let transferManager = TransferManager.shared

        Task {
            // Case 1: Target is Local
            if !targetPane.isRemote {
                let destDir: URL
                if let sub = targetSubfolder, sub.isDirectory {
                    destDir = sub.url
                } else {
                    destDir = targetPane.currentURL
                }

                if sourceIsRemote, let conn = sourceConn {
                    // SFTP Download with Live Monitoring
                    for item in items {
                        if TransferManager.shared.consumeCancelRequest() { break }
                        let cleanFileName = SFTPService.decodeLsEscapes(item.name).precomposedStringWithCanonicalMapping
                        let remotePath = SFTPService.decodeLsEscapes(item.url.path).precomposedStringWithCanonicalMapping
                        let destFileURL = destDir.appendingPathComponent(cleanFileName)

                        let taskId = transferManager.addTransfer(
                            fileName: cleanFileName,
                            direction: .download,
                            totalBytes: item.size
                        )

                        // Live disk monitor
                        let monitor = Task {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                guard !Task.isCancelled else { break }
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: destFileURL.path),
                                   let currentBytes = attrs[.size] as? Int64 {
                                    guard !Task.isCancelled else { break }
                                    let progress = item.size > 0 ? min(0.98, max(0.01, Double(currentBytes) / Double(item.size))) : 0.5
                                    await MainActor.run {
                                        guard !Task.isCancelled else { return }
                                        transferManager.updateProgress(
                                            id: taskId,
                                            progress: progress,
                                            bytesTransferred: currentBytes,
                                            totalBytes: item.size,
                                            message: "Downloading \(item.name)..."
                                        )
                                    }
                                }
                            }
                        }

                        do {
                            _ = try await SFTPService.shared.download(remotePath: remotePath, to: destDir, connection: conn, password: sourcePwd)
                            monitor.cancel()
                            await MainActor.run {
                                transferManager.updateProgress(id: taskId, progress: 1.0, bytesTransferred: item.size, totalBytes: item.size, message: "Downloaded \(item.name)")
                                transferManager.markCompleted(id: taskId)
                            }
                        } catch {
                            monitor.cancel()
                            await MainActor.run {
                                transferManager.markFailed(id: taskId, error: error.localizedDescription)
                            }
                        }
                    }
                } else {
                    // Local to Local Copy with Live Monitoring
                    for item in items {
                        if TransferManager.shared.consumeCancelRequest() { break }
                        let taskId = transferManager.addTransfer(
                            fileName: item.name,
                            direction: .localCopy,
                            totalBytes: item.size
                        )
                        let destFileURL = destDir.appendingPathComponent(item.name)

                        let monitor = Task {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                guard !Task.isCancelled else { break }
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: destFileURL.path),
                                   let currentBytes = attrs[.size] as? Int64 {
                                    guard !Task.isCancelled else { break }
                                    let progress = item.size > 0 ? min(0.98, max(0.05, Double(currentBytes) / Double(item.size))) : 0.5
                                    await MainActor.run {
                                        guard !Task.isCancelled else { return }
                                        transferManager.updateProgress(
                                            id: taskId,
                                            progress: progress,
                                            bytesTransferred: currentBytes,
                                            totalBytes: item.size,
                                            message: "Copying \(item.name)..."
                                        )
                                    }
                                }
                            }
                        }

                        do {
                            try await FileSystemService.shared.copy(urls: [item.url], to: destDir)
                            monitor.cancel()
                            await MainActor.run {
                                transferManager.updateProgress(id: taskId, progress: 1.0, bytesTransferred: item.size, totalBytes: item.size, message: "Copied \(item.name)")
                                transferManager.markCompleted(id: taskId)
                            }
                        } catch {
                            monitor.cancel()
                            await MainActor.run {
                                transferManager.markFailed(id: taskId, error: error.localizedDescription)
                            }
                        }
                    }
                }
            } else {
                // Case 2: Target is Remote
                guard let targetConn = targetPane.remoteConnection else { return }
                let targetPwd = targetPane.remotePassword ?? (targetConn.authType == .password ? KeychainService.shared.loadPassword(for: targetConn) : nil)
                let baseRemoteDir = targetPane.remotePath.precomposedStringWithCanonicalMapping

                let targetRemoteDir: String
                if let sub = targetSubfolder, sub.isDirectory {
                    let subPath = sub.url.path.precomposedStringWithCanonicalMapping
                    targetRemoteDir = subPath
                } else {
                    targetRemoteDir = baseRemoteDir
                }

                if !sourceIsRemote {
                    // Upload Local to Remote
                    for item in items {
                        if TransferManager.shared.consumeCancelRequest() { break }
                        let taskId = transferManager.addTransfer(
                            fileName: item.name,
                            direction: .upload,
                            totalBytes: item.size
                        )
                        await MainActor.run {
                            transferManager.updateProgress(id: taskId, progress: 0.1, bytesTransferred: 0, totalBytes: item.size, message: "Uploading \(item.name)...")
                        }
                        do {
                            try await SFTPService.shared.upload(localURL: item.url, to: targetRemoteDir, connection: targetConn, password: targetPwd)
                            await MainActor.run {
                                transferManager.updateProgress(id: taskId, progress: 1.0, bytesTransferred: item.size, totalBytes: item.size, message: "Uploaded \(item.name)")
                                transferManager.markCompleted(id: taskId)
                            }
                        } catch {
                            await MainActor.run {
                                transferManager.markFailed(id: taskId, error: error.localizedDescription)
                            }
                        }
                    }
                } else if let srcConn = sourceConn {
                    // Remote to Remote Transfer
                    for item in items {
                        if TransferManager.shared.consumeCancelRequest() { break }
                        let taskId = transferManager.addTransfer(
                            fileName: item.name,
                            direction: .remoteCopy,
                            totalBytes: item.size
                        )
                        await MainActor.run {
                            transferManager.updateProgress(id: taskId, progress: 0.1, bytesTransferred: 0, totalBytes: item.size, message: "Transferring \(item.name)...")
                        }
                        let srcPath = item.url.path.precomposedStringWithCanonicalMapping
                        do {
                            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpDrag_\(UUID().uuidString)")
                            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                            let downloadedURL = try await SFTPService.shared.download(remotePath: srcPath, to: tempDir, connection: srcConn, password: sourcePwd)
                            try await SFTPService.shared.upload(localURL: downloadedURL, to: targetRemoteDir, connection: targetConn, password: targetPwd)
                            try? FileManager.default.removeItem(at: tempDir)
                            await MainActor.run {
                                transferManager.updateProgress(id: taskId, progress: 1.0, bytesTransferred: item.size, totalBytes: item.size, message: "Transferred \(item.name)")
                                transferManager.markCompleted(id: taskId)
                            }
                        } catch {
                            await MainActor.run {
                                transferManager.markFailed(id: taskId, error: error.localizedDescription)
                            }
                        }
                    }
                }
            }

            await MainActor.run {
                completion()
            }
        }
    }
}
