import SwiftUI

/// Queue + history of every transfer, with per-row cancel and retry.
public struct TransfersWindowView: View {
    @ObservedObject private var manager: TransferManager = .shared

    public init() {}

    private var active: [TransferTaskItem] { manager.transfers.filter { $0.state == .inProgress || $0.state == .queued } }
    private var finished: [TransferTaskItem] { manager.transfers.filter { !($0.state == .inProgress || $0.state == .queued) }.reversed() }

    public var body: some View {
        VStack(spacing: 0) {
            if manager.transfers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No transfers yet")
                        .font(.title3)
                    Text("Copies, moves, uploads and downloads appear here. Finished items stay until you clear them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !active.isEmpty {
                        Section("In progress (\(active.count))") {
                            ForEach(active) { TransferRow(item: $0) }
                        }
                    }
                    if !finished.isEmpty {
                        Section("Finished (\(finished.count))") {
                            ForEach(finished) { TransferRow(item: $0) }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button("Cancel All") { manager.cancelAll() }
                    .disabled(active.isEmpty)
                Spacer()
                Button("Clear Finished") { manager.clearCompleted() }
                    .disabled(finished.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 520, minHeight: 320)
    }
}

struct TransferRow: View {
    let item: TransferTaskItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.direction.systemImage)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.direction.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.state == .inProgress || item.state == .queued {
                    HStack(spacing: 8) {
                        ProgressView(value: max(0.01, item.progress), total: 1.0)
                            .frame(maxWidth: 260)
                        if item.totalBytes > 0 {
                            Text("\(ByteCountFormatter.string(fromByteCount: item.bytesTransferred, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(item.statusMessage)
                        .font(.caption)
                        .foregroundStyle(item.state.isFailed ? Color.red : Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            switch item.state {
            case .inProgress, .queued:
                Button {
                    TransferManager.shared.cancelTransfer(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .accessibilityLabel("Cancel \(item.fileName)")
            case .failed, .cancelled:
                if TransferCoordinator.shared.canRetry(taskID: item.id) {
                    Button("Retry") { TransferCoordinator.shared.retry(taskID: item.id) }
                        .controlSize(.small)
                }
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch item.state {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .accentColor
        }
    }
}
