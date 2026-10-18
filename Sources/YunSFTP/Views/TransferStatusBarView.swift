import SwiftUI

public struct TransferStatusBarView: View {
    @ObservedObject var transferManager: TransferManager = .shared

    public init() {}

    public var body: some View {
        if transferManager.isVisible, let current = transferManager.currentTransfer {
            VStack(spacing: 0) {
                switch current.state {
                case .failed(let err):
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transfer Failed: \(current.fileName)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Dismiss") {
                            transferManager.clearCompleted()
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.12))

                case .completed:
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transfer Complete: \(current.fileName)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                            let totalStr = current.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: current.totalBytes, countStyle: .file) : ""
                            Text(totalStr.isEmpty ? "Finished successfully" : "\(totalStr) transferred")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        ProgressView(value: 1.0, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.green)
                            .frame(maxWidth: 160)

                        Button(action: { transferManager.clearCompleted() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))

                case .cancelled:
                    HStack(spacing: 10) {
                        Image(systemName: "nosign")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)

                        Text("Cancelled: \(current.fileName)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)

                        Spacer()

                        Button("Dismiss") {
                            transferManager.clearCompleted()
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))

                case .inProgress, .queued:
                    HStack(spacing: 10) {
                        Image(systemName: current.direction.systemImage)
                            .font(.system(size: 15))
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(current.direction.rawValue)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.accentColor)

                                Text(current.fileName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if transferManager.transfers.count > 1 {
                                    let activeCount = transferManager.transfers.filter { $0.state == .inProgress || $0.state == .queued }.count
                                    Text("(\(activeCount) items in queue)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                if current.totalBytes > 0 {
                                    ProgressView(value: max(0.01, current.progress), total: 1.0)
                                        .progressViewStyle(.linear)
                                        .frame(maxWidth: 240)

                                    let doneStr = ByteCountFormatter.string(fromByteCount: current.bytesTransferred, countStyle: .file)
                                    let totalStr = ByteCountFormatter.string(fromByteCount: current.totalBytes, countStyle: .file)
                                    Text("\(doneStr) / \(totalStr) (\(Int(current.progress * 100))%)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                    Text(current.statusMessage)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        Button(action: {
                            transferManager.cancelTransfer(id: current.id)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel Transfer")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
                }

                Divider()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
