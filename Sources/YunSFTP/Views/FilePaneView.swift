import SwiftUI

public struct FilePaneView: View {
    @ObservedObject var pane: PaneModel
    let isActive: Bool
    let onActivate: () -> Void

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

    @State private var isDropTarget: Bool = false
    @FocusState private var isFilterFocused: Bool

    public var body: some View {
        VStack(spacing: 0) {
            // Path Bar
            PathBreadcrumbBar(pane: pane)
                .onTapGesture { onActivate() }

            // Pane Control Bar (Filter, View Modes, Hidden Files)
            HStack(spacing: 8) {
                // Filter toggle; the field itself appears only on demand (Cmd+F)
                Button(action: {
                    onActivate()
                    pane.toggleFilter()
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(pane.shouldShowFilter ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Filter this folder (Cmd+F)")
                .accessibilityLabel("Filter")

                if pane.shouldShowFilter {
                    HStack(spacing: 4) {
                        TextField("Filter...", text: $pane.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .focused($isFilterFocused)
                            .onTapGesture { onActivate() }
                            .onExitCommand { pane.toggleFilter() }
                        if !pane.searchQuery.isEmpty {
                            Button(action: { pane.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                    .frame(maxWidth: 180)
                    .onAppear { isFilterFocused = true }
                }

                Spacer()

                // View Mode Toggle (List / Grid)
                Picker("", selection: $pane.viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)
                .frame(width: 70)
                .onChange(of: pane.viewMode) { _ in onActivate() }

                // Hidden files toggle
                Button(action: {
                    onActivate()
                    pane.showHiddenFiles.toggle()
                }) {
                    Image(systemName: pane.showHiddenFiles ? "eye.fill" : "eye.slash")
                        .font(.system(size: 11))
                        .foregroundColor(pane.showHiddenFiles ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Hidden Files (Cmd+Shift+.)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .onTapGesture { onActivate() }

            Divider()

            if let error = pane.errorMessage, !pane.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { pane.errorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.15))
                Divider()
            }

            // File Content View
            Group {
                if pane.isConnecting {
                    RemoteConnectingView(pane: pane, onCancel: {
                        pane.disconnectRemote()
                    })
                } else if pane.items.isEmpty && pane.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(pane.isRemote ? "Fetching remote file list..." : "Loading...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = pane.errorMessage, pane.items.isEmpty {
                    RemoteErrorView(error: error, pane: pane)
                } else if pane.viewMode == .list {
                    FileListView(
                        pane: pane,
                        onActivate: onActivate,
                        onOpenItem: onOpenItem,
                        onShowInfo: onShowInfo,
                        onQuickLook: onQuickLook,
                        onRename: onRename,
                        onChmod: onChmod,
                        onCopyToOtherPane: onCopyToOtherPane,
                        onMoveToOtherPane: onMoveToOtherPane,
                        onTrashItems: onTrashItems,
                        onCompressItems: onCompressItems,
                        onExtractArchive: onExtractArchive
                    )
                } else {
                    FileGridView(
                        pane: pane,
                        onActivate: onActivate,
                        onOpenItem: onOpenItem,
                        onShowInfo: onShowInfo,
                        onQuickLook: onQuickLook,
                        onRename: onRename,
                        onChmod: onChmod,
                        onCopyToOtherPane: onCopyToOtherPane,
                        onMoveToOtherPane: onMoveToOtherPane,
                        onTrashItems: onTrashItems,
                        onCompressItems: onCompressItems,
                        onExtractArchive: onExtractArchive
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL, .url, .text, .plainText], isTargeted: $isDropTarget) { providers in
                onActivate()
                DragDropManager.shared.handleDrop(onto: pane, targetSubfolder: nil, externalProviders: providers) {
                    pane.reload()
                }
                return true
            }

            Divider()

            // Pane Footer Status Bar
            HStack {
                Text(pane.statusDescription)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Text(pane.freeDiskSpaceDescription)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(NSColor.windowBackgroundColor))
            .onTapGesture { onActivate() }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    isDropTarget ? Color.accentColor :
                    (isActive ? Color.accentColor.opacity(0.8) : Color.clear),
                    lineWidth: isDropTarget ? 2.5 : 1.5
                )
        )
        .background(isDropTarget ? Color.accentColor.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
    }
}

public struct RemoteConnectingView: View {
    @ObservedObject var pane: PaneModel
    var onCancel: () -> Void

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "server.rack")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text(pane.connectingMessage.isEmpty ? "Connecting to SFTP server..." : pane.connectingMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                if let conn = pane.remoteConnection {
                    Text(verbatim: "\(conn.formattedHostPort) (path: \(pane.remotePath))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text("Initializing SFTP session and fetching the file list...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            ProgressView()
                .scaleEffect(1.1)
                .padding(.vertical, 4)

            Button(action: onCancel) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text("Cancel Connection")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

public struct RemoteErrorView: View {
    let error: String
    @ObservedObject var pane: PaneModel

    public var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            VStack(spacing: 6) {
                Text(pane.isRemote ? "Remote connection failed" : "Could not open folder")
                    .font(.system(size: 15, weight: .bold))

                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 10) {
                Button("Retry") {
                    pane.reload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if pane.isRemote {
                    Button("Back to Local") {
                        pane.disconnectRemote()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
