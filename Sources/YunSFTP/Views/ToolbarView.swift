import SwiftUI

public struct ToolbarView: View {
    @Binding var isDualPane: Bool
    var onToggleDualPane: () -> Void
    var onConnect: () -> Void
    var onCopyToOtherPane: () -> Void
    var onMoveToOtherPane: () -> Void
    var onRefresh: () -> Void
    var onNewFolder: () -> Void
    var onDelete: () -> Void
    var onChmod: () -> Void
    var onQuickLook: () -> Void
    var onBatchRename: () -> Void
    var onCompareSync: () -> Void
    var onOpenTerminal: () -> Void
    var onGetInfo: () -> Void

    public var body: some View {
        HStack(spacing: 6) {
            // Dual / Single Pane Toggle
            Button(action: onToggleDualPane) {
                Label("Dual Pane", systemImage: isDualPane ? "rectangle.split.2x1" : "rectangle")
            }
            .help("Toggle Dual Pane Mode")

            Divider().frame(height: 16)

            // Connect button
            Button(action: onConnect) {
                Label("Connect", systemImage: "network")
            }
            .help("Connect to Server (Cmd+K)")

            Divider().frame(height: 16)

            // Copy to other pane
            Button(action: onCopyToOtherPane) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy selected items to the other pane (F5)")

            // Move to other pane
            Button(action: onMoveToOtherPane) {
                Label("Move", systemImage: "arrow.right.doc.on.clipboard")
            }
            .help("Move selected items to the other pane (F6)")

            // Refresh
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh Active Pane (Cmd+R)")

            Divider().frame(height: 16)

            // New Folder
            Button(action: onNewFolder) {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .help("Create New Folder (Cmd+Shift+N)")

            // Delete
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .help("Move to Trash (Cmd+Backspace)")

            // Permissions (chmod)
            Button(action: onChmod) {
                Label("Permissions", systemImage: "lock.shield")
            }
            .help("Change Permissions (chmod)")

            Divider().frame(height: 16)

            // Quick Look
            Button(action: onQuickLook) {
                Label("Quick Look", systemImage: "eye")
            }
            .help("Quick Look / Preview (Cmd+Y)")

            // Batch Rename
            Button(action: onBatchRename) {
                Label("Multi-Rename", systemImage: "character.cursor.ibeam")
            }
            .help("Multi-Rename selected files")

            // Compare / Sync
            Button(action: onCompareSync) {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Compare & Sync Panes")

            // Terminal
            Button(action: onOpenTerminal) {
                Label("Terminal", systemImage: "terminal")
            }
            .help("Open Current Folder in Terminal")

            // Info
            Button(action: onGetInfo) {
                Label("Info", systemImage: "info.circle")
            }
            .help("Get Info (Cmd+I)")
        }
    }
}
