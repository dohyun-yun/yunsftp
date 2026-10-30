import Foundation
import Combine

public enum PaneSide: Sendable { case left, right }

/// The tabs of one pane side. `current` is what the rest of the UI treats as "the pane".
@MainActor
public final class PaneStack: ObservableObject {
    @Published public private(set) var tabs: [PaneModel]
    @Published public private(set) var selectedIndex: Int = 0
    private var forwarders: [UUID: AnyCancellable] = [:]

    public init(initial: PaneModel) {
        tabs = [initial]
        forward(initial)
    }

    public var current: PaneModel { tabs[min(selectedIndex, tabs.count - 1)] }

    /// Changes inside the current tab must re-render owners that only observe the stack.
    private func forward(_ pane: PaneModel) {
        forwarders[pane.id] = pane.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Opens a tab at the same place as the current one (same server folder, or same local folder).
    @discardableResult
    public func newTab() -> PaneModel {
        let source = current
        let pane: PaneModel
        if source.isRemote, let conn = source.remoteConnection {
            pane = PaneModel(initialURL: FileManager.default.homeDirectoryForCurrentUser, autoLoad: false)
            var target = conn
            target.remotePath = source.remotePath
            pane.connectRemote(connection: target, password: source.remotePassword)
        } else {
            pane = PaneModel(initialURL: source.currentURL)
        }
        pane.showHiddenFiles = source.showHiddenFiles
        pane.viewMode = source.viewMode
        tabs.insert(pane, at: selectedIndex + 1)
        forward(pane)
        selectedIndex += 1
        return pane
    }

    /// Closes a tab; the last tab stays open.
    public func close(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        let removed = tabs.remove(at: index)
        forwarders[removed.id] = nil
        if selectedIndex >= tabs.count { selectedIndex = tabs.count - 1 }
        else if index < selectedIndex { selectedIndex -= 1 }
    }

    public func closeCurrent() { close(at: selectedIndex) }

    public func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
    }

    public func selectNext() { selectedIndex = (selectedIndex + 1) % tabs.count }
    public func selectPrevious() { selectedIndex = (selectedIndex - 1 + tabs.count) % tabs.count }

    public static func title(for pane: PaneModel) -> String {
        if pane.isRemote, let conn = pane.remoteConnection {
            let folder = (pane.remotePath as NSString).lastPathComponent
            return folder.isEmpty || pane.remotePath == "/" ? conn.displayTitle : "\(conn.displayTitle): \(folder)"
        }
        let name = pane.currentURL.lastPathComponent
        return name.isEmpty ? "/" : name
    }

    /// Every remote connection open in any tab (for the sidebar status dots).
    public var connectedConnectionIDs: Set<UUID> {
        Set(tabs.compactMap { $0.isRemote ? $0.remoteConnection?.id : nil })
    }
}
