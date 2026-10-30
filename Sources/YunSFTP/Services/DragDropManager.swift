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
