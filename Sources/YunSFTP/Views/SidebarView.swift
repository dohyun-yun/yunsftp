import SwiftUI
import AppKit

public struct SidebarView: View {
    @Binding var customFavorites: [FavoriteLocation]
    @ObservedObject var connectionManager = ConnectionManager.shared
    @State private var hoveredConnectionId: UUID? = nil
    var connectedConnectionIds: Set<UUID> = []
    var onSelectLocation: (URL) -> Void
    var onOpenConnection: (RemoteConnection) -> Void
    var onEditConnection: (RemoteConnection) -> Void
    var onTestConnection: ((RemoteConnection) -> Void)? = nil
    var onManageConnections: () -> Void
    var onOpenRemotePath: ((RemoteConnection, String) -> Void)? = nil
    @ObservedObject private var bookmarkStore = BookmarkStore.shared

    public var body: some View {
        List {
            // Favorites
            Section(header: Text(L("Favorites")).font(.subheadline.weight(.semibold))) {
                ForEach(FavoriteLocation.defaultFavorites) { fav in
                    SidebarItemRow(name: fav.name, iconName: fav.systemIconName) {
                        onSelectLocation(fav.url)
                    }
                }

                ForEach(customFavorites) { fav in
                    SidebarItemRow(name: fav.name, iconName: fav.systemIconName) {
                        onSelectLocation(fav.url)
                    }
                    .contextMenu {
                        Button(L("Remove from Favorites")) {
                            customFavorites.removeAll { $0.id == fav.id }
                        }
                    }
                }
            }

            // Remote Connections (SSH / SFTP / FTP)
            Section(
                header: HStack {
                    Text(L("Connections")).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(action: onManageConnections) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Manage Connections (Cmd+K)"))
                }
            ) {
                if connectionManager.connections.isEmpty {
                    if FileManager.default.fileExists(atPath: SSHConfigImporter.userConfigURL.path) {
                        Button(action: { _ = connectionManager.importFromSSHConfig() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                Text(L("Import from ~/.ssh/config"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                    Button(action: onManageConnections) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text(L("Add Connection..."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                } else {
                    ForEach(connectionManager.connections) { conn in
                        HStack(spacing: 6) {
                            Button(action: { onOpenConnection(conn) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: conn.connectionProtocol.systemIconName)
                                        .font(.callout)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(conn.displayTitle)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Text(verbatim: conn.formattedHostPort)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 2)

                                    if connectedConnectionIds.contains(conn.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 7, height: 7)
                                            .accessibilityLabel(L("Connected"))
                                            .help(L("Connected"))
                                    } else if conn.isImportedFromForkLift2 {
                                        Image(systemName: "arrow.triangle.merge")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button(action: { onEditConnection(conn) }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 18, height: 18)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(L("Edit Connection..."))
                            .accessibilityLabel("Edit \(conn.displayTitle)")
                            .opacity(hoveredConnectionId == conn.id ? 1 : 0)
                        }
                        .padding(.vertical, 2)
                        .onHover { hovering in
                            hoveredConnectionId = hovering ? conn.id : (hoveredConnectionId == conn.id ? nil : hoveredConnectionId)
                        }
                        .contextMenu {
                            Button(L("Connect")) {
                                onOpenConnection(conn)
                            }
                            Button(L("Edit Connection...")) {
                                onEditConnection(conn)
                            }
                            Button(L("Test Connection...")) {
                                if let onTest = onTestConnection {
                                    onTest(conn)
                                } else {
                                    onEditConnection(conn)
                                }
                            }
                            Button(L("Duplicate Connection")) {
                                connectionManager.duplicateConnection(conn)
                            }
                            Button(L("Open in Terminal SSH")) {
                                connectionManager.openSSHTerminal(for: conn)
                            }
                            let recent = bookmarkStore.recents(for: conn.id)
                            if !recent.isEmpty {
                                Menu("Recent Folders") {
                                    ForEach(recent, id: \.self) { path in
                                        Button(path) { onOpenRemotePath?(conn, path) }
                                    }
                                }
                            }
                            Divider()
                            Button(L("Delete"), role: .destructive) {
                                KeychainService.shared.deletePassword(for: conn)
                                connectionManager.deleteConnection(id: conn.id)
                                bookmarkStore.forget(connectionID: conn.id)
                            }
                        }

                        ForEach(bookmarkStore.bookmarks(for: conn.id)) { bm in
                            Button(action: { onOpenRemotePath?(conn, bm.path) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 16)
                                    Text(bm.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 22)
                            .help(bm.path)
                            .contextMenu {
                                Button(L("Remove Bookmark")) { bookmarkStore.remove(id: bm.id) }
                            }
                        }
                    }
                }
            }

            // Devices
            Section(header: Text(L("Devices")).font(.subheadline.weight(.semibold))) {
                if DemoHelper.isDemoMode {
                    SidebarItemRow(name: "Macintosh HD", iconName: "internaldrive") {
                        onSelectLocation(URL(fileURLWithPath: "/"))
                    }
                } else {
                    ForEach(FavoriteLocation.mountedVolumes) { vol in
                        SidebarItemRow(name: vol.name, iconName: vol.systemIconName) {
                            onSelectLocation(vol.url)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: addCustomFolder) {
                    Label(L("Add Folder..."), systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(8)
                Spacer()
            }
        }
    }

    private func addCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let fav = FavoriteLocation(name: url.lastPathComponent, url: url, systemIconName: "folder.fill", isCustom: true)
            if !customFavorites.contains(where: { $0.url == url }) {
                customFavorites.append(fav)
            }
        }
    }
}

private struct SidebarItemRow: View {
    let name: String
    let iconName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.body)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)

                Text(name)
                    .font(.callout)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
