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

        guard !itemsToPaste.isEmpty, let destination = TransferLocation.from(pane: targetPane) else { return }

        let wasCut = self.isCut
        let source: TransferLocation
        if sourceIsRemote, let conn = sourceConnection {
            source = .remote(conn, password: sourceRemotePassword, path: "/")
        } else {
            source = .local(itemsToPaste.first?.url.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser)
        }
        if wasCut {
            self.clear()
        }

        TransferCoordinator.shared.start(TransferRequest(items: itemsToPaste, source: source, destination: destination, mode: wasCut ? .move : .copy)) {
            reloadPanes()
        }
    }
}
