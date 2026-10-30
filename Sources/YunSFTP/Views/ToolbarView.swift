import SwiftUI

/// Main window toolbar. Six primary actions are visible by default; everything else lives in the
/// "More" menu and can be dragged in through View > Customize Toolbar.
public struct ToolbarView: CustomizableToolbarContent {
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

    public static let primaryItemIDs = ["connect", "copy", "move", "newFolder", "delete", "quickLook", "more"]
    public static let secondaryItemIDs = ["dualPane", "refresh", "permissions", "batchRename", "sync", "terminal", "info"]

    public var body: some CustomizableToolbarContent {
        ToolbarItem(id: "connect") {
            Button(action: onConnect) { Label("Connect", systemImage: "network") }
                .help("Connect to Server (Cmd+K)")
        }
        ToolbarItem(id: "copy") {
            Button(action: onCopyToOtherPane) { Label("Copy to Other Pane", systemImage: "doc.on.doc") }
                .help("Copy selected items to the other pane (F5)")
        }
        ToolbarItem(id: "move") {
            Button(action: onMoveToOtherPane) { Label("Move to Other Pane", systemImage: "arrow.right.doc.on.clipboard") }
                .help("Move selected items to the other pane (F6)")
        }
        ToolbarItem(id: "newFolder") {
            Button(action: onNewFolder) { Label("New Folder", systemImage: "folder.badge.plus") }
                .help("Create New Folder (Cmd+Shift+N)")
        }
        ToolbarItem(id: "delete") {
            Button(action: onDelete) { Label("Delete", systemImage: "trash") }
                .help("Move to Trash / delete on server (Cmd+Backspace)")
        }
        ToolbarItem(id: "quickLook") {
            Button(action: onQuickLook) { Label("Quick Look", systemImage: "eye") }
                .help("Quick Look / Preview (Cmd+Y)")
        }
        ToolbarItem(id: "more") {
            Menu {
                Button(action: onToggleDualPane) {
                    Label(isDualPane ? "Single Pane" : "Dual Pane", systemImage: isDualPane ? "rectangle" : "rectangle.split.2x1")
                }
                Button(action: onRefresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                Divider()
                Button(action: onGetInfo) { Label("Get Info", systemImage: "info.circle") }
                Button(action: onChmod) { Label("Permissions…", systemImage: "lock.shield") }
                Button(action: onBatchRename) { Label("Multi-Rename…", systemImage: "character.cursor.ibeam") }
                Button(action: onCompareSync) { Label("Compare & Sync…", systemImage: "arrow.triangle.2.circlepath") }
                Divider()
                Button(action: onOpenTerminal) { Label("Open in Terminal", systemImage: "terminal") }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More actions")
        }

        // Optional items: hidden until the user adds them via View > Customize Toolbar.
        ToolbarItem(id: "dualPane", showsByDefault: false) {
            Button(action: onToggleDualPane) {
                Label("Dual Pane", systemImage: isDualPane ? "rectangle.split.2x1" : "rectangle")
            }
            .help("Toggle Dual Pane Mode")
        }
        ToolbarItem(id: "refresh", showsByDefault: false) {
            Button(action: onRefresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh Active Pane (Cmd+R)")
        }
        ToolbarItem(id: "permissions", showsByDefault: false) {
            Button(action: onChmod) { Label("Permissions", systemImage: "lock.shield") }
                .help("Change Permissions (chmod)")
        }
        ToolbarItem(id: "batchRename", showsByDefault: false) {
            Button(action: onBatchRename) { Label("Multi-Rename", systemImage: "character.cursor.ibeam") }
                .help("Multi-Rename selected files")
        }
        ToolbarItem(id: "sync", showsByDefault: false) {
            Button(action: onCompareSync) { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .help("Compare & Sync Panes")
        }
        ToolbarItem(id: "terminal", showsByDefault: false) {
            Button(action: onOpenTerminal) { Label("Terminal", systemImage: "terminal") }
                .help("Open Current Folder in Terminal")
        }
        ToolbarItem(id: "info", showsByDefault: false) {
            Button(action: onGetInfo) { Label("Info", systemImage: "info.circle") }
                .help("Get Info (Cmd+I)")
        }
    }
}
