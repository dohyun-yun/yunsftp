import SwiftUI
import AppKit
import QuartzCore

public struct FileListView: View {
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

    @AppStorage("colWidth_name") private var nameWidth: Double = 220
    @AppStorage("colWidth_size") private var sizeWidth: Double = 80
    @AppStorage("colWidth_date") private var dateWidth: Double = 135
    @AppStorage("colWidth_kind") private var kindWidth: Double = 95
    @AppStorage("colWidth_perms") private var permsWidth: Double = 65

    public static func totalColumnsWidth(
        nameWidth: Double,
        sizeWidth: Double,
        dateWidth: Double,
        kindWidth: Double,
        permsWidth: Double
    ) -> Double {
        return nameWidth + sizeWidth + dateWidth + kindWidth + permsWidth + 25.0
    }

    public static func calculateTableWidth(
        paneWidth: Double,
        nameWidth: Double,
        sizeWidth: Double,
        dateWidth: Double,
        kindWidth: Double,
        permsWidth: Double
    ) -> Double {
        let cols = totalColumnsWidth(
            nameWidth: nameWidth,
            sizeWidth: sizeWidth,
            dateWidth: dateWidth,
            kindWidth: kindWidth,
            permsWidth: permsWidth
        )
        return max(paneWidth, cols)
    }

    /// Computes the effective width for the Name column so that when the pane width is sufficient,
    /// the filename expands into the available space rather than being truncated prematurely.
    public static func effectiveNameColumnWidth(
        paneWidth: Double,
        nameWidth: Double,
        sizeWidth: Double,
        dateWidth: Double,
        kindWidth: Double,
        permsWidth: Double
    ) -> Double {
        let otherCols = sizeWidth + dateWidth + kindWidth + permsWidth + 25.0
        let available = max(100.0, paneWidth - otherCols)
        return max(nameWidth, available)
    }

    /// Computes the valid clamped horizontal scroll offset `[0, max(0, contentWidth - viewportWidth)]`
    /// so that overscrolled blank space at the left or right edge always snaps back cleanly.
    public static func clampedHorizontalOffset(
        currentX: Double,
        contentWidth: Double,
        viewportWidth: Double
    ) -> Double {
        let maxOffset = max(0.0, contentWidth - max(0.0, viewportWidth))
        return min(max(0.0, currentX), maxOffset)
    }

    /// Computes the minimal vertical scroll adjustment to make `rowIndex` visible within `[visibleTop, visibleBottom]`.
    /// Returns `nil` if the row is already fully visible, preventing jarring jumps on mouse selection.
    public static func targetVerticalOffset(
        rowIndex: Int,
        headerHeight: Double = 24.0,
        rowHeight: Double = 22.0,
        currentOriginY: Double,
        viewportHeight: Double
    ) -> Double? {
        guard viewportHeight > 0, rowIndex >= 0 else { return nil }
        let rowTop = headerHeight + Double(rowIndex) * rowHeight
        let rowBottom = rowTop + rowHeight

        let visibleTop = currentOriginY + headerHeight
        let visibleBottom = currentOriginY + viewportHeight

        if rowTop < visibleTop {
            // Above visible top -> scroll up just enough to reveal row below header
            return max(0.0, rowTop - headerHeight)
        } else if rowBottom > visibleBottom {
            // Below visible bottom -> scroll down just enough to reveal row at bottom
            return max(0.0, rowBottom - viewportHeight)
        } else {
            // Fully visible within viewport -> do NOT jump or scroll
            return nil
        }
    }

