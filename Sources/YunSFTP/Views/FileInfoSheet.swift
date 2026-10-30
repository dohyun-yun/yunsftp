import SwiftUI
import AppKit

public struct FileInfoSheet: View {
    let item: FileItem
    @Environment(\.dismiss) private var dismiss

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
                infoRow("Size", item.isDirectory ? "--" : "\(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) (\(item.size.formatted()) bytes)")
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
