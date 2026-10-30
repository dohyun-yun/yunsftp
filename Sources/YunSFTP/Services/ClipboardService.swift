import Foundation
import AppKit
import SwiftUI

@MainActor
public class ClipboardService: ObservableObject {
    public static let shared = ClipboardService()

    @Published public private(set) var copiedItems: [FileItem] = []
    @Published public private(set) var isCut: Bool = false
    @Published public private(set) var sourceIsRemote: Bool = false
    @Published public private(set) var sourceConnection: RemoteConnection? = nil
    @Published public private(set) var sourceRemotePassword: String? = nil

    public var canPaste: Bool {
        if !copiedItems.isEmpty { return true }
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return true
        }
        return false
    }

    public func copy(items: [FileItem], from pane: PaneModel) {
        guard !items.isEmpty else { return }
        self.copiedItems = items
        self.isCut = false
        self.sourceIsRemote = pane.isRemote
        self.sourceConnection = pane.remoteConnection
        self.sourceRemotePassword = pane.remotePassword

        if !pane.isRemote {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(items.map { $0.url as NSURL })
        }
    }

    public func cut(items: [FileItem], from pane: PaneModel) {
        guard !items.isEmpty else { return }
        self.copiedItems = items
        self.isCut = true
        self.sourceIsRemote = pane.isRemote
        self.sourceConnection = pane.remoteConnection
        self.sourceRemotePassword = pane.remotePassword

        if !pane.isRemote {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(items.map { $0.url as NSURL })
        }
    }

    public func clear() {
        self.copiedItems = []
        self.isCut = false
        self.sourceIsRemote = false
        self.sourceConnection = nil
        self.sourceRemotePassword = nil
    }

    /// Paste copied/cut items to destination pane
    public func paste(to targetPane: PaneModel, reloadPanes: @escaping () -> Void) {
        var itemsToPaste = self.copiedItems

        // If app-internal clipboard is empty, check system pasteboard (e.g. from Finder)
        if itemsToPaste.isEmpty {
            if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
                itemsToPaste = urls.map { FileItem(url: $0) }
                self.sourceIsRemote = false
            }
        }

        guard !itemsToPaste.isEmpty else { return }

        let transferManager = TransferManager.shared
        let wasCut = self.isCut
        let srcRemote = self.sourceIsRemote
        let srcConn = self.sourceConnection
        let srcPwd = self.sourceRemotePassword

        if wasCut {
            self.clear()
        }

        Task {
            // Case 1: Target is Local
            if !targetPane.isRemote {
                let destDir = targetPane.currentURL

                if srcRemote, let conn = srcConn {
                    // Download from Remote to Local with Live Monitoring
                    let batchStart = TransferManager.shared.beginBatch()
                    for item in itemsToPaste {
                        if TransferManager.shared.consumeCancelRequest(since: batchStart) { break }
                        let cleanFileName = SFTPService.decodeLsEscapes(item.name).precomposedStringWithCanonicalMapping
                        let remotePath = SFTPService.decodeLsEscapes(item.url.path).precomposedStringWithCanonicalMapping
                        let destFileURL = FileSystemService.plannedDestinationURL(fileName: cleanFileName, in: destDir)

                        let taskId = transferManager.addTransfer(
                            fileName: cleanFileName,
                            direction: .download,
                            totalBytes: item.size
                        )

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
                            _ = try await SFTPService.shared.download(remotePath: remotePath, to: destDir, connection: conn, password: srcPwd)
                            monitor.cancel()
                            if wasCut {
                                _ = try? await SFTPService.shared.remove(remotePath: remotePath, isDirectory: item.isDirectory, connection: conn, password: srcPwd)
                            }
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
                    // Local to Local (Copy or Move)
                    let dir: TransferDirection = wasCut ? .localMove : .localCopy
                    let batchStart = TransferManager.shared.beginBatch()
                    for item in itemsToPaste {
                        if TransferManager.shared.consumeCancelRequest(since: batchStart) { break }
                        let taskId = transferManager.addTransfer(
                            fileName: item.name,
                            direction: dir,
                            totalBytes: item.size
                        )
                        let destFileURL = FileSystemService.plannedDestinationURL(fileName: item.name, in: destDir)

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
                                            message: "\(wasCut ? "Moving" : "Copying") \(item.name)..."
                                        )
                                    }
                                }
                            }
                        }

                        do {
                            if wasCut {
                                try await FileSystemService.shared.move(urls: [item.url], to: destDir)
                            } else {
                                try await FileSystemService.shared.copy(urls: [item.url], to: destDir)
                            }
                            monitor.cancel()
                            await MainActor.run {
                                transferManager.updateProgress(id: taskId, progress: 1.0, bytesTransferred: item.size, totalBytes: item.size, message: "Done")
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
                let targetRemoteDir = targetPane.remotePath.precomposedStringWithCanonicalMapping

                if !srcRemote {
                    // Upload Local to Remote
                    let batchStart = TransferManager.shared.beginBatch()
                    for item in itemsToPaste {
                        if TransferManager.shared.consumeCancelRequest(since: batchStart) { break }
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
                            if wasCut {
                                try? await FileSystemService.shared.moveToTrash(urls: [item.url])
                            }
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
                } else if let srcConn = srcConn {
                    // Remote to Remote
                    let batchStart = TransferManager.shared.beginBatch()
                    for item in itemsToPaste {
                        if TransferManager.shared.consumeCancelRequest(since: batchStart) { break }
                        let taskId = transferManager.addTransfer(
                            fileName: item.name,
                            direction: .remoteCopy,
                            totalBytes: item.size
                        )
                        await MainActor.run {
                            transferManager.updateProgress(id: taskId, progress: 0.1, bytesTransferred: 0, totalBytes: item.size, message: "Transferring \(item.name)...")
                        }
                        let srcPath = item.url.path.precomposedStringWithCanonicalMapping
                        let dstPath = (targetRemoteDir == "/" ? "/\(item.name)" : "\(targetRemoteDir)/\(item.name)").precomposedStringWithCanonicalMapping

                        do {
                            if srcConn.id == targetConn.id && wasCut {
                                try await SFTPService.shared.rename(remotePath: srcPath, to: dstPath, connection: targetConn, password: targetPwd)
                            } else {
                                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpTransfer_\(UUID().uuidString)")
                                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                                let downloadedURL = try await SFTPService.shared.download(remotePath: srcPath, to: tempDir, connection: srcConn, password: srcPwd)
                                try await SFTPService.shared.upload(localURL: downloadedURL, to: targetRemoteDir, connection: targetConn, password: targetPwd)
                                try? FileManager.default.removeItem(at: tempDir)
                                if wasCut {
                                    _ = try? await SFTPService.shared.remove(remotePath: srcPath, isDirectory: item.isDirectory, connection: srcConn, password: srcPwd)
                                }
                            }
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
                reloadPanes()
            }
        }
    }
}
