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
    var onConnect: (() -> Void)? = nil
    var stack: PaneStack? = nil

    @State private var isDropTarget: Bool = false
    @AppStorage("yunsftp_welcomeDismissed") private var welcomeDismissed: Bool = false
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @FocusState private var isFilterFocused: Bool

    public var body: some View {
        VStack(spacing: 0) {
            if let stack, stack.tabs.count > 1 {
                PaneTabBar(stack: stack, onActivate: onActivate)
                Divider()
            }

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
                        .font(.subheadline)
                        .foregroundColor(pane.shouldShowFilter ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(L("Filter this folder (Cmd+F)"))
                .accessibilityLabel(L("Filter"))

                if pane.shouldShowFilter {
                    HStack(spacing: 4) {
                        TextField(L("Filter..."), text: $pane.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .focused($isFilterFocused)
                            .onTapGesture { onActivate() }
                            .onExitCommand { pane.toggleFilter() }
                        if !pane.searchQuery.isEmpty {
                            Button(action: { pane.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
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
                    Image(systemName: "tablecells").tag(ViewMode.table)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .help(L("List, table or icon view"))
                .onChange(of: pane.viewMode) { _ in onActivate() }

                // Hidden files toggle
                Button(action: {
                    onActivate()
                    pane.showHiddenFiles.toggle()
                }) {
                    Image(systemName: pane.showHiddenFiles ? "eye.fill" : "eye.slash")
                        .font(.subheadline)
                        .foregroundColor(pane.showHiddenFiles ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(L("Toggle Hidden Files (Cmd+Shift+.)"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .onTapGesture { onActivate() }

            Divider()

            if WelcomeBanner.shouldShow(connectionsEmpty: connectionManager.connections.isEmpty, dismissed: welcomeDismissed, isRemote: pane.isRemote, isActive: isActive) {
                WelcomeBanner(
                    onConnect: { onConnect?() },
                    onImport: { _ = connectionManager.importFromSSHConfig() },
                    onDismiss: { welcomeDismissed = true }
                )
                Divider()
            }

            if let error = pane.errorMessage, !pane.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { pane.errorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
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
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = pane.errorMessage, pane.items.isEmpty {
                    RemoteErrorView(error: error, pane: pane)
                } else if pane.viewMode == .table {
                    FileTableView(
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
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(pane.freeDiskSpaceDescription)
                    .font(.caption)
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

/// First-run hint shown in the active local pane until a server exists or it is dismissed.
public struct WelcomeBanner: View {
    var onConnect: () -> Void
    var onImport: () -> Void
    var onDismiss: () -> Void

    public static func shouldShow(connectionsEmpty: Bool, dismissed: Bool, isRemote: Bool, isActive: Bool) -> Bool {
        return connectionsEmpty && !dismissed && !isRemote && isActive
    }

    private var hasSSHConfig: Bool { FileManager.default.fileExists(atPath: SSHConfigImporter.userConfigURL.path) }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Add your first server"))
                    .font(.subheadline.weight(.semibold))
                Text("Press ⌘K to add a connection\(hasSSHConfig ? ", or import the hosts from ~/.ssh/config." : ".") Drag files between the two panes or press F5 to copy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if hasSSHConfig {
                Button(L("Import from ssh config"), action: onImport)
                    .controlSize(.small)
            }
            Button(L("Connect…"), action: onConnect)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Dismiss"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
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
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                if let conn = pane.remoteConnection {
                    Text(verbatim: "\(conn.formattedHostPort) (path: \(pane.remotePath))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text(L("Initializing SFTP session and fetching the file list..."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ProgressView()
                .scaleEffect(1.1)
                .padding(.vertical, 4)

            Button(action: onCancel) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text(L("Cancel Connection"))
                }
                .font(.callout)
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
                    .font(.title3.weight(.bold))

                Text(error)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 10) {
                Button(L("Retry")) {
                    pane.reload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if pane.isRemote {
                    Button(L("Back to Local")) {
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
