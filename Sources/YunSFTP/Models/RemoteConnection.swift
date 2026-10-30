import Foundation

public enum ConnectionProtocol: String, CaseIterable, Identifiable, Codable, Sendable {
    case sftp = "SFTP (SSH File Transfer)"
    case ftp = "FTP (File Transfer Protocol)"
    case smb = "SMB (Windows File Share)"
    case webdav = "WebDAV (HTTP/HTTPS)"

    public var id: String { rawValue }

    /// Only SFTP has a transport today. The other cases stay for Codable compatibility.
    public static let implemented: [ConnectionProtocol] = [.sftp]

    public var defaultPort: Int {
        switch self {
        case .sftp: return 22
        case .ftp: return 21
        case .smb: return 445
        case .webdav: return 80
        }
    }

    public var systemIconName: String {
        switch self {
        case .sftp: return "lock.icloud"
        case .ftp: return "network"
        case .smb: return "server.rack"
        case .webdav: return "globe"
        }
    }
}

public enum AuthenticationType: String, CaseIterable, Identifiable, Codable, Sendable {
    case password = "Password"
    case sshKey = "SSH Private Key"

    public var id: String { rawValue }
}

public struct RemoteConnection: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var connectionProtocol: ConnectionProtocol
    public var host: String
    public var port: Int
    public var username: String
    public var remotePath: String
    public var authType: AuthenticationType
    public var keyFilePath: String
    public var isImportedFromForkLift2: Bool
    public var lastTestedDate: Date?
    public var lastTestStatusSummary: String?
    /// Opt-in for devices that only speak SHA-1 key exchange / ssh-rsa. Off by default.
    public var allowLegacyAlgorithms: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        connectionProtocol: ConnectionProtocol = .sftp,
        host: String = "",
        port: Int = 22,
        username: String = "",
        remotePath: String = "/",
        authType: AuthenticationType = .password,
        keyFilePath: String = "~/.ssh/id_ed25519",
        isImportedFromForkLift2: Bool = false,
        lastTestedDate: Date? = nil,
        lastTestStatusSummary: String? = nil,
        allowLegacyAlgorithms: Bool = false
    ) {
        self.id = id
        self.name = name.isEmpty ? (host.isEmpty ? "New Connection" : host) : name
        self.connectionProtocol = connectionProtocol
        self.host = host
        self.port = port
        self.username = username
        self.remotePath = remotePath
        self.authType = authType
        self.keyFilePath = keyFilePath
        self.isImportedFromForkLift2 = isImportedFromForkLift2
        self.lastTestedDate = lastTestedDate
        self.lastTestStatusSummary = lastTestStatusSummary
        self.allowLegacyAlgorithms = allowLegacyAlgorithms
    }

    // Manual decoding so connections saved before `allowLegacyAlgorithms` existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        connectionProtocol = try c.decode(ConnectionProtocol.self, forKey: .connectionProtocol)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        remotePath = try c.decode(String.self, forKey: .remotePath)
        authType = try c.decode(AuthenticationType.self, forKey: .authType)
        keyFilePath = try c.decode(String.self, forKey: .keyFilePath)
        isImportedFromForkLift2 = try c.decode(Bool.self, forKey: .isImportedFromForkLift2)
        lastTestedDate = try c.decodeIfPresent(Date.self, forKey: .lastTestedDate)
        lastTestStatusSummary = try c.decodeIfPresent(String.self, forKey: .lastTestStatusSummary)
        allowLegacyAlgorithms = try c.decodeIfPresent(Bool.self, forKey: .allowLegacyAlgorithms) ?? false
    }

    public var formattedPort: String {
        String(port)
    }

    public var formattedHostPort: String {
        "\(host):\(String(port))"
    }

    public var displayTitle: String {
        if !name.isEmpty && name != host {
            return name
        }
        return host.isEmpty ? "Untitled Server" : host
    }

    public var displaySubtitle: String {
        let userPart = username.isEmpty ? "" : "\(username)@"
        return "\(userPart)\(host):\(String(port))"
    }
}
