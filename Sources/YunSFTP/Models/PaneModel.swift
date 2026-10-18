import Foundation
import SwiftUI
import Combine

public enum SortField: String, CaseIterable, Identifiable, Codable, Sendable {
    case name = "Name"
    case size = "Size"
    case date = "Date Modified"
    case kind = "Kind"

    public var id: String { rawValue }
}

public enum ViewMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case list = "List"
    case grid = "Icons"

    public var id: String { rawValue }
}

@MainActor
public class PaneModel: ObservableObject, Identifiable {
    public let id = UUID()

    @Published public var currentURL: URL
    @Published public var items: [FileItem] = []
    @Published public var selectedItemURLs: Set<URL> = []
    @Published public var focusedItemURL: URL? = nil
    public var selectionAnchorURL: URL? = nil
    public var pinnedSelectionURLs: Set<URL> = []
    @Published public var sortField: SortField = .date
    @Published public var sortAscending: Bool = false
    @Published public var showHiddenFiles: Bool = false
    @Published public var viewMode: ViewMode = .list
    @Published public var searchQuery: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var isConnecting: Bool = false
    @Published public var connectingMessage: String = ""

    @Published public var isRemote: Bool = false
    @Published public var remoteConnection: RemoteConnection? = nil
    @Published public var remotePath: String = "/"
    public var remotePassword: String? = nil

    private var history: [URL] = []
    private var historyIndex: Int = -1

    public var canGoBack: Bool {
        return historyIndex > 0
    }

    public var canGoForward: Bool {
        return historyIndex >= 0 && historyIndex < history.count - 1
    }

    public var canGoUp: Bool {
        if isRemote {
            return remotePath != "/" && !remotePath.isEmpty
        }
        return currentURL.path != "/"
    }

    public init(initialURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.currentURL = initialURL
        let settings = AppSettings.load()
        self.sortField = settings.sortField
        self.sortAscending = settings.sortAscending
        self.viewMode = settings.viewMode
        navigateTo(initialURL, addToHistory: true)
    }

    public func connectRemote(connection: RemoteConnection, password: String? = nil) {
        self.isRemote = true
        self.remoteConnection = connection
        self.remotePassword = password ?? (connection.authType == .password ? KeychainService.shared.loadPassword(for: connection) : nil)
        let path = SFTPService.normalizeRemotePath(connection.remotePath)
        self.remotePath = path
        let virtualURL = SFTPService.sftpURL(host: connection.host, port: connection.port, path: path)
        self.currentURL = virtualURL
        self.items.removeAll() // Clear old lingering items immediately (잔상 제거)
        self.selectedItemURLs.removeAll()
        self.pinnedSelectionURLs.removeAll()
        self.selectionAnchorURL = nil
        self.focusedItemURL = nil
        self.searchQuery = ""
        self.history = [virtualURL]
        self.historyIndex = 0
        self.isConnecting = true
        self.isLoading = true
        self.errorMessage = nil
        self.connectingMessage = "'\(connection.displayTitle)' 서버에 연결 중..."
        loadItems()
    }

    public func disconnectRemote() {
        self.isRemote = false
        self.remoteConnection = nil
        self.remotePassword = nil
        self.remotePath = "/"
        self.isConnecting = false
        self.connectingMessage = ""
        self.errorMessage = nil
        navigateTo(FileManager.default.homeDirectoryForCurrentUser, addToHistory: true)
    }

    public func navigateToRemote(path: String, addToHistory: Bool = true) {
        guard let conn = remoteConnection else { return }
        let cleanPath = SFTPService.normalizeRemotePath(path)
        self.remotePath = cleanPath
        let virtualURL = SFTPService.sftpURL(host: conn.host, port: conn.port, path: cleanPath)
        self.currentURL = virtualURL
        self.items.removeAll() // Clear old directory items so they don't linger
        self.selectedItemURLs.removeAll()
        self.pinnedSelectionURLs.removeAll()
        self.selectionAnchorURL = nil
        self.focusedItemURL = nil
        self.searchQuery = ""
        self.isLoading = true
        self.errorMessage = nil

        if addToHistory {
            if historyIndex >= 0 && historyIndex < history.count - 1 {
                history.removeSubrange((historyIndex + 1)..<history.count)
            }
            history.append(virtualURL)
            historyIndex = history.count - 1
        }

        loadItems()
    }

