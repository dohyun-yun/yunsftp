import SwiftUI
import AppKit

/// Native SwiftUI `Table` presentation of a pane (macOS 14+): system header, sorting, column
/// resize/reorder/hide via the header context menu, and native multi-selection. The pane's own
/// keyboard model (Space toggle, Shift ranges, focus cursor) keeps working because the window's
/// key monitor handles those keys before the table sees them.
public struct FileTableView: View {
    @ObservedObject var pane: PaneModel
    var onActivate: () -> Void
    var onOpenItem: (FileItem) -> Void
    var onShowInfo: (FileItem) -> Void
    var onQuickLook: (FileItem) -> Void
    var onRename: (FileItem) -> Void
    var onChmod: (FileItem) -> Void
    var onCopyToOtherPane: () -> Void
    var onMoveToOtherPane: () -> Void
    var onTrashItems: ([FileItem]) -> Void
    var onCompressItems: ([FileItem]) -> Void
    var onExtractArchive: (FileItem) -> Void

    @ObservedObject private var settingsStore = SettingsStore.shared
    @AppStorage("yunsftp_tableColumns") private var customization: TableColumnCustomization<FileItem>
    @State private var sortOrder: [KeyPathComparator<FileItem>] = []

    public var body: some View {
        Table(of: FileItem.self, selection: selectionBinding, sortOrder: $sortOrder, columnCustomization: $customization) {
            TableColumn(L("Name"), value: \.name) { item in
                nameCell(item)
            }
            .width(min: 140, ideal: 260)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn(L("Size"), value: \.size) { item in
                Text(item.formattedSize)
                    .font(secondaryFont.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            .alignment(.trailing)
            .customizationID("size")

            TableColumn(L("Date Modified"), value: \.modificationDate) { item in
                Text(item.formattedDate(relative: settingsStore.settings.showRelativeDates))
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 150)
            .customizationID("date")

            TableColumn(L("Kind"), value: \.kindDescription) { item in
                Text(item.kindDescription)
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 110)
            .customizationID("kind")

            TableColumn(L("Perms"), value: \.posixPermissions) { item in
                Text(item.posixPermissions)
                    .font(secondaryFont.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            .customizationID("perms")
            .defaultVisibility(.hidden)
        } rows: {
            ForEach(pane.displayedItems) { item in
                TableRow(item)
                    .itemProvider { dragProvider(for: item) }
                    .dropDestination(for: URL.self) { urls in handleDrop(urls, onto: item) }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: URL.self) { urls in
            contextMenu(for: urls)
        } primaryAction: { urls in
            onActivate()
            guard let url = urls.first, let item = pane.displayedItems.first(where: { $0.url == url }) else { return }
            if item.isDirectory { pane.navigateTo(item.url) } else { onOpenItem(item) }
        }
        .onChange(of: sortOrder) { _, order in
            guard let first = order.first, let field = Self.sortField(for: first) else { return }
            pane.sortField = field
            pane.sortAscending = first.order == .forward
        }
        .onAppear {
            sortOrder = Self.comparators(for: pane.sortField, ascending: pane.sortAscending)
        }
        .overlay {
            if pane.displayedItems.isEmpty && !pane.isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text(L("Folder is Empty")).font(.title3).foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
            }
        }
        .onTapGesture { onActivate() }
    }

    private var secondaryFont: Font { .system(size: max(9, settingsStore.settings.fontSize - 1)) }

    @ViewBuilder
    private func nameCell(_ item: FileItem) -> some View {
        let focused = pane.focusedItemURL == item.url && !pane.selectedItemURLs.contains(item.url)
        HStack(spacing: 6) {
            Image(nsImage: FileIconProvider.shared.icon(for: item))
                .resizable()
                .frame(width: 16, height: 16)
            Text(item.name)
                .font(.system(size: settingsStore.settings.fontSize, weight: focused ? .semibold : .regular))
                .foregroundStyle(item.isHidden ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isSymlink {
                Image(systemName: "arrowshape.turn.up.right.fill").font(.caption2).foregroundStyle(.blue)
            }
        }
        .overlay(alignment: .leading) {
            if focused {
                // Focus cursor: the row the keyboard model will act on, without being selected.
                RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 2).padding(.leading, -8)
            }
        }
    }

    // MARK: - Selection bridge

    private var selectionBinding: Binding<Set<URL>> {
        Binding(
            get: { pane.selectedItemURLs },
            set: { newValue in
                onActivate()
                pane.selectedItemURLs = newValue
                pane.pinnedSelectionURLs = newValue
                if newValue.count == 1, let only = newValue.first {
                    pane.focusedItemURL = only
                    pane.selectionAnchorURL = only
                } else if let f = pane.focusedItemURL, !newValue.contains(f), let any = newValue.first {
                    pane.focusedItemURL = any
                }
            }
        )
    }

    // MARK: - Sorting bridge

    static func sortField(for comparator: KeyPathComparator<FileItem>) -> SortField? {
        switch comparator.keyPath {
        case \FileItem.name: return .name
        case \FileItem.size: return .size
        case \FileItem.modificationDate: return .date
        case \FileItem.kindDescription: return .kind
        default: return nil
        }
    }

    static func comparators(for field: SortField, ascending: Bool) -> [KeyPathComparator<FileItem>] {
        let order: SortOrder = ascending ? .forward : .reverse
        switch field {
        case .name: return [KeyPathComparator(\.name, order: order)]
        case .size: return [KeyPathComparator(\.size, order: order)]
        case .date: return [KeyPathComparator(\.modificationDate, order: order)]
        case .kind: return [KeyPathComparator(\.kindDescription, order: order)]
        }
    }

    // MARK: - Drag & drop

    private func dragProvider(for item: FileItem) -> NSItemProvider {
        onActivate()
        let itemsToDrag = pane.selectedItemURLs.contains(item.url) ? pane.selectedItems : [item]
        DragDropManager.shared.startDrag(items: itemsToDrag, from: pane)
        if pane.isRemote, let conn = pane.remoteConnection {
            let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            return RemoteDragProvider.make(item: item, connection: conn, password: pwd)
        }
        return DragDropManager.shared.makeProvider(for: item.url)
    }

    private func handleDrop(_ urls: [URL], onto item: FileItem) {
        onActivate()
        let target: FileItem? = item.isDirectory ? item : nil
        // The table hands us payloads, not providers: an internal drop is one whose URLs are the
        // items this app started dragging; anything else came from another app.
        let dragged = Set(DragDropManager.shared.draggedItems.map { $0.url.absoluteString })
        let internalDrop = !dragged.isEmpty && urls.contains { dragged.contains($0.absoluteString) }
        let providers = internalDrop ? [] : urls.map { NSItemProvider(object: $0 as NSURL) }
        if !internalDrop { DragDropManager.shared.endDrag() }
        DragDropManager.shared.handleDrop(onto: pane, targetSubfolder: target, externalProviders: providers) {
            pane.reload()
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for urls: Set<URL>) -> some View {
        let items = pane.displayedItems.filter { urls.contains($0.url) }
        if let item = items.first {
            Button(L("Open (Cmd+O)")) {
                onActivate()
                if item.isDirectory { pane.navigateTo(item.url) } else { onOpenItem(item) }
            }
            if pane.isRemote && !item.isDirectory, let conn = pane.remoteConnection {
                Button(L("Edit in External Editor")) {
                    onActivate()
                    let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
                    Task {
                        do { try await RemoteEditService.shared.edit(item: item, connection: conn, password: pwd) }
                        catch { pane.errorMessage = "Could not open for editing: \(error.localizedDescription)" }
                    }
                }
            }
            Button(L("Quick Look (Cmd+Y)")) { onActivate(); onQuickLook(item) }
            Button(L("Get Info (Cmd+I)")) { onActivate(); onShowInfo(item) }
            Divider()
            Button(L("Copy (Cmd+C)")) { onActivate(); ClipboardService.shared.copy(items: items, from: pane) }
            Button(L("Cut (Cmd+X)")) { onActivate(); ClipboardService.shared.cut(items: items, from: pane) }
            Button(L("Copy to Other Pane (F5)")) { onActivate(); selectIfNeeded(items); onCopyToOtherPane() }
            Button(L("Move to Other Pane (F6)")) { onActivate(); selectIfNeeded(items); onMoveToOtherPane() }
            Divider()
            Button(L("Rename (Enter)")) { onActivate(); onRename(item) }
            Button(L("Permissions (chmod)...")) { onActivate(); onChmod(item) }
            if !pane.isRemote {
                if item.fileExtension == "zip" {
                    Button(L("Extract Archive")) { onActivate(); onExtractArchive(item) }
                } else {
                    Button(L("Compress to Zip")) { onActivate(); onCompressItems(items) }
                }
                Button(L("Open in Terminal")) { TerminalService.openInTerminal(at: item.isDirectory ? item.url : pane.currentURL) }
                Button(L("Reveal in Finder")) { TerminalService.revealInFinder(url: item.url) }
            }
            Divider()
            Button(L("Delete / Move to Trash (Cmd+Backspace)"), role: .destructive) { onActivate(); onTrashItems(items) }
        } else {
            Button(L("Refresh (Cmd+R)")) { pane.reload() }
        }
    }

    private func selectIfNeeded(_ items: [FileItem]) {
        let urls = Set(items.map(\.url))
        if !urls.isSubset(of: pane.selectedItemURLs) {
            pane.selectedItemURLs = urls
            pane.pinnedSelectionURLs = urls
        }
    }
}
