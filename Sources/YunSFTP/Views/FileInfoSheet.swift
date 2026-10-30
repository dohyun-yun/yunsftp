import SwiftUI
import AppKit

public struct FileInfoSheet: View {
    let item: FileItem
    var pane: PaneModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var folderSize: Int64? = nil
    @State private var isCalculating = false
    @State private var sizeTask: Task<Void, Never>? = nil

    public var body: some View {
        VStack(spacing: 16) {
            // Header with Icon & Name
            HStack(spacing: 16) {
                Image(nsImage: FileIconProvider.shared.icon(for: item))
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.kindDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Details Grid
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Full Path", item.url.path)
                if item.isDirectory {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Size:")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        if let size = folderSize {
                            Text("\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) (\(size.formatted()) bytes)")
                                .font(.subheadline)
                                .textSelection(.enabled)
                        } else if isCalculating {
                            ProgressView().controlSize(.small)
                            Text("Calculating…").font(.subheadline).foregroundColor(.secondary)
                        } else {
                            Button("Calculate") { calculateFolderSize() }
                                .controlSize(.small)
                        }
                        Spacer()
                    }
                } else {
                    infoRow("Size", "\(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) (\(item.size.formatted()) bytes)")
                }
                infoRow("Modified", item.formattedDate)
                if let created = item.creationDate {
                    infoRow("Created", formatDate(created))
                }
                infoRow("Permissions", item.posixPermissions)
                if let target = item.symlinkTarget {
                    infoRow("Link Target", target)
                }
            }

            Spacer()

            // Action Buttons
            HStack {
                Button("Reveal in Finder") {
                    TerminalService.revealInFinder(url: item.url)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 360)
        .onDisappear { sizeTask?.cancel() }
    }

    private func calculateFolderSize() {
        isCalculating = true
        let url = item.url
        let remote = pane?.isRemote == true ? pane?.remoteConnection : nil
        let pwd = pane?.remotePassword
        sizeTask = Task {
            let size: Int64?
            if let conn = remote {
                size = try? await SFTPService.shared.directorySize(remotePath: SFTPService.normalizeRemotePath(url.path), connection: conn, password: pwd)
            } else {
                size = await Task.detached(priority: .userInitiated) { FileSystemService.directorySize(url) }.value
            }
            await MainActor.run {
                folderSize = size ?? 0
                isCalculating = false
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .lineLimit(3)

            Spacer()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
