import SwiftUI

public struct DualPaneView: View {
    @ObservedObject var leftStack: PaneStack
    @ObservedObject var rightStack: PaneStack
    @Binding var isDualPane: Bool
    @Binding var activeSide: PaneSide

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
                pane: leftStack.current,
                isActive: activeSide == .left || !isDualPane,
                onActivate: { activeSide = .left },
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
                onConnect: onConnect,
                stack: leftStack
            )
            .id(leftStack.current.id)
            .frame(minWidth: 280)

            if isDualPane {
                FilePaneView(
                    pane: rightStack.current,
                    isActive: activeSide == .right,
                    onActivate: { activeSide = .right },
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
                    onConnect: onConnect,
                    stack: rightStack
                )
                .id(rightStack.current.id)
                .frame(minWidth: 280)
            }
        }
    }
}
