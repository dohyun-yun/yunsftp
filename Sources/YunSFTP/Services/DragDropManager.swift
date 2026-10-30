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

    /// Private pasteboard type that marks providers created by this app's own drags. Finder never
    /// supplies it, so its presence on a drop is what makes the drop "internal".
    nonisolated public static let sessionMarkerType = "com.finsternis.yunsftp.drag-session"

    /// Identifies the current drag; a provider created for it keeps a token whose release (the
    /// drag session is over, wherever it ended) clears the cached items of *this* session only.
    public private(set) var currentSession: UUID? = nil

    @discardableResult
    public func startDrag(items: [FileItem], from pane: PaneModel) -> UUID {
        let session = UUID()
        self.currentSession = session
        self.draggedItems = items
        self.sourcePaneId = pane.id
        self.sourceIsRemote = pane.isRemote
        self.sourceConnection = pane.remoteConnection
        self.sourceRemotePassword = pane.remotePassword
        return session
    }

    /// Provider for a local item: the file URL plus the session marker.
    public func makeProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        Self.attachSessionMarker(to: provider, session: currentSession)
        return provider
    }

    /// Released together with the provider, i.e. when AppKit is done with the drag session.
    final class SessionToken: @unchecked Sendable {
        let session: UUID?
        init(_ session: UUID?) { self.session = session }
        deinit {
            guard let session else { return }
            Task { @MainActor in DragDropManager.shared.endDrag(session: session) }
        }
    }

    nonisolated public static func attachSessionMarker(to provider: NSItemProvider, session: UUID? = nil) {
        let token = SessionToken(session)
        provider.registerDataRepresentation(forTypeIdentifier: sessionMarkerType, visibility: .ownProcess) { completion in
            _ = token      // keeps the token alive exactly as long as the provider
            completion(Data("1".utf8), nil)
            return nil
        }
    }

    /// Ends the drag only if it is still the given session (a newer drag must not be cleared).
    public func endDrag(session: UUID) {
        guard currentSession == session else { return }
        endDrag()
    }

    nonisolated public static func isInternalDrop(providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(sessionMarkerType) }
    }

    public func endDrag() {
        self.currentSession = nil
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
        // Our own drags mark their providers; a drop that carries the marker transfers the whole
        // dragged selection (SwiftUI only hands over the row under the cursor). Anything else is an
        // external drop, and whatever was cached belonged to a drag that ended in another app.
        if !draggedItems.isEmpty && (externalProviders.isEmpty || Self.isInternalDrop(providers: externalProviders)) {
            let items = self.draggedItems
            let srcRemote = self.sourceIsRemote
            let srcConn = self.sourceConnection
            let srcPwd = self.sourceRemotePassword
            self.endDrag()
            executeTransfer(items: items, sourceIsRemote: srcRemote, sourceConn: srcConn, sourcePwd: srcPwd,
                            targetPane: targetPane, targetSubfolder: targetSubfolder, completion: completion)
            return
        }
        endDrag()
        guard !externalProviders.isEmpty else { return }

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
