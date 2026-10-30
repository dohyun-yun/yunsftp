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

    public init() {}

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
        // Resolve what was actually dropped first. Internal drags carry our own URLs (local file
        // URLs, or the sftp URL registered for this process); a stale internal state from a drag
        // that ended in another app never matches a later Finder drop.
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in externalProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
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
            let internalItems = Self.internalItems(dragged: self.draggedItems, dropped: collectedURLs, hadProviders: !externalProviders.isEmpty)
            if !internalItems.isEmpty {
                let items = internalItems
                let srcRemote = self.sourceIsRemote
                let srcConn = self.sourceConnection
                let srcPwd = self.sourceRemotePassword
                self.endDrag()
                self.executeTransfer(items: items, sourceIsRemote: srcRemote, sourceConn: srcConn, sourcePwd: srcPwd,
                                     targetPane: targetPane, targetSubfolder: targetSubfolder, completion: completion)
                return
            }
            self.endDrag()   // whatever was cached belonged to a drag that ended elsewhere
            guard !collectedURLs.isEmpty else { return }
            let items = collectedURLs.filter { $0.isFileURL }.map { FileItem(url: $0) }
            guard !items.isEmpty else { return }
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

    /// The dragged items that were actually dropped. A stale cache from a drag that ended in
    /// another app only ever contributes the items the user dropped again, never the whole set.
    static func internalItems(dragged: [FileItem], dropped: [URL], hadProviders: Bool) -> [FileItem] {
        guard !dragged.isEmpty else { return [] }
        guard hadProviders else { return dragged }
        let droppedKeys = Set(dropped.map(normalizedKey))
        return dragged.filter { droppedKeys.contains(normalizedKey($0.url)) }
    }

    static func isInternalDrop(dragged: [FileItem], dropped: [URL], hadProviders: Bool) -> Bool {
        !internalItems(dragged: dragged, dropped: dropped, hadProviders: hadProviders).isEmpty
    }

    /// Stable identity across the pasteboard round trip (trailing slashes, percent-encoding, NFD/NFC).
    static func normalizedKey(_ url: URL) -> String {
        if url.isFileURL {
            var p = url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
            if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
            return "file:" + p
        }
        let path = SFTPService.normalizeRemotePath(url.path)
        return "\(url.scheme ?? ""):\(url.host ?? ""):\(url.port ?? 22)\(path)"
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
        guard let destination = TransferLocation.from(pane: targetPane, subfolder: targetSubfolder?.isDirectory == true ? targetSubfolder : nil) else { return }
        let source: TransferLocation
        if sourceIsRemote, let conn = sourceConn {
            source = .remote(conn, password: sourcePwd, path: "/")
        } else {
            source = .local(items.first?.url.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser)
        }
        // Drag & drop copies; a move is an explicit F6 / Cut+Paste.
        TransferCoordinator.shared.start(TransferRequest(items: items, source: source, destination: destination, mode: .copy)) {
            completion()
        }
    }
}
