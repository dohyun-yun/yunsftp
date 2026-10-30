import SwiftUI

public struct DualPaneView: View {
    @ObservedObject var leftPane: PaneModel
    @ObservedObject var rightPane: PaneModel
    @Binding var isDualPane: Bool
    @Binding var activePaneId: UUID

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

    public var body: some View {
        HSplitView {
            FilePaneView(
                pane: leftPane,
                isActive: activePaneId == leftPane.id,
                onActivate: { activePaneId = leftPane.id },
                onOpenItem: onOpenItem,
                onShowInfo: onShowInfo,
                onQuickLook: onQuickLook,
                onRename: onRename,
                onChmod: onChmod,
                onCopyToOtherPane: onCopyToOtherPane,
                onMoveToOtherPane: onMoveToOtherPane,
                onTrashItems: onTrashItems,
                onCompressItems: onCompressItems,
                onExtractArchive: onExtractArchive,
                onConnect: onConnect
            )
            .frame(minWidth: 280)

            if isDualPane {
                FilePaneView(
                    pane: rightPane,
                    isActive: activePaneId == rightPane.id,
                    onActivate: { activePaneId = rightPane.id },
                    onOpenItem: onOpenItem,
                    onShowInfo: onShowInfo,
                    onQuickLook: onQuickLook,
                    onRename: onRename,
                    onChmod: onChmod,
                    onCopyToOtherPane: onCopyToOtherPane,
                    onMoveToOtherPane: onMoveToOtherPane,
                    onTrashItems: onTrashItems,
                    onCompressItems: onCompressItems,
                    onExtractArchive: onExtractArchive,
                    onConnect: onConnect
                )
                .frame(minWidth: 280)
            }
        }
    }
}
