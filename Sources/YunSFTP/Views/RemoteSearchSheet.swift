import SwiftUI

/// Recursive name search below the pane's current remote folder.
public struct RemoteSearchSheet: View {
    @ObservedObject var pane: PaneModel
    var onReveal: (RemoteFileItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [RemoteFileItem] = []
    @State private var isSearching = false
    @State private var searched = false
    @State private var task: Task<Void, Never>? = nil
    @FocusState private var fieldFocused: Bool

    public init(pane: PaneModel, onReveal: @escaping (RemoteFileItem) -> Void) {
        self.pane = pane
        self.onReveal = onReveal
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Name contains…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { search() }
                if isSearching {
                    ProgressView().controlSize(.small)
                    Button("Stop") { task?.cancel() }.controlSize(.small)
                } else {
                    Button("Search") { search() }.controlSize(.small).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)

            Text("Searching below \(pane.remotePath) on \(pane.remoteConnection?.displayTitle ?? "server"). Up to 500 results, 8 levels deep.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if results.isEmpty {
                VStack {
                    Spacer()
                    Text(searched && !isSearching ? "No matches" : "Type a name fragment and press Return")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(results) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.isDirectory ? "folder" : "doc")
                            .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.body).lineLimit(1)
                            Text((item.remotePath as NSString).deletingLastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(item.formattedSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onReveal(item); dismiss() }
                    .contextMenu { Button("Reveal in Pane") { onReveal(item); dismiss() } }
                }
                .listStyle(.inset)
            }

            HStack {
                Text(results.isEmpty ? "" : "\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
        .onAppear { fieldFocused = true }
    }

    private func search() {
        guard let conn = pane.remoteConnection else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        task?.cancel()
        isSearching = true
        searched = true
        results = []
        let root = pane.remotePath
        let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
        task = Task {
            let found = (try? await SFTPService.shared.search(root: root, query: q, connection: conn, password: pwd)) ?? []
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}
