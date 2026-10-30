import Foundation

/// Reads `Host` blocks from an OpenSSH client config (`~/.ssh/config`, including `Include`d files).
public enum SSHConfigImporter {

    public static var userConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
    }

    public static func importFromUserConfig() -> [RemoteConnection] {
        guard let text = try? String(contentsOf: userConfigURL, encoding: .utf8) else { return [] }
        return parse(text, baseDirectory: userConfigURL.deletingLastPathComponent())
    }

    /// Wildcard patterns (`*`, `?`, `!`) are skipped: they are defaults, not servers.
    public static func parse(_ text: String, baseDirectory: URL, depth: Int = 0) -> [RemoteConnection] {
        struct Block { var aliases: [String]; var hostName: String?; var user: String?; var port: Int?; var identityFile: String? }
        var blocks: [Block] = []
        var current: Block? = nil
        var included: [RemoteConnection] = []

        func flush() { if let b = current { blocks.append(b) }; current = nil }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // "Key value" or "Key=value"
            let parts = line.replacingOccurrences(of: "=", with: " ").split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let key = parts.first?.lowercased(), parts.count >= 2 else { continue }
            let value = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "host":
                flush()
                let aliases = parts.dropFirst().filter { !$0.contains("*") && !$0.contains("?") && !$0.hasPrefix("!") }
                current = aliases.isEmpty ? nil : Block(aliases: aliases, hostName: nil, user: nil, port: nil, identityFile: nil)
            case "match":
                flush()
            case "include":
                if depth < 3 {
                    for pattern in parts.dropFirst() {
                        for url in expand(includePattern: pattern, relativeTo: baseDirectory) {
                            if let sub = try? String(contentsOf: url, encoding: .utf8) {
                                included += parse(sub, baseDirectory: baseDirectory, depth: depth + 1)
                            }
                        }
                    }
                }
            case "hostname": current?.hostName = value
            case "user": current?.user = value
            case "port": current?.port = Int(value)
            case "identityfile": if current?.identityFile == nil { current?.identityFile = value }
            default: break
            }
        }
        flush()

        var result = included
        for b in blocks {
            for alias in b.aliases {
                let key = b.identityFile.map { expandTilde($0) }
                result.append(RemoteConnection(
                    name: alias,
                    connectionProtocol: .sftp,
                    host: b.hostName ?? alias,
                    port: b.port ?? 22,
                    username: b.user ?? "",
                    remotePath: "/",
                    authType: key != nil ? .sshKey : .password,
                    keyFilePath: key ?? ""
                ))
            }
        }
        return result
    }

    private static func expandTilde(_ path: String) -> String {
        return (path as NSString).expandingTildeInPath
    }

    private static func expand(includePattern pattern: String, relativeTo base: URL) -> [URL] {
        let expanded = expandTilde(pattern)
        let absolute = expanded.hasPrefix("/") ? expanded : base.appendingPathComponent(expanded).path
        var gt = glob_t()
        defer { globfree(&gt) }
        guard glob(absolute, 0, nil, &gt) == 0 else { return [] }
        return (0..<Int(gt.gl_matchc)).compactMap { i in
            gt.gl_pathv[i].flatMap { URL(fileURLWithPath: String(cString: $0)) }
        }
    }
}

/// Reads Cyberduck bookmark files (`*.duck`, plist dictionaries).
public enum CyberduckImporter {

    public static var bookmarksDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cyberduck/Bookmarks")
    }

    public static func importFromDisk() -> [RemoteConnection] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: bookmarksDirectory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "duck" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
            return connection(from: dict)
        }
    }

    /// Only SFTP bookmarks are imported; the app has no other transport.
    public static func connection(from dict: [String: Any]) -> RemoteConnection? {
        let proto = (dict["Protocol"] as? String ?? "").lowercased()
        guard proto == "sftp", let host = dict["Hostname"] as? String, !host.isEmpty else { return nil }
        let port = (dict["Port"] as? String).flatMap(Int.init) ?? (dict["Port"] as? Int) ?? 22
        let key = (dict["Private Key File"] as? String).map { ($0 as NSString).expandingTildeInPath }
        return RemoteConnection(
            name: (dict["Nickname"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? host,
            connectionProtocol: .sftp,
            host: host,
            port: port,
            username: dict["Username"] as? String ?? "",
            remotePath: (dict["Path"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "/",
            authType: key != nil ? .sshKey : .password,
            keyFilePath: key ?? ""
        )
    }
}
