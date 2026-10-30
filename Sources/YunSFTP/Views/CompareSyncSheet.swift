import SwiftUI

public struct CompareSyncSheet: View {
    @ObservedObject var leftPane: PaneModel
    @ObservedObject var rightPane: PaneModel
    @Environment(\.dismiss) private var dismiss

    @State private var comparisonResults: [DirectoryComparisonResult] = []
    @State private var isComparing: Bool = false
    @State private var isSyncing: Bool = false
    @State private var syncMessage: String? = nil

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare & Sync Panes")
                        .font(.headline)
                    Text("Left: \(leftPane.currentURL.lastPathComponent)  ↔  Right: \(rightPane.currentURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button("Refresh Comparison") {
                    runComparison()
                }
                .disabled(isComparing)
            }

            // Results Table
            if isComparing {
                VStack {
                    Spacer()
                    ProgressView("Comparing directories...")
                    Spacer()
                }
                .frame(height: 260)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Name").frame(width: 200, alignment: .leading)
                        Text("Left Pane").frame(width: 110, alignment: .leading)
                        Text("Right Pane").frame(width: 110, alignment: .leading)
                        Text("Status").frame(width: 110, alignment: .leading)
                        Spacer()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    List(comparisonResults) { res in
                        HStack {
                            Text(res.name)
                                .font(.subheadline)
                                .frame(width: 200, alignment: .leading)
                                .lineLimit(1)

                            Text(res.leftItem?.formattedSize ?? "--")
                                .font(.subheadline)
                                .frame(width: 110, alignment: .leading)

                            Text(res.rightItem?.formattedSize ?? "--")
                                .font(.subheadline)
                                .frame(width: 110, alignment: .leading)

                            statusBadge(res.status)
                                .frame(width: 110, alignment: .leading)

                            Spacer()
                        }
                    }
                    .frame(height: 240)
                }
                .border(Color.secondary.opacity(0.2))
            }

            if let msg = syncMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            // Sync Actions
            HStack {
                Button("Sync Left → Right") {
                    syncLeftToRight()
                }
                .disabled(isSyncing || isComparing)

                Button("Sync Right → Left") {
                    syncRightToLeft()
                }
                .disabled(isSyncing || isComparing)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 440)
        .onAppear {
            runComparison()
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: DirectoryComparisonResult.ComparisonStatus) -> some View {
        switch status {
        case .identical:
            Text("Identical")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        case .leftOnly:
            Text("Left Only")
                .font(.caption.weight(.bold))
                .foregroundColor(.blue)
        case .rightOnly:
            Text("Right Only")
                .font(.caption.weight(.bold))
                .foregroundColor(.orange)
        case .differentSize:
            Text("Diff Size")
                .font(.caption.weight(.bold))
                .foregroundColor(.red)
        case .differentDate:
            Text("Diff Date")
                .font(.caption.weight(.bold))
                .foregroundColor(.purple)
        }
    }

    private func runComparison() {
        isComparing = true
        let leftItems = leftPane.displayedItems
        let rightItems = rightPane.displayedItems
        let results = FileSystemService.compareItemLists(leftItems: leftItems, rightItems: rightItems)
        self.comparisonResults = results
        self.isComparing = false
    }

    private func syncItems(_ items: [FileItem], from srcPane: PaneModel, to dstPane: PaneModel) async {
        guard !items.isEmpty else { return }

        if !srcPane.isRemote && !dstPane.isRemote {
            let urls = items.map { $0.url }
            try? await FileSystemService.shared.copy(urls: urls, to: dstPane.currentURL, overwrite: true)
        } else if srcPane.isRemote && !dstPane.isRemote {
            guard let conn = srcPane.remoteConnection else { return }
            let pwd = srcPane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            for item in items {
                let remotePath = SFTPService.normalizeRemotePath(item.url.path)
                _ = try? await SFTPService.shared.download(remotePath: remotePath, to: dstPane.currentURL, connection: conn, password: pwd, overwrite: true)
            }
        } else if !srcPane.isRemote && dstPane.isRemote {
            guard let conn = dstPane.remoteConnection else { return }
            let pwd = dstPane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            let remoteDir = SFTPService.normalizeRemotePath(dstPane.remotePath)
            for item in items {
                try? await SFTPService.shared.upload(localURL: item.url, to: remoteDir, connection: conn, password: pwd, overwrite: true)
            }
        } else if srcPane.isRemote && dstPane.isRemote {
            guard let srcConn = srcPane.remoteConnection, let dstConn = dstPane.remoteConnection else { return }
            let srcPwd = srcPane.remotePassword ?? (srcConn.authType == .password ? KeychainService.shared.loadPassword(for: srcConn) : nil)
            let dstPwd = dstPane.remotePassword ?? (dstConn.authType == .password ? KeychainService.shared.loadPassword(for: dstConn) : nil)
            let remoteDir = SFTPService.normalizeRemotePath(dstPane.remotePath)
            for item in items {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpSync_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let remotePath = SFTPService.normalizeRemotePath(item.url.path)
                if let downloaded = try? await SFTPService.shared.download(remotePath: remotePath, to: tempDir, connection: srcConn, password: srcPwd) {
                    try? await SFTPService.shared.upload(localURL: downloaded, to: remoteDir, connection: dstConn, password: dstPwd, overwrite: true)
                }
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
    }

    private func syncLeftToRight() {
        isSyncing = true
        syncMessage = "Syncing Left to Right..."
        let itemsToSync = comparisonResults
            .filter { $0.status == .leftOnly || $0.status == .differentSize || $0.status == .differentDate }
            .compactMap { $0.leftItem }

        Task {
            await syncItems(itemsToSync, from: leftPane, to: rightPane)
            await MainActor.run {
                rightPane.reload()
                isSyncing = false
                syncMessage = "Sync Complete! (\(itemsToSync.count) items synced)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    runComparison()
                }
            }
        }
    }

    private func syncRightToLeft() {
        isSyncing = true
        syncMessage = "Syncing Right to Left..."
        let itemsToSync = comparisonResults
            .filter { $0.status == .rightOnly || $0.status == .differentSize || $0.status == .differentDate }
            .compactMap { $0.rightItem }

        Task {
            await syncItems(itemsToSync, from: rightPane, to: leftPane)
            await MainActor.run {
                leftPane.reload()
                isSyncing = false
                syncMessage = "Sync Complete! (\(itemsToSync.count) items synced)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    runComparison()
                }
            }
        }
    }
}
