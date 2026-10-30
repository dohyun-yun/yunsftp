import SwiftUI
import AppKit

public struct MainWindowView: View {
    @StateObject private var leftPane: PaneModel
    @StateObject private var rightPane: PaneModel

    @State private var activePaneId: UUID
    @State private var isDualPane: Bool = true
    @State private var customFavorites: [FavoriteLocation]

    public init(leftPane: PaneModel? = nil, rightPane: PaneModel? = nil, customFavorites: [FavoriteLocation]? = nil) {
        let lp = leftPane ?? PaneModel()
        let rp = rightPane ?? PaneModel(initialURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
        _leftPane = StateObject(wrappedValue: lp)
        _rightPane = StateObject(wrappedValue: rp)
        _activePaneId = State(initialValue: lp.id)
        _customFavorites = State(initialValue: customFavorites ?? [])
    }

    @Environment(\.undoManager) private var undoManager

    // Sheet states
    @State private var previewItem: FileItem? = nil
    @State private var infoItem: FileItem? = nil
    @State private var chmodItem: FileItem? = nil
    @State private var renameTargetItem: FileItem? = nil
    @State private var showNewFolderPrompt: Bool = false
    @State private var showConnectSheet: Bool = false
    @State private var connectSheetInitialConn: RemoteConnection? = nil
    @State private var connectSheetIsEditMode: Bool = false
    @State private var connectSheetAutoRunTest: Bool = false
    @State private var showCompareSyncSheet: Bool = false
    @State private var showBatchRenameSheet: Bool = false

    private var activePane: PaneModel {
        if activePaneId == rightPane.id && isDualPane {
            return rightPane
        } else {
            return leftPane
        }
    }

    private var otherPane: PaneModel {
        if activePaneId == rightPane.id && isDualPane {
            return leftPane
        } else {
            return rightPane
        }
    }

    private var hasActiveModal: Bool {
        showConnectSheet || showCompareSyncSheet || showBatchRenameSheet || showNewFolderPrompt || renameTargetItem != nil || chmodItem != nil || previewItem != nil || infoItem != nil
    }

    private var connectedConnectionIds: Set<UUID> {
        var ids = Set<UUID>()
        if leftPane.isRemote, let id = leftPane.remoteConnection?.id { ids.insert(id) }
        if rightPane.isRemote, let id = rightPane.remoteConnection?.id { ids.insert(id) }
        return ids
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                customFavorites: $customFavorites,
                connectedConnectionIds: connectedConnectionIds,
                onSelectLocation: { targetURL in
                    activePane.navigateTo(targetURL)
                },
                onOpenConnection: { conn in
                    let pwd = KeychainService.shared.loadPassword(for: conn)
                    if conn.authType == .password && (pwd == nil || pwd!.isEmpty) {
                        connectSheetInitialConn = conn
                        connectSheetIsEditMode = false
                        connectSheetAutoRunTest = false
                        showConnectSheet = true
                    } else {
                        activePane.connectRemote(connection: conn, password: pwd)
                    }
                },
                onEditConnection: { conn in
                    connectSheetInitialConn = conn
                    connectSheetIsEditMode = true
                    connectSheetAutoRunTest = false
                    showConnectSheet = true
                },
                onTestConnection: { conn in
                    connectSheetInitialConn = conn
                    connectSheetIsEditMode = true
                    connectSheetAutoRunTest = true
                    showConnectSheet = true
                },
                onManageConnections: {
                    connectSheetInitialConn = nil
                    connectSheetIsEditMode = false
                    connectSheetAutoRunTest = false
                    showConnectSheet = true
                },
                onOpenRemotePath: { conn, path in
                    openRemotePath(conn, path: path)
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 340)
        } detail: {
            VStack(spacing: 0) {
                // Top Transfer Progress & Status Banner
                TransferStatusBarView()

                DualPaneView(
                    leftPane: leftPane,
                    rightPane: rightPane,
                    isDualPane: $isDualPane,
                    activePaneId: $activePaneId,
                    onOpenItem: { item in
                        if activePane.isRemote {
                            downloadAndOpenRemoteItem(item)
                        } else {
                            TerminalService.openItem(url: item.url)
                        }
                    },
                    onShowInfo: { item in
                        infoItem = item
                    },
                    onQuickLook: { item in
                        previewItem = item
                    },
                    onRename: { item in
                        renameTargetItem = item
                    },
                    onChmod: { item in
                        chmodItem = item
                    },
                    onCopyToOtherPane: {
                        copySelectedToOtherPane()
                    },
                    onMoveToOtherPane: {
                        moveSelectedToOtherPane()
                    },
                    onTrashItems: { items in
                        trashItems(items)
                    },
                    onCompressItems: { items in
                        compressItems(items)
                    },
                    onExtractArchive: { item in
                        extractArchive(item)
                    },
                    onConnect: {
                        connectSheetInitialConn = nil
                        showConnectSheet = true
                    }
                )
            }
            .toolbar(id: "yunsftp.main") {
                ToolbarView(
                    isDualPane: $isDualPane,
                    onToggleDualPane: {
                        isDualPane.toggle()
                        if !isDualPane {
                            activePaneId = leftPane.id
                        }
                    },
                    onConnect: {
                        connectSheetInitialConn = nil
                        showConnectSheet = true
                    },
                    onCopyToOtherPane: { copySelectedToOtherPane() },
                    onMoveToOtherPane: { moveSelectedToOtherPane() },
                    onRefresh: { activePane.reload() },
                    onNewFolder: {
                        showNewFolderPrompt = true
                    },
                    onDelete: {
                        trashItems(activePane.effectiveSelectedItems)
                    },
                    onChmod: {
                        if let first = activePane.firstSelectedItem {
                            chmodItem = first
                        }
                    },
                    onQuickLook: {
                        if let first = activePane.firstSelectedItem {
                            previewItem = first
                        }
                    },
                    onBatchRename: {
                        if !activePane.effectiveSelectedItems.isEmpty {
                            showBatchRenameSheet = true
                        }
                    },
                    onCompareSync: {
                        showCompareSyncSheet = true
                    },
                    onOpenTerminal: {
                        TerminalService.openInTerminal(at: activePane.currentURL)
                    },
                    onGetInfo: {
                        if let first = activePane.firstSelectedItem {
                            infoItem = first
                        }
                    }
                )
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .onAppear {
            let left = leftPane, right = rightPane
            TransferCoordinator.shared.localMoveRecorder = { [undoManager] actionName, moves in
                LocalUndo.register(undoManager, actionName: actionName) {
                    for m in moves.reversed() {
                        _ = try await FileSystemService.shared.move(urls: [m.to], to: m.from.deletingLastPathComponent())
                    }
                    await MainActor.run { left.reload(); right.reload() }
                }
            }
            activePaneId = leftPane.id
            if !DemoHelper.isDemoMode {
                // Load and migrate ForkLift 2 favorites
                let result = MigrationService.shared.migrateFromForkLift2()
                for fav in result.importedFavorites {
                    if !customFavorites.contains(where: { $0.url == fav.url }) {
                        customFavorites.append(fav)
                    }
                }
            }
        }
        // Sheets
        .sheet(item: $previewItem) { item in
            FilePreviewSheet(item: item, pane: activePane)
        }
        .sheet(item: $infoItem) { item in
            FileInfoSheet(item: item, pane: activePane)
        }
        .sheet(item: $chmodItem) { item in
            ChmodSheet(item: item) { mode, recursive in
                applyChmod(item: item, mode: mode, recursive: recursive)
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectSheet(
                initialConnection: connectSheetInitialConn,
                isEditMode: connectSheetIsEditMode,
                autoRunTest: connectSheetAutoRunTest
            ) { conn, password in
                activePane.connectRemote(connection: conn, password: password)
            }
        }
        .sheet(isPresented: $showCompareSyncSheet) {
            CompareSyncSheet(leftPane: leftPane, rightPane: rightPane)
        }
        .sheet(isPresented: $showBatchRenameSheet) {
            BatchRenameSheet(items: activePane.effectiveSelectedItems, pane: activePane) {
                activePane.reload()
            }
        }
        .sheet(isPresented: $showNewFolderPrompt) {
            NewFolderSheet(defaultName: "New Folder") { folderName in
                createNewFolder(named: folderName)
            }
        }
        .sheet(item: $renameTargetItem) { item in
            RenameSheet(item: item) { newName in
                performRename(item: item, to: newName)
            }
        }
        // Keyboard Shortcuts
        .background(
            KeyboardShortcutHelper(
                isEnabled: !hasActiveModal,
                onTab: {
                    if isDualPane {
                        activePaneId = (activePaneId == leftPane.id) ? rightPane.id : leftPane.id
                    }
                },
                onSpace: {
                    activePane.toggleSelectionAtFocus()
                },
                onEscape: {
                    if activePane.shouldShowFilter {
                        activePane.toggleFilter()
                    } else {
                        leftPane.clearSelection()
                        rightPane.clearSelection()
                    }
                },
                onQuickLook: {
                    if let first = activePane.firstSelectedItem {
                        previewItem = first
                    }
                },
                onConnect: {
                    connectSheetInitialConn = nil
                    connectSheetIsEditMode = false
                    connectSheetAutoRunTest = false
                    showConnectSheet = true
                },
                onCopy: {
                    ClipboardService.shared.copy(items: activePane.effectiveSelectedItems, from: activePane)
                },
                onCut: {
                    ClipboardService.shared.cut(items: activePane.effectiveSelectedItems, from: activePane)
                },
                onPaste: {
                    ClipboardService.shared.paste(to: activePane) {
                        leftPane.reload()
                        rightPane.reload()
                    }
                },
                onRefresh: {
                    activePane.reload()
                },
                onF5: { copySelectedToOtherPane() },
                onF6: { moveSelectedToOtherPane() },
                onDelete: { trashItems(activePane.effectiveSelectedItems) },
                onNewFolder: {
                    showNewFolderPrompt = true
                },
                onSelectAll: { activePane.selectAll() },
                onDownArrow: { isShift in activePane.selectNext(extendSelection: isShift) },
                onUpArrow: { isShift in activePane.selectPrevious(extendSelection: isShift) },
                onReturn: {
                    if let item = activePane.firstSelectedItem {
                        renameTargetItem = item
                    }
                },
                onCmdDown: { openOrNavigateActiveItem() },
                onCmdO: { openOrNavigateActiveItem() },
                onCmdUp: { activePane.goUp() },
                onBackspace: { activePane.goUp() },
                onHome: { isShift in activePane.selectFirst(extendSelection: isShift) },
                onEnd: { isShift in activePane.selectLast(extendSelection: isShift) },
                onGetInfo: {
                    if let first = activePane.firstSelectedItem {
                        infoItem = first
                    }
                },
                onDuplicate: {
                    duplicateSelectedItems()
                },
                onGoBack: {
                    activePane.goBack()
                },
                onGoForward: {
                    activePane.goForward()
                },
                onToggleHidden: {
                    activePane.showHiddenFiles.toggle()
                },
                onToggleFilter: {
                    activePane.toggleFilter()
                },
                onGoToPath: {
                    activePane.pathEditRequest += 1
                },
                onTypeChar: { char in activePane.selectMatchingPrefix(char) }
            )
        )
    }

    private func createNewFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let targetPane = activePane
        if targetPane.isRemote {
            guard let conn = targetPane.remoteConnection else { return }
            let pwd = targetPane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            let nfcCurrent = SFTPService.normalizeRemotePath(targetPane.remotePath)
            let nfcName = name.precomposedStringWithCanonicalMapping
            let path = (nfcCurrent == "/" ? "/\(nfcName)" : "\(nfcCurrent)/\(nfcName)").precomposedStringWithCanonicalMapping
            Task {
                do {
                    try await SFTPService.shared.createDirectory(remotePath: path, connection: conn, password: pwd)
                    await MainActor.run {
                        targetPane.reload()
                    }
                } catch {
                    await MainActor.run {
                        targetPane.errorMessage = "Create folder failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            Task {
                do {
                    _ = try await FileSystemService.shared.createFolder(at: targetPane.currentURL, name: name)
                    await MainActor.run {
                        targetPane.reload()
                    }
                } catch {
                    await MainActor.run {
                        targetPane.errorMessage = "Create folder failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func performRename(item: FileItem, to rawNewName: String) {
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !newName.isEmpty, newName != item.name.precomposedStringWithCanonicalMapping else { return }
        let targetPane = activePane
        if targetPane.isRemote {
            guard let conn = targetPane.remoteConnection else { return }
            let pwd = targetPane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            let oldPath = SFTPService.normalizeRemotePath(item.url.path)
            let parent = (oldPath as NSString).deletingLastPathComponent
            let newPath = (parent == "/" || parent.isEmpty ? "/\(newName)" : "\(parent)/\(newName)").precomposedStringWithCanonicalMapping
            Task {
                do {
                    try await SFTPService.shared.rename(remotePath: oldPath, to: newPath, connection: conn, password: pwd)
                    await MainActor.run {
                        targetPane.reload()
                    }
                } catch {
                    await MainActor.run {
                        targetPane.errorMessage = "Rename failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            Task {
                do {
                    let newURL = try await FileSystemService.shared.rename(url: item.url, to: newName)
                    let oldName = item.name
                    await MainActor.run {
                        LocalUndo.register(undoManager, actionName: "Rename") {
                            _ = try await FileSystemService.shared.rename(url: newURL, to: oldName)
                            await MainActor.run { targetPane.reload() }
                        }
                        targetPane.selectedItemURLs = [newURL]
                        targetPane.focusedItemURL = newURL
                        targetPane.reload()
                    }
                } catch {
                    await MainActor.run {
                        targetPane.errorMessage = "Rename failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func duplicateSelectedItems() {
        let targets = activePane.effectiveSelectedItems
        guard !targets.isEmpty else { return }
        let targetPane = activePane

        if targetPane.isRemote {
            guard let conn = targetPane.remoteConnection else { return }
            let pwd = targetPane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            Task {
                for item in targets {
                    let remotePath = SFTPService.normalizeRemotePath(item.url.path)
                    do {
                        _ = try await SFTPService.shared.duplicate(remotePath: remotePath, isDirectory: item.isDirectory, connection: conn, password: pwd)
                    } catch {
                        await MainActor.run {
                            targetPane.errorMessage = "Duplicate failed: \(error.localizedDescription)"
                        }
                    }
                }
                await MainActor.run {
                    targetPane.reload(preserveError: true)
                }
            }
        } else {
            Task {
                for item in targets {
                    do {
                        _ = try await FileSystemService.shared.duplicate(url: item.url)
                    } catch {
                        await MainActor.run {
                            targetPane.errorMessage = "Duplicate failed: \(error.localizedDescription)"
                        }
                    }
                }
                await MainActor.run {
                    targetPane.reload(preserveError: true)
                }
            }
        }
    }

    private func applyChmod(item: FileItem, mode: String, recursive: Bool) {
        let targetPane = activePane
        if targetPane.isRemote {
            guard let conn = targetPane.remoteConnection else { return }
            let pwd = targetPane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            let path = SFTPService.normalizeRemotePath(item.url.path)
            Task {
                do {
                    try await SFTPService.shared.chmod(remotePath: path, mode: mode, recursive: recursive, connection: conn, password: pwd)
                    await MainActor.run { targetPane.reload() }
                } catch {
                    await MainActor.run {
                        targetPane.errorMessage = "Permission change failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            if let octalInt = Int(mode, radix: 8) {
                Task {
                    do {
                        try await FileSystemService.shared.chmod(url: item.url, posixPermissions: octalInt)
                        await MainActor.run { targetPane.reload() }
                    } catch {
                        await MainActor.run {
                            targetPane.errorMessage = "Permission change failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    /// Bookmark / recent folder: navigate if already on that server, otherwise connect straight there.
    private func openRemotePath(_ conn: RemoteConnection, path: String) {
        if activePane.isRemote, activePane.remoteConnection?.id == conn.id {
            activePane.navigateToRemote(path: path)
            return
        }
        var target = conn
        target.remotePath = path
        let pwd = KeychainService.shared.loadPassword(for: conn)
        if conn.authType == .password && (pwd == nil || pwd!.isEmpty) {
            connectSheetInitialConn = target
            connectSheetIsEditMode = false
            connectSheetAutoRunTest = false
            showConnectSheet = true
        } else {
            activePane.connectRemote(connection: target, password: pwd)
        }
    }

    private func downloadAndOpenRemoteItem(_ item: FileItem) {
        guard let conn = activePane.remoteConnection else { return }
        let pwd = activePane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let remotePath = SFTPService.normalizeRemotePath(item.url.path)
        let size = item.size
        let name = item.name
        TransferCoordinator.shared.runAdHoc(fileName: name, direction: .download, totalBytes: size) { taskID in
            await TransferManager.shared.updateProgress(id: taskID, progress: 0.2, bytesTransferred: 0, totalBytes: size, message: "Downloading \(name)...")
            let localURL = try await SFTPService.shared.download(remotePath: remotePath, to: tempDir, connection: conn, password: pwd, overwrite: true)
            await MainActor.run { TerminalService.openItem(url: localURL) }
        }
    }

    private func openOrNavigateActiveItem() {
        if let item = activePane.firstSelectedItem {
            if item.isDirectory {
                activePane.navigateTo(item.url)
            } else {
                if activePane.isRemote {
                    downloadAndOpenRemoteItem(item)
                } else {
                    TerminalService.openItem(url: item.url)
                }
            }
        }
    }

    private func copySelectedToOtherPane() {
        transferSelection(mode: .copy)
    }

    private func moveSelectedToOtherPane() {
        transferSelection(mode: .move)
    }

    private func transferSelection(mode: TransferMode) {
        guard isDualPane else { return }
        let selected = activePane.effectiveSelectedItems
        guard !selected.isEmpty,
              let source = TransferLocation.from(pane: activePane),
              let destination = TransferLocation.from(pane: otherPane) else { return }
        let src = activePane, dst = otherPane
        TransferCoordinator.shared.start(TransferRequest(items: selected, source: source, destination: destination, mode: mode)) {
            if mode == .move { src.reload() }
            dst.reload()
        }
    }

    static func remoteDeleteAlertText(itemNames: [String]) -> (title: String, message: String) {
        let title = itemNames.count == 1
            ? "Delete \"\(itemNames[0])\" from the server?"
            : "Delete \(itemNames.count) items from the server?"
        return (title, "Remote files are removed permanently. This cannot be undone.")
    }

    private static func confirmRemoteDelete(itemNames: [String]) -> Bool {
        let text = remoteDeleteAlertText(itemNames: itemNames)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.title
        alert.informativeText = text.message
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func trashItems(_ items: [FileItem]) {
        let targets = !items.isEmpty ? items : activePane.effectiveSelectedItems
        guard !targets.isEmpty else { return }
        let targetPane = activePane
        let transferManager = TransferManager.shared

        if targetPane.isRemote {
            guard let conn = targetPane.remoteConnection else { return }
            // Remote deletion is permanent (no trash), so unlike the local path it needs confirmation.
            if SettingsStore.shared.settings.confirmRemoteDelete {
                guard Self.confirmRemoteDelete(itemNames: targets.map { $0.name }) else { return }
            }
            let pwd = targetPane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            Task {
                var hadError = false
                for item in targets {
                    let remotePath = SFTPService.normalizeRemotePath(item.url.path)
                    let taskId = transferManager.addTransfer(fileName: item.name, direction: .remoteCopy, totalBytes: item.size)
                    await MainActor.run {
                        transferManager.updateProgress(id: taskId, progress: 0.3, bytesTransferred: 0, totalBytes: item.size, message: "Deleting \(item.name)...")
                    }
                    do {
                        try await SFTPService.shared.remove(remotePath: remotePath, isDirectory: item.isDirectory, connection: conn, password: pwd)
                        await MainActor.run {
                            targetPane.items.removeAll { $0.url == item.url }
                            targetPane.selectedItemURLs.remove(item.url)
                            if targetPane.focusedItemURL == item.url {
                                targetPane.focusedItemURL = nil
                            }
                            transferManager.updateProgress(id: taskId, progress: 1.0, bytesTransferred: item.size, totalBytes: item.size, message: "Deleted \(item.name)")
                            transferManager.markCompleted(id: taskId)
                        }
                    } catch {
                        hadError = true
                        await MainActor.run {
                            targetPane.errorMessage = "Delete failed (\(item.name)): \(error.localizedDescription)"
                            transferManager.markFailed(id: taskId, error: error.localizedDescription)
                        }
                    }
                }
                await MainActor.run {
                    targetPane.reload(preserveError: hadError)
                }
            }
            return
        }

        let urls = targets.map { $0.url }
        guard !urls.isEmpty else { return }
        Task {
            do {
                let pairs = try await FileSystemService.shared.moveToTrash(urls: urls)
                await MainActor.run {
                    LocalUndo.register(undoManager, actionName: pairs.count == 1 ? "Move to Trash" : "Move \(pairs.count) Items to Trash") {
                        for pair in pairs { try await FileSystemService.shared.restoreFromTrash(pair) }
                        await MainActor.run { targetPane.reload() }
                    }
                    let deletedSet = Set(urls)
                    targetPane.items.removeAll { deletedSet.contains($0.url) }
                    targetPane.selectedItemURLs.subtract(deletedSet)
                    if let focused = targetPane.focusedItemURL, deletedSet.contains(focused) {
                        targetPane.focusedItemURL = nil
                    }
                    targetPane.reload()
                }
            } catch {
                await MainActor.run {
                    targetPane.errorMessage = "Delete failed: \(error.localizedDescription)"
                    targetPane.reload(preserveError: true)
                }
            }
        }
    }

    private func compressItems(_ items: [FileItem]) {
        let urls = items.map { $0.url }
        guard !urls.isEmpty else { return }
        Task {
            _ = try? await FileSystemService.shared.compress(urls: urls, to: activePane.currentURL)
            activePane.reload()
        }
    }

    private func extractArchive(_ item: FileItem) {
        Task {
            try? await FileSystemService.shared.extract(archiveURL: item.url, to: activePane.currentURL)
            activePane.reload()
        }
    }
}

public struct RenameSheet: View {
    public let item: FileItem
    public var onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String
    @FocusState private var isNameFocused: Bool

    public static let minimumSheetWidth: CGFloat = 560
    public static let maximumSheetWidth: CGFloat = 760

    public static func defaultInitialName(for item: FileItem) -> String {
        SFTPService.decodeLsEscapes(item.name).precomposedStringWithCanonicalMapping
    }

    public static func preferredSheetWidth(for filename: String) -> CGFloat {
        let estimated = CGFloat(filename.count) * 8.5 + 120
        return min(maximumSheetWidth, max(minimumSheetWidth, estimated))
    }

    public init(item: FileItem, onCommit: @escaping (String) -> Void) {
        self.item = item
        self.onCommit = onCommit
        let defaultName = Self.defaultInitialName(for: item)
        self._newName = State(initialValue: defaultName)
    }

    public var body: some View {
        let initialName = Self.defaultInitialName(for: item)
        let targetWidth = Self.preferredSheetWidth(for: max(initialName.count, newName.count) == initialName.count ? initialName : newName)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: FileIconProvider.shared.icon(for: item))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Item")
                        .font(.headline)
                    Text("Original: \(initialName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("New Name", text: $newName)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit {
                        submit()
                    }

                Button(action: {
                    newName = initialName
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Restore original filename")
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: targetWidth)
        .onAppear {
            if newName.isEmpty {
                newName = initialName
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isNameFocused = true
            }
        }
    }

    private func submit() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}

public struct NewFolderSheet: View {
    public let defaultName: String
    public var onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var folderName: String
    @FocusState private var isFocused: Bool

    public init(defaultName: String = "New Folder", onCommit: @escaping (String) -> Void) {
        self.defaultName = defaultName
        self.onCommit = onCommit
        self._folderName = State(initialValue: defaultName)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
                Text("New Folder")
                    .font(.headline)
                Spacer()
            }

            TextField("Folder Name", text: $folderName)
                .font(.body)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submit()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if folderName.isEmpty {
                folderName = defaultName
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }

    private func submit() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}

// AppKit key event monitor helper for global panel shortcuts
public struct KeyboardShortcutHelper: NSViewRepresentable {
    var isEnabled: Bool = true
    let onTab: () -> Void
    let onSpace: () -> Void
    var onEscape: (() -> Void)? = nil
    var onQuickLook: (() -> Void)? = nil
    var onConnect: (() -> Void)? = nil
    let onCopy: () -> Void
    let onCut: () -> Void
    let onPaste: () -> Void
    let onRefresh: () -> Void
    let onF5: () -> Void
    let onF6: () -> Void
    let onDelete: () -> Void
    let onNewFolder: () -> Void
    let onSelectAll: () -> Void
    let onDownArrow: (Bool) -> Void
    let onUpArrow: (Bool) -> Void
    let onReturn: () -> Void
    let onCmdDown: () -> Void
    let onCmdO: () -> Void
    let onCmdUp: () -> Void
    let onBackspace: () -> Void
    let onHome: (Bool) -> Void
    let onEnd: (Bool) -> Void
    var onGetInfo: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onGoBack: (() -> Void)? = nil
    var onGoForward: (() -> Void)? = nil
    var onToggleHidden: (() -> Void)? = nil
    var onToggleFilter: (() -> Void)? = nil
    var onGoToPath: (() -> Void)? = nil
    let onTypeChar: (String) -> Void

    /// Testable helper verifying whether a key event should trigger file deletion (`Cmd+Backspace`, `Ctrl+Backspace`, or `Forward Delete`).
    public static func shouldTriggerDelete(keyCode: UInt16, isCmd: Bool, isCtrl: Bool, isPlain: Bool) -> Bool {
        if keyCode == 51 {
            return isCmd || isCtrl
        }
        if keyCode == 117 {
            return true
        }
        return false
    }

    /// Testable helper verifying whether a key event should open the Connections Manager (`Cmd+K`).
    public static func shouldTriggerConnect(keyCode: UInt16, charKey: String?, isCmd: Bool, isShift: Bool, isCtrl: Bool) -> Bool {
        return (keyCode == 40 || charKey?.lowercased() == "k") && isCmd && !isShift && !isCtrl
    }

    /// Testable helper verifying whether a key event should toggle file selection (`Space`).
    public static func shouldTriggerSpaceToggle(keyCode: UInt16, isPlain: Bool) -> Bool {
        return keyCode == 49 && isPlain
    }

    /// Testable helper verifying whether a key event should cancel/clear selection (`Escape` - keyCode 53).
    public static func shouldTriggerEscape(keyCode: UInt16) -> Bool {
        return keyCode == 53
    }

    public func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        updateKeyView(view)
        return view
    }

    public func updateNSView(_ nsView: KeyView, context: Context) {
        updateKeyView(nsView)
    }

    private func updateKeyView(_ view: KeyView) {
        view.isEnabled = isEnabled
        view.onTab = onTab
        view.onSpace = onSpace
        view.onEscape = onEscape
        view.onQuickLook = onQuickLook
        view.onConnect = onConnect
        view.onCopy = onCopy
        view.onCut = onCut
        view.onPaste = onPaste
        view.onRefresh = onRefresh
        view.onF5 = onF5
        view.onF6 = onF6
        view.onDelete = onDelete
        view.onNewFolder = onNewFolder
        view.onSelectAll = onSelectAll
        view.onDownArrow = onDownArrow
        view.onUpArrow = onUpArrow
        view.onReturn = onReturn
        view.onCmdDown = onCmdDown
        view.onCmdO = onCmdO
        view.onCmdUp = onCmdUp
        view.onBackspace = onBackspace
        view.onHome = onHome
        view.onEnd = onEnd
        view.onGetInfo = onGetInfo
        view.onDuplicate = onDuplicate
        view.onGoBack = onGoBack
        view.onGoForward = onGoForward
        view.onToggleHidden = onToggleHidden
        view.onToggleFilter = onToggleFilter
        view.onGoToPath = onGoToPath
        view.onTypeChar = onTypeChar
    }

    public class KeyView: NSView {
        var isEnabled: Bool = true
        var onTab: (() -> Void)?
        var onSpace: (() -> Void)?
        var onEscape: (() -> Void)?
        var onQuickLook: (() -> Void)?
        var onConnect: (() -> Void)?
        var onCopy: (() -> Void)?
        var onCut: (() -> Void)?
        var onPaste: (() -> Void)?
        var onRefresh: (() -> Void)?
        var onF5: (() -> Void)?
        var onF6: (() -> Void)?
        var onDelete: (() -> Void)?
        var onNewFolder: (() -> Void)?
        var onSelectAll: (() -> Void)?
        var onDownArrow: ((Bool) -> Void)?
        var onUpArrow: ((Bool) -> Void)?
        var onReturn: (() -> Void)?
        var onCmdDown: (() -> Void)?
        var onCmdO: (() -> Void)?
        var onCmdUp: (() -> Void)?
        var onBackspace: (() -> Void)?
        var onHome: ((Bool) -> Void)?
        var onEnd: ((Bool) -> Void)?
        var onGetInfo: (() -> Void)?
        var onDuplicate: (() -> Void)?
        var onGoBack: (() -> Void)?
        var onGoForward: (() -> Void)?
        var onToggleHidden: (() -> Void)?
        var onToggleFilter: (() -> Void)?
        var onGoToPath: (() -> Void)?
        var onTypeChar: ((String) -> Void)?
        private var monitor: Any?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self = self else { return event }

                    // 1. If helper is disabled (modal / sheet / alert active), do NOT intercept!
                    guard self.isEnabled else { return event }

                    // 2. If event is for another window (such as a sheet or dialog), do NOT intercept!
                    guard let myWindow = self.window, event.window === myWindow else {
                        return event
                    }

                    // 3. If main window has an attached sheet, do NOT intercept!
                    if myWindow.attachedSheet != nil {
                        return event
                    }

                    // 4. If window is not key, do NOT intercept!
                    if !myWindow.isKeyWindow {
                        return event
                    }

                    // 5. If user is currently typing inside a text field / search bar, do NOT intercept!
                    if let responder = myWindow.firstResponder,
                       (responder is NSTextView || responder is NSTextField || responder is NSTextInputClient) {
                        // Allow escape to blur text field
                        if event.keyCode == 53 {
                            myWindow.makeFirstResponder(nil)
                            return nil
                        }
                        return event
                    }

                    // Escape key (keyCode 53) outside text fields -> Deselect all / cancel toggles
                    if KeyboardShortcutHelper.shouldTriggerEscape(keyCode: event.keyCode) {
                        DispatchQueue.main.async {
                            self.onEscape?()
                        }
                        return nil
                    }

                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let isCmd = flags.contains(.command)
                    let isShift = flags.contains(.shift)
                    let isCtrl = flags.contains(.control)
                    let isPlain = flags.isEmpty
                    let charKey = event.charactersIgnoringModifiers?.lowercased()

                    // Tab key (switch panes)
                    if event.keyCode == 48 && isPlain {
                        self.onTab?()
                        return nil
                    }

                    // Cmd + K (Connections Manager) - keyCode 40
                    if KeyboardShortcutHelper.shouldTriggerConnect(keyCode: event.keyCode, charKey: charKey, isCmd: isCmd, isShift: isShift, isCtrl: isCtrl) {
                        DispatchQueue.main.async {
                            self.onConnect?()
                        }
                        return nil
                    }

                    // Cmd + Y (Quick Look) - keyCode 16
                    if (event.keyCode == 16 || charKey == "y") && isCmd && !isShift && !isCtrl {
                        self.onQuickLook?()
                        return nil
                    }

                    // Cmd + Shift + N (New Folder) - keyCode 45
                    if (event.keyCode == 45 || charKey == "n") && isCmd && isShift {
                        DispatchQueue.main.async {
                            self.onNewFolder?()
                        }
                        return nil
                    }

                    // Cmd + F (Filter) - keyCode 3
                    if (event.keyCode == 3 || charKey == "f") && isCmd && !isShift && !isCtrl {
                        DispatchQueue.main.async { self.onToggleFilter?() }
                        return nil
                    }

                    // Cmd + Shift + G (Go to Folder) - keyCode 5
                    if (event.keyCode == 5 || charKey == "g") && isCmd && isShift {
                        DispatchQueue.main.async { self.onGoToPath?() }
                        return nil
                    }

                    // Cmd + Shift + . (Toggle Hidden Files) - keyCode 47
                    if (event.keyCode == 47 || charKey == ".") && isCmd && isShift {
                        self.onToggleHidden?()
                        return nil
                    }

                    // Cmd + I (Get Info) - keyCode 34
                    if (event.keyCode == 34 || charKey == "i") && isCmd && !isShift {
                        self.onGetInfo?()
                        return nil
                    }

                    // Cmd + D (Duplicate) - keyCode 2
                    if (event.keyCode == 2 || charKey == "d") && isCmd && !isShift {
                        self.onDuplicate?()
                        return nil
                    }

                    // Cmd + [ (Go Back) - keyCode 33
                    if (event.keyCode == 33 || charKey == "[") && isCmd && !isShift {
                        self.onGoBack?()
                        return nil
                    }

                    // Cmd + ] (Go Forward) - keyCode 30
                    if (event.keyCode == 30 || charKey == "]") && isCmd && !isShift {
                        self.onGoForward?()
                        return nil
                    }

                    // Cmd + O (Open / Enter) - keyCode 31
                    if (event.keyCode == 31 || charKey == "o") && isCmd && !isShift {
                        self.onCmdO?()
                        return nil
                    }

                    // Cmd + C (Copy) - keyCode 8
                    if (event.keyCode == 8 || charKey == "c") && isCmd && !isShift {
                        self.onCopy?()
                        return nil
                    }

                    // Cmd + X (Cut) - keyCode 7
                    if (event.keyCode == 7 || charKey == "x") && isCmd && !isShift {
                        self.onCut?()
                        return nil
                    }

                    // Cmd + V (Paste) - keyCode 9
                    if (event.keyCode == 9 || charKey == "v") && isCmd && !isShift {
                        self.onPaste?()
                        return nil
                    }

                    // Cmd + R (Refresh) - keyCode 15
                    if (event.keyCode == 15 || charKey == "r") && isCmd && !isShift {
                        self.onRefresh?()
                        return nil
                    }

                    // Down Arrow (keyCode 125)
                    if event.keyCode == 125 {
                        if isCmd {
                            self.onCmdDown?()
                        } else {
                            self.onDownArrow?(isShift)
                        }
                        return nil
                    }

                    // Up Arrow (keyCode 126)
                    if event.keyCode == 126 {
                        if isCmd {
                            self.onCmdUp?()
                        } else {
                            self.onUpArrow?(isShift)
                        }
                        return nil
                    }

                    // Return / Enter (keyCode 36 or 76) -> macOS Finder Rename
                    if event.keyCode == 36 || event.keyCode == 76 {
                        if !isCmd {
                            DispatchQueue.main.async {
                                self.onReturn?()
                            }
                            return nil
                        }
                    }

                    // Backspace / Delete (keyCode 51) & Forward Delete (keyCode 117)
                    if KeyboardShortcutHelper.shouldTriggerDelete(keyCode: event.keyCode, isCmd: isCmd, isCtrl: isCtrl, isPlain: isPlain) {
                        self.onDelete?()
                        return nil
                    }
                    if event.keyCode == 51 && isPlain {
                        self.onBackspace?()
                        return nil
                    }

                    // Space (Toggle File Selection ON/OFF)
                    if KeyboardShortcutHelper.shouldTriggerSpaceToggle(keyCode: event.keyCode, isPlain: isPlain) {
                        self.onSpace?()
                        return nil
                    }

                    // Home & End (supports Shift + Home / Shift + End range selection)
                    if event.keyCode == 115 {
                        self.onHome?(isShift)
                        return nil
                    }
                    if event.keyCode == 119 {
                        self.onEnd?(isShift)
                        return nil
                    }

                    // F5 (Copy to other pane)
                    if event.keyCode == 96 {
                        self.onF5?()
                        return nil
                    }

                    // F6 (Move to other pane)
                    if event.keyCode == 97 {
                        self.onF6?()
                        return nil
                    }

                    // Cmd + A (Select All)
                    if (event.keyCode == 0 || charKey == "a") && isCmd {
                        self.onSelectAll?()
                        return nil
                    }

                    // Type-to-select: regular alphanumeric characters
                    if isPlain, let chars = event.characters, !chars.isEmpty {
                        let scalar = chars.unicodeScalars.first!
                        if CharacterSet.alphanumerics.contains(scalar) {
                            self.onTypeChar?(chars)
                            return nil
                        }
                    }

                    return event
                }
            } else if window == nil && monitor != nil {
                if let m = monitor {
                    NSEvent.removeMonitor(m)
                    monitor = nil
                }
            }
        }

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