    public func navigateTo(_ url: URL, addToHistory: Bool = true) {
        if isRemote || url.scheme == "sftp" {
            let path = url.path.isEmpty ? "/" : url.path
            navigateToRemote(path: path.precomposedStringWithCanonicalMapping, addToHistory: addToHistory)
            return
        }

        let targetURL = url.standardized
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        self.currentURL = targetURL
        self.selectedItemURLs.removeAll()
        self.pinnedSelectionURLs.removeAll()
        self.selectionAnchorURL = nil
        self.focusedItemURL = nil
        self.searchQuery = ""

        if addToHistory {
            if historyIndex >= 0 && historyIndex < history.count - 1 {
                history.removeSubrange((historyIndex + 1)..<history.count)
            }
            history.append(targetURL)
            historyIndex = history.count - 1
        }

        loadItems()
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        let prevURL = history[historyIndex]
        navigateTo(prevURL, addToHistory: false)
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        let nextURL = history[historyIndex]
        navigateTo(nextURL, addToHistory: false)
    }

    public func goUp() {
        if isRemote {
            guard remotePath != "/" && !remotePath.isEmpty else { return }
            let nfcPath = remotePath.precomposedStringWithCanonicalMapping
            let parent = (nfcPath as NSString).deletingLastPathComponent
            let target = parent.isEmpty ? "/" : parent
            navigateToRemote(path: target)
            return
        }

        let parentURL = currentURL.deletingLastPathComponent()
        if parentURL != currentURL {
            navigateTo(parentURL)
        }
    }

    public func reload(preserveError: Bool = false) {
        loadItems(preserveError: preserveError)
    }

    public func pruneStaleSelections() {
        let validURLs = Set(self.items.map { $0.url })
        self.selectedItemURLs.formIntersection(validURLs)
        self.pinnedSelectionURLs.formIntersection(validURLs)
        if let f = self.focusedItemURL, !validURLs.contains(f) {
            self.focusedItemURL = nil
        }
        if let a = self.selectionAnchorURL, !validURLs.contains(a) {
            self.selectionAnchorURL = nil
        }
    }

