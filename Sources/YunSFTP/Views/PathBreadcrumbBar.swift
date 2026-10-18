import SwiftUI

public struct PathBreadcrumbBar: View {
    @ObservedObject var pane: PaneModel
    @State private var isEditingPath = false
    @State private var customPathText = ""

    public var body: some View {
        HStack(spacing: 6) {
            // Back & Forward buttons
            HStack(spacing: 2) {
                Button(action: { pane.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .disabled(!pane.canGoBack)
                .buttonStyle(.plain)
                .help("Back (Cmd+[)")

                Button(action: { pane.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .disabled(!pane.canGoForward)
                .buttonStyle(.plain)
                .help("Forward (Cmd+])")

                Button(action: { pane.goUp() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .disabled(!pane.canGoUp)
                .buttonStyle(.plain)
                .help("Enclosing Folder (Cmd+Up)")
            }
            .padding(.trailing, 4)

            Divider()
                .frame(height: 14)

            if pane.isRemote, let conn = pane.remoteConnection {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: .green.opacity(0.8), radius: 2)

                    Image(systemName: "network")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)

                    Text(conn.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Button(action: { pane.disconnectRemote() }) {
                        Image(systemName: "eject")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.green.opacity(0.08))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.green.opacity(0.35), lineWidth: 0.8)
                )

                Divider()
                    .frame(height: 14)
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)

                    Image(systemName: "internaldrive")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text("Local")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.8)
                )

                Divider()
                    .frame(height: 14)
            }

            // Path Breadcrumbs or Text Field
            if isEditingPath {
                HStack {
                    TextField("Enter path...", text: $customPathText, onCommit: {
                        applyCustomPath()
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                    Button("Go") {
                        applyCustomPath()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Cancel") {
                        isEditingPath = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(pathComponents, id: \.url) { item in
                                Button(action: {
                                    if pane.isRemote, let rPath = item.remotePath {
                                        pane.navigateToRemote(path: rPath)
                                    } else {
                                        pane.navigateTo(item.url)
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        if item.isRoot {
                                            Image(systemName: pane.isRemote ? "server.rack" : "internaldrive")
                                                .font(.system(size: 11))
                                                .foregroundColor(pane.isRemote ? .accentColor : .secondary)
                                        } else if item.isHome {
                                            Image(systemName: "house")
                                                .font(.system(size: 11))
                                        }
                                        Text(item.name)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)

                                if item.url != pane.currentURL {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                            }

                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("breadcrumbEnd")
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo("breadcrumbEnd", anchor: .trailing)
                        }
                    }
                    .onChange(of: pane.currentURL) { _ in
                        DispatchQueue.main.async {
                            proxy.scrollTo("breadcrumbEnd", anchor: .trailing)
                        }
                    }
                    .onTapGesture(count: 2) {
                        customPathText = pane.isRemote ? pane.remotePath : pane.currentURL.path
                        isEditingPath = true
                    }
                }
            }

            Spacer()

            // Path Edit toggle button
            Button(action: {
                if !isEditingPath {
                    customPathText = pane.isRemote ? pane.remotePath : pane.currentURL.path
                }
                isEditingPath.toggle()
            }) {
                Image(systemName: isEditingPath ? "xmark" : "character.cursor.ibeam")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit path manually")

            // Reload button
            Button(action: { pane.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reload folder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private struct PathItem {
        let name: String
        let url: URL
        let isRoot: Bool
        let isHome: Bool
        var remotePath: String? = nil
    }

    private var pathComponents: [PathItem] {
        if pane.isRemote, let conn = pane.remoteConnection {
            var items: [PathItem] = []
            let serverURL = SFTPService.sftpURL(host: conn.host, port: conn.port, path: "/")
            items.append(PathItem(name: conn.displayTitle, url: serverURL, isRoot: true, isHome: false, remotePath: "/"))

            let cleanPath = SFTPService.decodeLsEscapes(pane.remotePath).precomposedStringWithCanonicalMapping
            let segments = cleanPath.split(separator: "/").map(String.init)
            var currentPath = ""
            for seg in segments {
                let cleanSeg = SFTPService.decodeLsEscapes(seg)
                currentPath += "/" + cleanSeg
                let itemURL = SFTPService.sftpURL(host: conn.host, port: conn.port, path: currentPath)
                items.append(PathItem(name: cleanSeg, url: itemURL, isRoot: false, isHome: false, remotePath: currentPath))
            }
            return items
        }

        var items: [PathItem] = []
        var current = pane.currentURL.standardized
        let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardized

        var components: [URL] = []
        while true {
            components.append(current)
            let parent = current.deletingLastPathComponent().standardized
            if parent == current || current.path == "/" {
                break
            }
            current = parent
        }
        components.reverse()

        for url in components {
            let isRoot = (url.path == "/")
            let isHome = (url == homeURL)
            let name = isRoot ? "Macintosh HD" : (isHome ? "Home" : url.lastPathComponent)
            items.append(PathItem(name: name, url: url, isRoot: isRoot, isHome: isHome))
        }

        return items
    }

    private func applyCustomPath() {
        if pane.isRemote {
            var path = customPathText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.hasPrefix("/") {
                path = "/" + path
            }
            let cleanPath = SFTPService.decodeLsEscapes(path).precomposedStringWithCanonicalMapping
            pane.navigateToRemote(path: cleanPath)
            isEditingPath = false
            return
        }

        var path = customPathText.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            path = home + path.dropFirst()
        }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            pane.navigateTo(url)
            isEditingPath = false
        }
    }
}
