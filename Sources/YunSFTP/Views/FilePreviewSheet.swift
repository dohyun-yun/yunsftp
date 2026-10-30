import SwiftUI
import AppKit

public struct FilePreviewSheet: View {
    let item: FileItem
    var pane: PaneModel? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var textContent: String = ""
    @State private var isTextEditable: Bool = false
    @State private var isSaving: Bool = false
    @State private var isLoading: Bool = false
    @State private var hasChanges: Bool = false
    @State private var image: NSImage? = nil
    @State private var localPreviewURL: URL? = nil
    @State private var errorMessage: String? = nil

    private let textExtensions: Set<String> = [
        "txt", "md", "swift", "py", "sh", "zsh", "bash", "js", "ts", "json",
        "xml", "html", "css", "yaml", "yml", "toml", "c", "cpp", "h", "m",
        "plist", "log", "conf", "ini", "env", "sql", "rb", "go", "rs", "java"
    ]

    private let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "ico", "icns", "webp", "heic"
    ]

    public init(item: FileItem, pane: PaneModel? = nil) {
        self.item = item
        self.pane = pane
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Image(nsImage: FileIconProvider.shared.icon(for: item))
                    .resizable()
                    .frame(width: 20, height: 20)

                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)

                if pane?.isRemote == true {
                    Text("SFTP")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }

                Spacer()

                if isTextEditable && hasChanges {
                    Button(isSaving ? "Saving..." : "Save Changes") {
                        saveText()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }

                Button("Open in Default App") {
                    openInDefaultApp()
                }
                .disabled(isLoading)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                Divider()
            }

            // Preview Content
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Loading preview for \(item.name)...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if imageExtensions.contains(item.fileExtension), let img = image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                } else if isTextEditable {
                    TextEditor(text: $textContent)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(6)
                        .onChange(of: textContent) { _ in
                            hasChanges = true
                        }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(nsImage: FileIconProvider.shared.icon(for: item))
                            .resizable()
                            .frame(width: 80, height: 80)
                        Text(item.name)
                            .font(.title3)
                        Text(item.formattedSize)
                            .foregroundColor(.secondary)
                        Text("No direct text/image preview available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Open with System Viewer") {
                            openInDefaultApp()
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear {
            loadPreview()
        }
    }

    private func loadPreview() {
        if let pane = pane, pane.isRemote, let conn = pane.remoteConnection {
            isLoading = true
            let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpQuickLook", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let remotePath = SFTPService.normalizeRemotePath(item.url.path)

            Task {
                do {
                    let downloadedURL = try await SFTPService.shared.download(remotePath: remotePath, to: tempDir, connection: conn, password: pwd)
                    await MainActor.run {
                        self.localPreviewURL = downloadedURL
                        self.loadFromLocalURL(downloadedURL)
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Preview download failed: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }
        } else {
            self.localPreviewURL = item.url
            loadFromLocalURL(item.url)
        }
    }

    private func loadFromLocalURL(_ url: URL) {
        if imageExtensions.contains(item.fileExtension) {
            if let img = NSImage(contentsOf: url) {
                self.image = img
            }
        } else if textExtensions.contains(item.fileExtension) {
            if let string = try? String(contentsOf: url, encoding: .utf8) {
                self.textContent = string
                self.isTextEditable = true
                self.hasChanges = false
            }
        } else if !item.isDirectory {
            if item.size < 500_000, let string = try? String(contentsOf: url, encoding: .utf8) {
                self.textContent = string
                self.isTextEditable = true
                self.hasChanges = false
            }
        }
    }

    private func openInDefaultApp() {
        if let url = localPreviewURL {
            TerminalService.openItem(url: url)
            dismiss()
        } else if pane?.isRemote != true {
            TerminalService.openItem(url: item.url)
            dismiss()
        }
    }

    private func saveText() {
        guard let targetURL = localPreviewURL else { return }
        isSaving = true
        errorMessage = nil

        if let pane = pane, pane.isRemote, let conn = pane.remoteConnection {
            let pwd = pane.remotePassword ?? (conn.authType == .password ? KeychainService.shared.loadPassword(for: conn) : nil)
            let remotePath = SFTPService.normalizeRemotePath(item.url.path)
            let remoteParent = (remotePath as NSString).deletingLastPathComponent
            let contentToSave = textContent

            Task {
                do {
                    try contentToSave.write(to: targetURL, atomically: true, encoding: .utf8)
                    try await SFTPService.shared.upload(localURL: targetURL, to: remoteParent.isEmpty ? "/" : remoteParent, connection: conn, password: pwd, overwrite: true)
                    await MainActor.run {
                        hasChanges = false
                        isSaving = false
                        pane.reload()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Remote save failed: \(error.localizedDescription)"
                        isSaving = false
                    }
                }
            }
        } else {
            do {
                try textContent.write(to: targetURL, atomically: true, encoding: .utf8)
                hasChanges = false
                pane?.reload()
            } catch {
                errorMessage = "Save failed: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}