    public func loadItems(preserveError: Bool = false) {
        if isRemote {
            loadRemoteItems(preserveError: preserveError)
            return
        }

        isLoading = true
        if !preserveError {
            errorMessage = nil
        }
        let targetURL = self.currentURL

        Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            do {
                let fileURLs = try fileManager.contentsOfDirectory(
                    at: targetURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isPackageKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                        .contentModificationDateKey,
                        .creationDateKey,
                        .localizedTypeDescriptionKey,
                        .isHiddenKey
                    ],
                    options: [.skipsSubdirectoryDescendants]
                )

                let loadedItems = fileURLs.map { FileItem(url: $0) }

                await MainActor.run {
                    if self.currentURL == targetURL {
                        self.items = loadedItems
                        self.pruneStaleSelections()
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    if self.currentURL == targetURL {
                        self.items = []
                        self.pruneStaleSelections()
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func loadRemoteItems(preserveError: Bool = false) {
        guard let conn = remoteConnection else { return }
        isLoading = true
        if !preserveError {
            errorMessage = nil
        }
        let cleanPath = SFTPService.normalizeRemotePath(remotePath)
        let pwd = remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)

        Task {
            do {
                let remoteItems = try await SFTPService.shared.listDirectory(path: cleanPath, connection: conn, password: pwd)
                let mapped = remoteItems.map { $0.toFileItem(connection: conn) }
                await MainActor.run {
                    if self.isRemote && SFTPService.normalizeRemotePath(self.remotePath) == cleanPath {
                        self.items = mapped
                        self.pruneStaleSelections()
                        self.isLoading = false
                        self.isConnecting = false
                        self.connectingMessage = ""
                    }
                }
            } catch {
                await MainActor.run {
                    if self.isRemote {
                        self.items = []
                        self.pruneStaleSelections()
                        self.isLoading = false
                        self.isConnecting = false
                        self.connectingMessage = ""
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    public var displayedItems: [FileItem] {
        var result = items

        // Filter hidden files
        if !showHiddenFiles {
            result = result.filter { !$0.isHidden }
        }

        // Filter search query
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { $0.name.lowercased().contains(q) }
        }

        // Sort items: folders first, then according to sortField
        result.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }

            let comparison: ComparisonResult
            switch sortField {
            case .name:
                comparison = a.name.localizedStandardCompare(b.name)
            case .size:
                if a.size == b.size {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.size < b.size ? .orderedAscending : .orderedDescending
                }
            case .date:
                comparison = a.modificationDate.compare(b.modificationDate)
            case .kind:
                if a.kindDescription == b.kindDescription {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.kindDescription.localizedStandardCompare(b.kindDescription)
                }
            }

            return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        }

        return result
    }

    public var selectedItems: [FileItem] {
        return items.filter { selectedItemURLs.contains($0.url) }
    }

    public var effectiveSelectedItems: [FileItem] {
        let sel = selectedItems
        if !sel.isEmpty { return sel }
        if let focused = focusedItemURL, let item = items.first(where: { $0.url == focused }) {
            return [item]
        }
        return []
    }

    public var firstSelectedItem: FileItem? {
        if let first = selectedItems.first {
            return first
        }
        if let focused = focusedItemURL, let item = items.first(where: { $0.url == focused }) {
            return item
        }
        return nil
    }

    public func selectAll() {
        let all = Set(displayedItems.map { $0.url })
        selectedItemURLs = all
        pinnedSelectionURLs = all
    }

    public func deselectAll() {
        selectedItemURLs.removeAll()
        pinnedSelectionURLs.removeAll()
        selectionAnchorURL = focusedItemURL
    }

    public func toggleSelection(_ itemURL: URL) {
        if selectedItemURLs.contains(itemURL) {
            selectedItemURLs.remove(itemURL)
            pinnedSelectionURLs.remove(itemURL)
        } else {
            pinnedSelectionURLs = selectedItemURLs
            pinnedSelectionURLs.insert(itemURL)
            selectedItemURLs.insert(itemURL)
        }
        focusedItemURL = itemURL
        selectionAnchorURL = itemURL
    }

    /// Toggles selection ON/OFF on the currently focused item when pressing Space.
    /// Allows moving the cursor with Up/Down arrows and pressing Space to select/deselect multiple individual files.
    public func toggleSelectionAtFocus() {
        let list = displayedItems
        guard !list.isEmpty else { return }

        let targetURL = focusedItemURL ?? selectedItemURLs.first ?? list[0].url
        focusedItemURL = targetURL
        selectionAnchorURL = targetURL

        if selectedItemURLs.contains(targetURL) {
            pinnedSelectionURLs = selectedItemURLs
            pinnedSelectionURLs.remove(targetURL)
            selectedItemURLs.remove(targetURL)
        } else {
            pinnedSelectionURLs.insert(targetURL)
            selectedItemURLs.insert(targetURL)
        }
    }

    public func selectSingle(_ itemURL: URL) {
        selectedItemURLs = [itemURL]
        pinnedSelectionURLs.removeAll()
        focusedItemURL = itemURL
        selectionAnchorURL = itemURL
    }

    /// Selects the contiguous range from `selectionAnchorURL` to `targetURL`, contracting any previously extended items outside the range.
    public func selectRange(to targetURL: URL) {
        let list = displayedItems
        guard !list.isEmpty else { return }

        let anchorURL = selectionAnchorURL ?? focusedItemURL ?? selectedItemURLs.first ?? targetURL
        selectionAnchorURL = anchorURL
        focusedItemURL = targetURL

        if let idx1 = list.firstIndex(where: { $0.url == anchorURL }),
           let idx2 = list.firstIndex(where: { $0.url == targetURL }) {
            let lower = min(idx1, idx2)
            let upper = max(idx1, idx2)
            let rangeSet = Set(list[lower...upper].map { $0.url })
            selectedItemURLs = pinnedSelectionURLs.union(rangeSet)
        } else {
            selectedItemURLs = pinnedSelectionURLs.union([targetURL])
        }
    }

    public func selectNext(extendSelection: Bool = false) {
        let list = displayedItems
        guard !list.isEmpty else { return }

        let currentURL = focusedItemURL ?? selectedItemURLs.first
        if let currentURL = currentURL, let idx = list.firstIndex(where: { $0.url == currentURL }) {
            let nextIdx = min(idx + 1, list.count - 1)
            let nextItem = list[nextIdx]
            if extendSelection {
                if selectionAnchorURL == nil {
                    selectionAnchorURL = currentURL
                }
                selectRange(to: nextItem.url)
            } else {
                focusedItemURL = nextItem.url
                selectionAnchorURL = nextItem.url
                selectedItemURLs = pinnedSelectionURLs
            }
        } else if let first = list.first {
            focusedItemURL = first.url
            selectionAnchorURL = first.url
            if extendSelection {
                selectedItemURLs = pinnedSelectionURLs.union([first.url])
            } else {
                selectedItemURLs = pinnedSelectionURLs
            }
        }
    }

    public func selectPrevious(extendSelection: Bool = false) {
        let list = displayedItems
        guard !list.isEmpty else { return }

        let currentURL = focusedItemURL ?? selectedItemURLs.first
        if let currentURL = currentURL, let idx = list.firstIndex(where: { $0.url == currentURL }) {
            let prevIdx = max(idx - 1, 0)
            let prevItem = list[prevIdx]
            if extendSelection {
                if selectionAnchorURL == nil {
                    selectionAnchorURL = currentURL
                }
                selectRange(to: prevItem.url)
            } else {
                focusedItemURL = prevItem.url
                selectionAnchorURL = prevItem.url
                selectedItemURLs = pinnedSelectionURLs
            }
        } else if let last = list.last {
            focusedItemURL = last.url
            selectionAnchorURL = last.url
            if extendSelection {
                selectedItemURLs = pinnedSelectionURLs.union([last.url])
            } else {
                selectedItemURLs = pinnedSelectionURLs
            }
        }
    }

    public func selectFirst(extendSelection: Bool = false) {
        guard let first = displayedItems.first else { return }
        if extendSelection {
            selectRange(to: first.url)
        } else {
            focusedItemURL = first.url
            selectionAnchorURL = first.url
            selectedItemURLs = pinnedSelectionURLs
        }
    }

    public func selectLast(extendSelection: Bool = false) {
        guard let last = displayedItems.last else { return }
        if extendSelection {
            selectRange(to: last.url)
        } else {
            focusedItemURL = last.url
            selectionAnchorURL = last.url
            selectedItemURLs = pinnedSelectionURLs
        }
    }

    public func selectMatchingPrefix(_ prefix: String) {
        guard !prefix.isEmpty else { return }
        let lower = prefix.lowercased()
        if let match = displayedItems.first(where: { $0.name.lowercased().hasPrefix(lower) }) {
            focusedItemURL = match.url
            selectionAnchorURL = match.url
            selectedItemURLs = pinnedSelectionURLs
        }
    }

    public var statusDescription: String {
        let totalCount = displayedItems.count
        let selCount = selectedItemURLs.count

        if selCount > 0 {
            let selBytes = selectedItems.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size }
            let formattedSelBytes = ByteCountFormatter.string(fromByteCount: selBytes, countStyle: .file)
            return "\(selCount) of \(totalCount) selected (\(formattedSelBytes))"
        } else {
            return "\(totalCount) items"
        }
    }

    public var freeDiskSpaceDescription: String {
        if isRemote {
            return remoteConnection?.displayTitle ?? "Remote Server"
        }
        guard let values = try? currentURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file) + " available"
    }
}
