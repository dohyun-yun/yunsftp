import SwiftUI
import AppKit

public struct FileGridView: View {
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

    let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 12)
    ]
    @State private var isGridDropTarget: Bool = false

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(pane.displayedItems) { item in
                    let isSelected = pane.selectedItemURLs.contains(item.url)
                    let isFocused = pane.focusedItemURL == item.url
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: FileIconProvider.shared.icon(for: item))
                                .resizable()
                                .frame(width: 48, height: 48)
                                .shadow(radius: 1)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.accentColor)
                                    .background(Circle().fill(Color.white))
                                    .offset(x: 4, y: -4)
                            }
                        }

                        Text(item.name)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.accentColor : (isFocused ? Color.accentColor.opacity(0.20) : Color.clear))
                            .cornerRadius(4)
                    }
                    .frame(width: 96, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                    .onDrag {
                        onActivate()
                        let itemsToDrag = pane.selectedItemURLs.contains(item.url) ? pane.selectedItems : [item]
                        DragDropManager.shared.startDrag(items: itemsToDrag, from: pane)
                        return NSItemProvider(object: item.url as NSURL)
                    }
                    .onTapGesture(count: 2) {
                        onActivate()
                        if item.isDirectory {
                            pane.navigateTo(item.url)
                        } else {
                            onOpenItem(item)
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().modifiers(.shift).onEnded {
                            onActivate()
                            pane.selectRange(to: item.url)
                        }
                    )
                    .simultaneousGesture(
                        TapGesture().modifiers(.command).onEnded {
                            onActivate()
                            pane.toggleSelection(item.url)
                        }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            onActivate()
                            pane.selectSingle(item.url)
                        }
                    )
                    .contextMenu {
                        Button("Open") {
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
                        Button("Duplicate (Cmd+D)") {
                            onActivate()
                            if pane.isRemote {
                                guard let conn = pane.remoteConnection else { return }
                                let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
                                let remotePath = SFTPService.normalizeRemotePath(item.url.path)
                                Task {
                                    do {
                                        _ = try await SFTPService.shared.duplicate(remotePath: remotePath, isDirectory: item.isDirectory, connection: conn, password: pwd)
                                        await MainActor.run { pane.reload() }
                                    } catch {
                                        await MainActor.run { pane.errorMessage = "복제 실패: \(error.localizedDescription)" }
                                    }
                                }
                            } else {
                                Task {
                                    _ = try? await FileSystemService.shared.duplicate(url: item.url)
                                    await MainActor.run { pane.reload() }
                                }
                            }
                        }
                        Divider()
                        Button("Copy to Other Pane (F5)") {
                            onActivate()
                            pane.selectSingle(item.url)
                            onCopyToOtherPane()
                        }
                        Button("Move to Other Pane (F6)") {
                            onActivate()
                            pane.selectSingle(item.url)
                            onMoveToOtherPane()
                        }
                        Divider()
                        Button("Permissions (chmod)...") {
                            onActivate()
                            onChmod(item)
                        }
                        Button("Rename (Return)") {
                            onActivate()
                            onRename(item)
                        }
                        if !pane.isRemote {
                            if item.fileExtension == "zip" {
                                Button("Extract Archive") {
                                    onActivate()
                                    onExtractArchive(item)
                                }
                            } else {
                                Button("Compress") {
                                    onActivate()
                                    onCompressItems([item])
                                }
                            }
                        }
                        Divider()
                        Button("Refresh (Cmd+R)") {
                            pane.reload()
                        }
                        Divider()
                        Button("Move to Trash / Delete", role: .destructive) {
                            onActivate()
                            let targets = pane.selectedItemURLs.contains(item.url) ? pane.selectedItems : [item]
                            onTrashItems(targets)
                        }
                    }
                }
            }
            .padding(12)
        }
        .onDrop(of: [.fileURL, .url, .text, .plainText], isTargeted: $isGridDropTarget) { providers in
            onActivate()
            DragDropManager.shared.handleDrop(onto: pane, targetSubfolder: nil, externalProviders: providers) {
                pane.reload()
            }
            return true
        }
        .background(Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
    }
}
