import Foundation

public struct MigrationResult: Sendable {
    public let importedConnections: [RemoteConnection]
    public let importedFavorites: [FavoriteLocation]
    public let importedSettings: AppSettings?
    public let sourceFound: Bool
}

public struct MigrationService: Sendable {
    public static let shared = MigrationService()

    private let forkLift2PlistPath = ("~/Library/Preferences/com.binarynights.ForkLift2.plist" as NSString).expandingTildeInPath

    public func hasForkLift2Data() -> Bool {
        return FileManager.default.fileExists(atPath: forkLift2PlistPath)
    }

    /// ForkLift 2 stores SFTP bookmarks as type 200; anything else on port 22 is treated as SFTP too.
    static func importedProtocol(type: Int, port: Int) -> ConnectionProtocol {
        return (type == 200 || port == 22) ? .sftp : .ftp
    }

    static func importedConnectionName(host: String) -> String {
        let first = host.components(separatedBy: ".").first ?? host
        return first.isEmpty ? host : first.capitalized
    }

    public func migrateFromForkLift2() -> MigrationResult {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: forkLift2PlistPath)),
              let rootDict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return MigrationResult(importedConnections: [], importedFavorites: [], importedSettings: nil, sourceFound: false)
        }

        var connections: [RemoteConnection] = []
        var favorites: [FavoriteLocation] = []

        // Parse view settings
        var settings = AppSettings()
        if let viewSettings = rootDict["FileViewSettings"] as? [String: Any] {
            if let sortKey = viewSettings["sortKey"] as? String {
                switch sortKey {
                case "dateModified": settings.sortField = .date
                case "displayName", "name": settings.sortField = .name
                case "size": settings.sortField = .size
                case "kind": settings.sortField = .kind
                default: settings.sortField = .name
                }
            }
            if let sortAsc = viewSettings["sortAscending"] as? Int {
                settings.sortAscending = (sortAsc != 0)
            }
            if let groupFolders = viewSettings["groupFolders"] as? Int {
                settings.groupFolders = (groupFolders != 0)
            }
            if let fontSize = viewSettings["fontSize"] as? Double {
                settings.fontSize = fontSize
            }
            if let viewModeInt = viewSettings["ViewMode"] as? Int {
                settings.viewMode = (viewModeInt == 0) ? .grid : .list
            }
        }

        // Parse custom tools
        if let toolsArray = rootDict["Tools"] as? [[String: Any]] {
            for t in toolsArray {
                if let title = t["title"] as? String,
                   let exec = t["executablePath"] as? String {
                    settings.tools.append(CustomTool(title: title, executablePath: exec))
                }
            }
        }
        // Parse binary plists: InitialFavorites, Favorites, ConnectPanelFavoriteHistory
        let targetKeys = ["InitialFavorites", "Favorites", "ConnectPanelFavoriteHistory"]

        for key in targetKeys {
            guard let binaryData = rootDict[key] as? Data,
              let plist = try? PropertyListSerialization.propertyList(from: binaryData, options: [], format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else {
                continue
            }

            func resolve(_ val: Any?) -> Any? {
                guard let val = val else { return nil }
                let desc = String(describing: val)
                if desc.contains("CFKeyedArchiverUID"), let range = desc.range(of: "value = ") {
                    let numStr = desc[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "}\" "))
                    if let idx = Int(numStr), idx < objects.count {
                        return resolve(objects[idx])
                    }
                }
                return val
            }

            for obj in objects {
                guard let dict = obj as? [String: Any] else { continue }
                let host = resolve(dict["host"]) as? String
                let user = resolve(dict["username"]) as? String
                let rawPort = resolve(dict["port"])
                var port = 0
                if let pNum = rawPort as? NSNumber {
                    port = pNum.intValue
                } else if let pInt = rawPort as? Int {
                    port = pInt
                } else if let pStr = rawPort as? String, let p = Int(pStr) {
                    port = p
                }
                let rawType = resolve(dict["type"])
                let type = (rawType as? NSNumber)?.intValue ?? (rawType as? Int) ?? 0
                var path = resolve(dict["path"]) as? String ?? ""

                // check userData for LastVisitedPath
                if let userData = resolve(dict["userData"]) as? [String: Any] {
                    if let lastPath = resolve(userData["LastVisitedPath"]) as? String, !lastPath.isEmpty {
                        path = lastPath
                    }
                }

                // If it is a remote connection
                if let host = host, !host.isEmpty, host != "$null" {
                    let resolvedPort = port > 0 ? port : (type == 200 ? 22 : 21)
                    let proto = Self.importedProtocol(type: type, port: resolvedPort)
                    let username = (user == "$null" ? "" : user) ?? ""
                    let cleanPath = (path == "$null" || path.isEmpty) ? "/" : path
                    let serverName = Self.importedConnectionName(host: host)

                    let defaultKeyPath = ("~/.ssh/id_ed25519" as NSString).expandingTildeInPath
                    let hasKey = FileManager.default.fileExists(atPath: defaultKeyPath)

                    let conn = RemoteConnection(
                        name: serverName,
                        connectionProtocol: proto,
                        host: host,
                        port: resolvedPort,
                        username: username,
                        remotePath: cleanPath,
                        authType: hasKey ? .sshKey : .password,
                        keyFilePath: hasKey ? "~/.ssh/id_ed25519" : "",
                        isImportedFromForkLift2: true
                    )

                    if !connections.contains(where: { $0.host == host && $0.port == resolvedPort }) {
                        connections.append(conn)
                    }
                }

                // If it is a local favorite path
                if (host == nil || host == "$null" || host!.isEmpty),
                   let path = resolve(dict["path"]) as? String,
                   !path.isEmpty, path != "$null", path != "/" {
                    let url = URL(fileURLWithPath: path)
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        let name = url.lastPathComponent
                        let fav = FavoriteLocation(name: name, url: url, systemIconName: "folder.fill", isCustom: true)
                        if !favorites.contains(where: { $0.url == url }) &&
                           !FavoriteLocation.defaultFavorites.contains(where: { $0.url == url }) {
                            favorites.append(fav)
                        }
                    }
                }
            }
        }

        return MigrationResult(
            importedConnections: connections,
            importedFavorites: favorites,
            importedSettings: settings,
            sourceFound: true
        )
    }
}
