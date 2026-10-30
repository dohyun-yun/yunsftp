import Foundation
import AppKit
import UniformTypeIdentifiers

/// Drag source for remote items. Other apps (Finder, Mail, …) see a file promise and receive the
/// downloaded file when they accept the drop; our own panes keep seeing the sftp URL.
public enum RemoteDragProvider {

    public static func fileType(for item: FileItem) -> UTType {
        if item.isDirectory { return .folder }
        if !item.fileExtension.isEmpty, let t = UTType(filenameExtension: item.fileExtension) { return t }
        return .data
    }

    public static func make(item: FileItem, connection: RemoteConnection, password: String?) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = item.name
        let remotePath = SFTPService.normalizeRemotePath(item.url.path)
        let type = fileType(for: item)

        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            // Another process is taking the drop: the internal drag state must not leak into the next drop.
            Task { @MainActor in DragDropManager.shared.endDrag() }
            let progress = Progress(totalUnitCount: 1)
            let task = Task {
                do {
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpDrag/\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = try await SFTPService.shared.download(remotePath: remotePath, to: dir, connection: connection, password: password, overwrite: true)
                    progress.completedUnitCount = 1
                    // `false`: the receiver copies the file, we keep (and later clean) the temp copy.
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
        // Internal pane-to-pane drops still read the sftp URL; invisible to other processes.
        provider.registerObject(item.url as NSURL, visibility: .ownProcess)
        return provider
    }

    /// Temp copies from finished drags; called on launch so they do not accumulate.
    public static func cleanUpTempCopies(olderThan age: TimeInterval = 3600) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpDrag", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for d in dirs {
            if let m = (try? d.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, Date().timeIntervalSince(m) > age {
                try? FileManager.default.removeItem(at: d)
            }
        }
    }
}