    @ViewBuilder
    private func tableHeaderBar(tableWidth: Double, nameColumnWidth: Double) -> some View {
        HStack(spacing: 0) {
            headerCell("Name", field: .name, alignment: .leading, width: nameColumnWidth)
            ColumnResizeDivider(
                width: Binding<Double>(
                    get: { nameColumnWidth },
                    set: { nameWidth = $0 }
                ),
                minWidth: 100,
                maxWidth: 1000,
                defaultWidth: 220
            )

            headerCell("Size", field: .size, alignment: .trailing, width: sizeWidth)
            ColumnResizeDivider(width: $sizeWidth, minWidth: 50, maxWidth: 300, defaultWidth: 80)

            headerCell("Date Modified", field: .date, alignment: .leading, width: dateWidth)
            ColumnResizeDivider(width: $dateWidth, minWidth: 80, maxWidth: 350, defaultWidth: 135)

            headerCell("Kind", field: .kind, alignment: .leading, width: kindWidth)
            ColumnResizeDivider(width: $kindWidth, minWidth: 50, maxWidth: 300, defaultWidth: 95)

            headerCell("Perms", field: nil, alignment: .center, width: permsWidth)
            ColumnResizeDivider(width: $permsWidth, minWidth: 45, maxWidth: 200, defaultWidth: 65)

            Spacer(minLength: 0)
        }
        .frame(width: tableWidth, height: 24, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }

    public var body: some View {
        GeometryReader { geo in
            let effectiveNameW = Self.effectiveNameColumnWidth(
                paneWidth: geo.size.width,
                nameWidth: nameWidth,
                sizeWidth: sizeWidth,
                dateWidth: dateWidth,
                kindWidth: kindWidth,
                permsWidth: permsWidth
            )
            let colsWidth = Self.totalColumnsWidth(
                nameWidth: effectiveNameW,
                sizeWidth: sizeWidth,
                dateWidth: dateWidth,
                kindWidth: kindWidth,
                permsWidth: permsWidth
            )
            let tableWidth = max(geo.size.width, colsWidth)

            if pane.displayedItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: colsWidth > geo.size.width) {
                    VStack(spacing: 0) {
                        tableHeaderBar(tableWidth: tableWidth, nameColumnWidth: effectiveNameW)

                        VStack(spacing: 12) {
                            Spacer()
                            if pane.isLoading {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Loading...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            } else if let error = pane.errorMessage {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                if pane.isRemote {
                                    Button("Disconnect") {
                                        pane.disconnectRemote()
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button("Reload") {
                                        pane.reload()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                Image(systemName: "folder")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary.opacity(0.4))
                                Text("Folder is Empty")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .frame(width: tableWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onActivate()
                        }
                        .background(
                            HorizontalScrollBounceNormalizer(
                                contentWidth: tableWidth,
                                viewportWidth: geo.size.width
                            )
                        )
                    }
                    .frame(width: tableWidth, height: max(100, geo.size.height), alignment: .topLeading)
                }
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section(header: tableHeaderBar(tableWidth: tableWidth, nameColumnWidth: effectiveNameW)) {
                            ForEach(pane.displayedItems) { item in
                                FileRowView(
                                    item: item,
                                    isSelected: pane.selectedItemURLs.contains(item.url),
                                    isFocused: pane.focusedItemURL == item.url,
                                    nameWidth: effectiveNameW,
                                    sizeWidth: sizeWidth,
                                    dateWidth: dateWidth,
                                    kindWidth: kindWidth,
                                    permsWidth: permsWidth,
                                    onActivate: onActivate,
                                    onSelect: { isShift, isCmd in
                                        onActivate()
                                        handleSelection(item: item, isShift: isShift, isCmd: isCmd)
                                    },
                                    onDoubleClick: {
                                        onActivate()
                                        if item.isDirectory {
                                            pane.navigateTo(item.url)
                                        } else {
                                            onOpenItem(item)
                                        }
                                    },
                                    onDragStart: {
                                        let itemsToDrag = pane.selectedItemURLs.contains(item.url) ? pane.selectedItems : [item]
                                        DragDropManager.shared.startDrag(items: itemsToDrag, from: pane)
                                    },
                                    onDropOntoFolder: { providers in
                                        onActivate()
                                        DragDropManager.shared.handleDrop(onto: pane, targetSubfolder: item, externalProviders: providers) {
                                            pane.reload()
                                        }
                                    },
                                    onDropOntoPane: { providers in
                                        onActivate()
                                        DragDropManager.shared.handleDrop(onto: pane, targetSubfolder: nil, externalProviders: providers) {
                                            pane.reload()
                                        }
                                    }
                                )
                                .frame(width: tableWidth, alignment: .leading)
                                .contextMenu {
                                    contextMenuFor(item: item)
                                }
                                .id(item.url)
                            }
                        }
                    }
                    .frame(width: tableWidth, alignment: .topLeading)
                    .background(
                        HorizontalScrollBounceNormalizer(
                            contentWidth: tableWidth,
                            viewportWidth: geo.size.width,
                            targetURL: pane.focusedItemURL,
                            items: pane.displayedItems
                        )
                    )
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func headerCell(_ title: String, field: SortField?, alignment: Alignment, width: Double) -> some View {
        Button(action: {
            onActivate()
            guard let field = field else { return }
            if pane.sortField == field {
                pane.sortAscending.toggle()
            } else {
                pane.sortField = field
                pane.sortAscending = true
            }
        }) {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let field = field, pane.sortField == field {
                    Image(systemName: pane.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.accentColor)
                }
                if alignment != .trailing { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 6)
            .frame(width: width, height: 24)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(field == nil)
    }

    private func handleSelection(item: FileItem, isShift: Bool, isCmd: Bool) {
        if isCmd {
            pane.toggleSelection(item.url)
        } else if isShift {
            pane.selectRange(to: item.url)
        } else {
            pane.selectSingle(item.url)
        }
    }

    @ViewBuilder
    private func contextMenuFor(item: FileItem) -> some View {
        Button("Open (Cmd+O)") {
            onActivate()
            if item.isDirectory {
                pane.navigateTo(item.url)
            } else {
                onOpenItem(item)
            }
        }

        Button("Toggle Selection (Space)") {
            onActivate()
            pane.focusedItemURL = item.url
            pane.toggleSelectionAtFocus()
        }

        Button("Quick Look (Cmd+Y)") {
            onActivate()
            onQuickLook(item)
        }

        Button("Get Info (Cmd+I)") {
            onActivate()
            onShowInfo(item)
        }

        Divider()

        // Clipboard Copy / Cut / Paste
        Button("Copy (Cmd+C)") {
            onActivate()
            let itemsToCopy = pane.selectedItemURLs.contains(item.url) ? pane.selectedItems : [item]
            ClipboardService.shared.copy(items: itemsToCopy, from: pane)
        }

        Button("Cut (Cmd+X)") {
            onActivate()
            let itemsToCut = pane.selectedItemURLs.contains(item.url) ? pane.selectedItems : [item]
            ClipboardService.shared.cut(items: itemsToCut, from: pane)
        }

        Button("Paste (Cmd+V)") {
            onActivate()
            ClipboardService.shared.paste(to: pane) {
                pane.reload()
            }
        }
        .disabled(!ClipboardService.shared.canPaste)

        Divider()

        Button("Copy to Other Pane (F5)") {
            onActivate()
            if !pane.selectedItemURLs.contains(item.url) {
                pane.selectSingle(item.url)
            }
            onCopyToOtherPane()
        }

        Button("Move to Other Pane (F6)") {
            onActivate()
            if !pane.selectedItemURLs.contains(item.url) {
                pane.selectSingle(item.url)
            }
            onMoveToOtherPane()
        }

        Divider()

        Button("Permissions (chmod)...") {
            onActivate()
            onChmod(item)
        }

        Button("Rename (Enter)") {
            onActivate()
            onRename(item)
        }

        Button("Duplicate (Cmd+D)") {
            onActivate()
            if pane.isRemote, let conn = pane.remoteConnection {
                let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
                let remotePath = item.url.path.precomposedStringWithCanonicalMapping
                Task {
                    do {
                        _ = try await SFTPService.shared.duplicate(remotePath: remotePath, isDirectory: item.isDirectory, connection: conn, password: pwd)
                        await MainActor.run {
                            pane.reload()
                        }
                    } catch {
                        await MainActor.run {
                            pane.errorMessage = "복제 실패: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                Task {
                    do {
                        try await FileSystemService.shared.duplicate(urls: [item.url])
                        await MainActor.run {
                            pane.reload()
                        }
                    } catch {
                        await MainActor.run {
                            pane.errorMessage = "복제 실패: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }

        if !pane.isRemote {
            if item.fileExtension == "zip" {
                Button("Extract Archive") {
                    onActivate()
                    onExtractArchive(item)
                }
            } else {
                Button("Compress to Zip") {
                    onActivate()
                    onCompressItems([item])
                }
            }
        }

        Divider()

        Button("Refresh (Cmd+R)") {
            pane.reload()
        }

        if !pane.isRemote {
            Button("Open in Terminal") {
                TerminalService.openInTerminal(at: item.isDirectory ? item.url : pane.currentURL)
            }

            Button("Reveal in Finder") {
                TerminalService.revealInFinder(url: item.url)
            }
        }

        Divider()

        Button("Delete / Move to Trash (Cmd+Backspace)", role: .destructive) {
            onActivate()
            let targets = pane.selectedItemURLs.contains(item.url) ? pane.selectedItems : [item]
            onTrashItems(targets)
        }
    }
}

public struct FileRowView: View {
    let item: FileItem
    let isSelected: Bool
    let isFocused: Bool
    let nameWidth: Double
    let sizeWidth: Double
    let dateWidth: Double
    let kindWidth: Double
    let permsWidth: Double
    let onActivate: () -> Void
    let onSelect: (Bool, Bool) -> Void
    let onDoubleClick: () -> Void
    let onDragStart: () -> Void
    let onDropOntoFolder: ([NSItemProvider]) -> Void
    let onDropOntoPane: ([NSItemProvider]) -> Void

    @State private var isFolderDropTarget: Bool = false

    public var body: some View {
        HStack(spacing: 0) {
            // Icon & Name
            HStack(spacing: 6) {
                Image(nsImage: FileIconProvider.shared.icon(for: item))
                    .resizable()
                    .frame(width: 16, height: 16)

                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : (item.isHidden ? .secondary : .primary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.isSymlink {
                    Image(systemName: "arrowshape.turn.up.right.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: nameWidth, alignment: .leading)
            .clipped()

            Color.clear.frame(width: 5)

            // Size
            HStack {
                Spacer(minLength: 0)
                Text(item.formattedSize)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: sizeWidth, alignment: .trailing)
            .clipped()

            Color.clear.frame(width: 5)

            // Date
            HStack {
                Text(item.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: dateWidth, alignment: .leading)
            .clipped()

            Color.clear.frame(width: 5)

            // Kind
            HStack {
                Text(item.kindDescription)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: kindWidth, alignment: .leading)
            .clipped()

            Color.clear.frame(width: 5)

            // Permissions
            Text(item.posixPermissions)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.8))
                .lineLimit(1)
                .frame(width: permsWidth, alignment: .center)
                .clipped()

            Color.clear.frame(width: 5)

            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .background(
            isFolderDropTarget ? Color.accentColor.opacity(0.3) :
            (isSelected ? Color.accentColor :
            (isFocused ? Color.accentColor.opacity(0.20) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    isFolderDropTarget ? Color.accentColor :
                    (isFocused ? (isSelected ? Color.white.opacity(0.95) : Color.accentColor.opacity(0.85)) : Color.clear),
                    lineWidth: isFocused ? 1.5 : 1.0
                )
                .padding(.horizontal, 1)
                .padding(.vertical, 0.5)
        )
        .contentShape(Rectangle())
        .onDrag {
            onActivate()
            onDragStart()
            return NSItemProvider(object: item.url as NSURL)
        }
        .onDrop(of: [.fileURL, .url, .text, .plainText], isTargeted: $isFolderDropTarget) { providers in
            onActivate()
            if item.isDirectory {
                onDropOntoFolder(providers)
            } else {
                onDropOntoPane(providers)
            }
            return true
        }
        .onTapGesture(count: 2) {
            onActivate()
            onDoubleClick()
        }
        .simultaneousGesture(
            TapGesture().modifiers(.shift).onEnded {
                onActivate()
                onSelect(true, false)
            }
        )
        .simultaneousGesture(
            TapGesture().modifiers(.command).onEnded {
                onActivate()
                onSelect(false, true)
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                onActivate()
                onSelect(false, false)
            }
        )
    }
}

/// Ensures horizontal scrolling in NSScrollView snaps back immediately when overscrolled past the left or right edge
/// and manages minimal vertical visibility scrolling on focus/selection while keeping horizontal scroll strictly left-anchored (at x = 0).
public struct HorizontalScrollBounceNormalizer: NSViewRepresentable {
    let contentWidth: Double
    let viewportWidth: Double
    var targetURL: URL? = nil
    var items: [FileItem] = []

    public func makeNSView(context: Context) -> ScrollNormalizerNSView {
        let view = ScrollNormalizerNSView()
        view.contentWidth = contentWidth
        view.viewportWidth = viewportWidth
        return view
    }

    public func updateNSView(_ nsView: ScrollNormalizerNSView, context: Context) {
        nsView.contentWidth = contentWidth
        nsView.viewportWidth = viewportWidth
        nsView.configureScrollViewIfNeeded()
        if let target = targetURL {
            nsView.scrollToItemIfNeeded(url: target, items: items)
        } else {
            nsView.lastScrolledURL = nil
        }
    }

    public final class ScrollNormalizerNSView: NSView {
        var contentWidth: Double = 0
        var viewportWidth: Double = 0
        private weak var attachedScrollView: NSScrollView?
        private var scrollMonitor: Any?
        private var isUserTouchingTrackpad: Bool = false
        var lastScrolledURL: URL? = nil

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureScrollViewIfNeeded()
            if window != nil && scrollMonitor == nil {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.handleScrollEvent(event)
                    return event
                }
            } else if window == nil, let m = scrollMonitor {
                NSEvent.removeMonitor(m)
                scrollMonitor = nil
            }
        }

        func configureScrollViewIfNeeded() {
            guard let sv = enclosingScrollView else { return }
            if attachedScrollView !== sv {
                attachedScrollView = sv
                sv.horizontalScrollElasticity = .allowed
                sv.verticalScrollElasticity = .allowed
                let clipView = sv.contentView
                if clipView.bounds.origin.x != 0 {
                    clipView.setBoundsOrigin(NSPoint(x: 0, y: clipView.bounds.origin.y))
                    sv.reflectScrolledClipView(clipView)
                }
            }
            if !isUserTouchingTrackpad {
                snapBackIfOutOfBounds(animated: false)
            }
        }

        func scrollToItemIfNeeded(url: URL, items: [FileItem]) {
            guard let sv = attachedScrollView else { return }
            guard let index = items.firstIndex(where: { $0.url == url }) else { return }

            let clipView = sv.contentView
            let clipBounds = clipView.bounds
            guard clipBounds.height > 0 else { return }

            let targetOffset = FileListView.targetVerticalOffset(
                rowIndex: index,
                headerHeight: 24.0,
                rowHeight: 22.0,
                currentOriginY: Double(clipBounds.origin.y),
                viewportHeight: Double(clipBounds.height)
            )

            let currentX = Double(clipBounds.origin.x)
            let targetX = 0.0

            if let targetY = targetOffset {
                let targetPoint = NSPoint(x: CGFloat(targetX), y: CGFloat(targetY))
                clipView.setBoundsOrigin(targetPoint)
                sv.reflectScrolledClipView(clipView)
            } else if !isUserTouchingTrackpad && abs(currentX - targetX) > 0.5 {
                let targetPoint = NSPoint(x: CGFloat(targetX), y: clipBounds.origin.y)
                clipView.setBoundsOrigin(targetPoint)
                sv.reflectScrolledClipView(clipView)
            }
            lastScrolledURL = url
        }

        private func handleScrollEvent(_ event: NSEvent) {
            guard let sv = attachedScrollView,
                  let win = sv.window,
                  event.window === win else { return }

            let locationInSV = sv.convert(event.locationInWindow, from: nil)
            guard sv.bounds.contains(locationInSV) else { return }

            if event.phase == .began || event.phase == .changed || event.phase == .mayBegin {
                isUserTouchingTrackpad = true
            } else if event.phase == .ended || event.phase == .cancelled {
                isUserTouchingTrackpad = false
                DispatchQueue.main.async { [weak self] in
                    self?.snapBackIfOutOfBounds(animated: true)
                }
            } else if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                isUserTouchingTrackpad = false
                DispatchQueue.main.async { [weak self] in
                    self?.snapBackIfOutOfBounds(animated: true)
                }
            } else if event.phase.isEmpty && event.momentumPhase.isEmpty {
                isUserTouchingTrackpad = false
                DispatchQueue.main.async { [weak self] in
                    self?.snapBackIfOutOfBounds(animated: true)
                }
            }
        }

        func snapBackIfOutOfBounds(animated: Bool) {
            guard let sv = attachedScrollView else { return }
            let clipView = sv.contentView
            let currentOrigin = clipView.bounds.origin
            let effectiveViewportWidth = Double(clipView.bounds.width > 0 ? clipView.bounds.width : CGFloat(viewportWidth))
            let effectiveContentWidth = max(contentWidth, Double(sv.documentView?.frame.width ?? CGFloat(contentWidth)))
            let targetX = FileListView.clampedHorizontalOffset(
                currentX: Double(currentOrigin.x),
                contentWidth: effectiveContentWidth,
                viewportWidth: effectiveViewportWidth
            )

            if abs(Double(currentOrigin.x) - targetX) > 0.5 {
                let targetPoint = NSPoint(x: CGFloat(targetX), y: currentOrigin.y)
                if animated {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.18
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        clipView.animator().setBoundsOrigin(targetPoint)
                    } completionHandler: {
                        sv.reflectScrolledClipView(clipView)
                    }
                } else {
                    clipView.setBoundsOrigin(targetPoint)
                    sv.reflectScrolledClipView(clipView)
                }
            }
        }

        deinit {
            if let m = scrollMonitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}

public struct ColumnResizeDivider: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    var defaultWidth: Double = 120

    @State private var dragStartWidth: Double? = nil

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1)
        }
        .frame(width: 5, height: 24)
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture(count: 2) {
            width = defaultWidth
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }
                    let newWidth = (dragStartWidth ?? width) + Double(value.translation.width)
                    width = max(minWidth, min(maxWidth, newWidth))
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }
}

