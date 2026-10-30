import Foundation
import NIOCore
import NIOSSH
import Citadel
import Crypto
import _CryptoExtras
import NIOPosix

/// SFTP over swift-nio-ssh (Citadel). One SSH session per connection, reused across operations.
/// Errors are mapped to the same `SFTPService` NSError codes the OpenSSH transport produces,
/// so callers (and the UI) do not care which engine ran.
public actor NativeSFTPEngine {
    public static let shared = NativeSFTPEngine()

    /// Overridable for tests.
    public static var knownHostsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts")

    public static let chunkSize = 256 * 1024
    public static let connectTimeout: TimeAmount = .seconds(15)

    private struct Session {
        let ssh: SSHClient
        let sftp: SFTPClient
    }
    private var sessions: [String: Session] = [:]
    private var connecting: [String: Task<SFTPClient, Error>] = [:]

    public init() {}

    /// Live sessions (tests observe that concurrent callers share one connection).
    public var sessionCount: Int { sessions.count }

    // MARK: - Session

    private func session(for connection: RemoteConnection, password: String?) async throws -> SFTPClient {
        let key = connection.sessionFingerprint
        if let s = sessions[key], s.ssh.isConnected, s.sftp.isActive {
            return s.sftp
        }
        if let s = sessions.removeValue(forKey: key) {
            Task { try? await s.sftp.close(); try? await s.ssh.close() }
        }
        // Concurrent first-use callers (two panes, a listing racing a transfer) share one connect.
        if let inFlight = connecting[key] { return try await inFlight.value }
        let task = Task<SFTPClient, Error> { try await Self.openSession(for: connection, password: password) }
        connecting[key] = task
        defer { connecting[key] = nil }
        let sftp = try await task.value
        if let ssh = Self.pendingSSHClients.take(for: key) {
            sessions[key] = Session(ssh: ssh, sftp: sftp)
        }
        return sftp
    }

    /// Hands the SSHClient from `openSession` back to the actor (the connect task is not isolated).
    private final class PendingClients: @unchecked Sendable {
        private let lock = NSLock()
        private var clients: [String: SSHClient] = [:]
        func put(_ client: SSHClient, for key: String) { lock.lock(); clients[key] = client; lock.unlock() }
        func take(for key: String) -> SSHClient? { lock.lock(); defer { lock.unlock() }; return clients.removeValue(forKey: key) }
    }
    private static let pendingSSHClients = PendingClients()

    private static func openSession(for connection: RemoteConnection, password: String?) async throws -> SFTPClient {
        let auth = try authenticationMethod(for: connection, password: password)
        let validator = KnownHostsValidator(host: connection.host, port: connection.port, store: KnownHosts(fileURL: knownHostsURL))
        let ssh: SSHClient
        do {
            ssh = try await SSHClient.connect(
                host: connection.host,
                port: connection.port,
                authenticationMethod: auth,
                hostKeyValidator: .custom(validator),
                reconnect: .never,
                connectTimeout: connectTimeout
            )
        } catch {
            if let hostKeyError = validator.failure { throw hostKeyError }
            throw mapConnectError(error)
        }
        let sftp = try await ssh.openSFTP()
        pendingSSHClients.put(ssh, for: connection.sessionFingerprint)
        return sftp
    }

    public func disconnect(_ connection: RemoteConnection) async {
        if let s = sessions.removeValue(forKey: connection.sessionFingerprint) {
            try? await s.sftp.close()
            try? await s.ssh.close()
        }
    }

    public func disconnectAll() async {
        for key in Array(sessions.keys) {
            if let s = sessions.removeValue(forKey: key) {
                try? await s.sftp.close()
                try? await s.ssh.close()
            }
        }
    }

    static func authenticationMethod(for connection: RemoteConnection, password: String?) throws -> SSHAuthenticationMethod {
        let user = connection.username.isEmpty ? NSUserName() : connection.username
        switch connection.authType {
        case .password:
            guard let password, !password.isEmpty else {
                throw NSError(domain: "SFTPService", code: SFTPService.authenticationFailureCode, userInfo: [NSLocalizedDescriptionKey: "A password is required for this connection."])
            }
            return .passwordBased(username: user, password: password)
        case .sshKey:
            let path = (connection.keyFilePath.isEmpty ? "~/.ssh/id_ed25519" : connection.keyFilePath) as NSString
            // No readable key file: OpenSSH may still succeed through ssh-agent or other identities.
            guard let text = try? String(contentsOfFile: path.expandingTildeInPath, encoding: .utf8) else {
                throw EngineUnsupported.privateKey
            }
            return try privateKeyAuthentication(username: user, keyText: text)
        }
    }

    /// Tries the OpenSSH private-key formats Citadel can read. Passphrase-protected keys are
    /// reported as unsupported so the caller falls back to OpenSSH + ssh-agent.
    static func privateKeyAuthentication(username: String, keyText: String) throws -> SSHAuthenticationMethod {
        if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: keyText) {
            return .ed25519(username: username, privateKey: key)
        }
        if let key = try? Insecure.RSA.PrivateKey(sshRsa: keyText) {
            return .rsa(username: username, privateKey: key)
        }
        throw EngineUnsupported.privateKey
    }

    /// Raised when the native engine cannot handle a connection; `SFTPService` then uses OpenSSH.
    public enum EngineUnsupported: Error { case privateKey, negotiation(String) }

    static func mapConnectError(_ error: Error) -> Error {
        if error is EngineUnsupported || error is CancellationError { return error }
        if let e = error as? SSHClientError {
            // swift-nio-ssh has no keyboard-interactive and no agent: let OpenSSH give the verdict.
            return EngineUnsupported.negotiation("\(e)")
        }
        if let e = error as? NIOSSHError {
            if e.type == .keyExchangeNegotiationFailure || e.type == .unsupportedVersion || e.type == .protocolViolation {
                return EngineUnsupported.negotiation(String(describing: e))
            }
            return connectionError(String(describing: e))
        }
        if let e = error as? ChannelError, e == .connectTimeout(connectTimeout) || "\(e)".contains("connectTimeout") {
            return connectionError("Connection timed out")
        }
        if let e = error as? IOError {
            switch e.errnoCode {
            case ECONNREFUSED: return connectionError("Connection refused")
            case EHOSTUNREACH, ENETUNREACH: return connectionError("No route to host")
            case ETIMEDOUT: return connectionError("Connection timed out")
            default: return connectionError(e.description)
            }
        }
        let text = String(describing: error)
        if text.contains("connectTimeout") || text.contains("timed out") { return connectionError("Connection timed out") }
        if text.contains("ECONNREFUSED") || text.contains("refused") { return connectionError("Connection refused") }
        if text.contains("nodename nor servname") || text.contains("DNS") || text.contains("getaddrinfo") || text.contains("could not be resolved") {
            return connectionError("DNS lookup failed. Host could not be resolved.")
        }
        return connectionError(error.localizedDescription)
    }

    private static func connectionError(_ raw: String) -> NSError {
        NSError(domain: "SFTPService", code: 255, userInfo: [NSLocalizedDescriptionKey: SFTPService.translateErrorMessage(raw, exitCode: 255)])
    }

    static func mapSFTPError(_ error: Error, path: String) -> Error {
        // Citadel throws the status either wrapped (`SFTPError.errorStatus`) or as the raw message.
        var statusValue: SFTPMessage.Status? = error as? SFTPMessage.Status
        if case SFTPError.errorStatus(let s) = error { statusValue = s }
        if let status = statusValue {
            switch status.errorCode {
            case .noSuchFile:
                return NSError(domain: "SFTPService", code: SFTPService.notFoundCode,
                               userInfo: [NSLocalizedDescriptionKey: SFTPService.translateErrorMessage("No such file or directory: \(path)", exitCode: 1)])
            case .permissionDenied:
                return NSError(domain: "SFTPService", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: SFTPService.translateErrorMessage("remote: Permission denied: \(path)", exitCode: 1)])
            default:
                return NSError(domain: "SFTPService", code: 1, userInfo: [NSLocalizedDescriptionKey: status.message.isEmpty ? "SFTP error \(status.errorCode)" : status.message])
            }
        }
        if case SFTPError.connectionClosed = error {
            return NSError(domain: "SFTPService", code: 1, userInfo: [NSLocalizedDescriptionKey: SFTPService.translateErrorMessage("Connection reset by peer", exitCode: 255)])
        }
        return error
    }

    // MARK: - Listing & attributes

    public func listDirectory(path: String, connection: RemoteConnection, password: String?) async throws -> [RemoteFileItem] {
        let sftp = try await session(for: connection, password: password)
        let dir = SFTPService.normalizeRemotePath(path)
        do {
            let names = try await sftp.listDirectory(atPath: dir)
            var items: [RemoteFileItem] = []
            for name in names {
                for component in name.components where component.filename != "." && component.filename != ".." {
                    items.append(Self.item(from: component, in: dir))
                }
            }
            return items
        } catch {
            throw Self.mapSFTPError(error, path: dir)
        }
    }

    static func item(from component: SFTPPathComponent, in dir: String) -> RemoteFileItem {
        let attrs = component.attributes
        let mode = attrs.permissions ?? 0
        let typeBits = mode & 0o170000
        let isDir = typeBits == 0o040000
        let isLink = typeBits == 0o120000
        let full = dir == "/" ? "/\(component.filename)" : "\(dir)/\(component.filename)"
        return RemoteFileItem(
            name: component.filename,
            remotePath: full,
            isDirectory: isDir,
            isSymlink: isLink,
            size: Int64(attrs.size ?? 0),
            modificationDate: attrs.accessModificationTime?.modificationTime ?? Date(),
            permissions: FileItem.formatPOSIXPermissions(Int(mode & 0o777))
        )
    }

    public func exists(path: String, connection: RemoteConnection, password: String?) async throws -> Bool {
        let sftp = try await session(for: connection, password: password)
        do {
            _ = try await sftp.getAttributes(at: SFTPService.normalizeRemotePath(path))
            return true
        } catch {
            let mapped = Self.mapSFTPError(error, path: path)
            if SFTPService.isNotFound(mapped) { return false }
            throw mapped
        }
    }

    private func attributes(of path: String, sftp: SFTPClient) async throws -> SFTPFileAttributes? {
        do { return try await sftp.getAttributes(at: path) } catch {
            let mapped = Self.mapSFTPError(error, path: path)
            if SFTPService.isNotFound(mapped) { return nil }
            throw mapped
        }
    }

    // MARK: - Transfers

    /// Downloads a file or a directory tree to `localURL` (the final local path, parent must exist).
    public func download(remotePath: String, to localURL: URL, connection: RemoteConnection, password: String?,
                         progress: (@Sendable (Int64) -> Void)? = nil) async throws {
        let sftp = try await session(for: connection, password: password)
        let path = SFTPService.normalizeRemotePath(remotePath)
        guard let attrs = try await attributes(of: path, sftp: sftp) else {
            throw NSError(domain: "SFTPService", code: SFTPService.notFoundCode, userInfo: [NSLocalizedDescriptionKey: SFTPService.translateErrorMessage("No such file or directory: \(path)", exitCode: 1)])
        }
        var transferred: Int64 = 0
        try await downloadNode(path: path, attributes: attrs, to: localURL, sftp: sftp, transferred: &transferred, progress: progress)
    }

    private func downloadNode(path: String, attributes: SFTPFileAttributes, to localURL: URL, sftp: SFTPClient,
                              transferred: inout Int64, progress: (@Sendable (Int64) -> Void)?) async throws {
        try Task.checkCancellation()
        let mode = attributes.permissions ?? 0
        if mode & 0o170000 == 0o040000 {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            let children = try await sftp.listDirectory(atPath: path).flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }
            for child in children {
                let childPath = path == "/" ? "/\(child.filename)" : "\(path)/\(child.filename)"
                try await downloadNode(path: childPath, attributes: child.attributes, to: localURL.appendingPathComponent(child.filename), sftp: sftp, transferred: &transferred, progress: progress)
            }
            return
        }
        let file: SFTPFile
        do { file = try await sftp.openFile(filePath: path, flags: .read) } catch { throw Self.mapSFTPError(error, path: path) }
        defer { Task { try? await file.close() } }
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: localURL)
        defer { try? handle.close() }
        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let buffer = try await file.read(from: offset, length: UInt32(Self.chunkSize))
            guard buffer.readableBytes > 0 else { break }
            try handle.write(contentsOf: Data(buffer.readableBytesView))
            offset += UInt64(buffer.readableBytes)
            transferred += Int64(buffer.readableBytes)
            progress?(transferred)
            if buffer.readableBytes < Self.chunkSize, let size = attributes.size, offset >= size { break }
        }
        if let mtime = attributes.accessModificationTime?.modificationTime {
            try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: localURL.path)
        }
    }

    /// Uploads a file or directory tree to `remotePath` (the final remote path).
    public func upload(localURL: URL, to remotePath: String, connection: RemoteConnection, password: String?,
                       progress: (@Sendable (Int64) -> Void)? = nil) async throws {
        let sftp = try await session(for: connection, password: password)
        var transferred: Int64 = 0
        try await uploadNode(localURL: localURL, to: SFTPService.normalizeRemotePath(remotePath), sftp: sftp, transferred: &transferred, progress: progress)
    }

    private func uploadNode(localURL: URL, to path: String, sftp: SFTPClient, transferred: inout Int64, progress: (@Sendable (Int64) -> Void)?) async throws {
        try Task.checkCancellation()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            throw NSError(domain: "SFTPService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local file not found: \(localURL.path)"])
        }
        if isDir.boolValue {
            if try await attributes(of: path, sftp: sftp) == nil {
                do { try await sftp.createDirectory(atPath: path) } catch { throw Self.mapSFTPError(error, path: path) }
            }
            let children = try FileManager.default.contentsOfDirectory(at: localURL, includingPropertiesForKeys: nil, options: [])
            for child in children {
                let name = child.lastPathComponent.precomposedStringWithCanonicalMapping
                try await uploadNode(localURL: child, to: path == "/" ? "/\(name)" : "\(path)/\(name)", sftp: sftp, transferred: &transferred, progress: progress)
            }
            return
        }
        let file: SFTPFile
        do { file = try await sftp.openFile(filePath: path, flags: [.write, .create, .truncate]) } catch { throw Self.mapSFTPError(error, path: path) }
        defer { Task { try? await file.close() } }
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty else { break }
            do { try await file.write(ByteBuffer(bytes: data), at: offset) } catch { throw Self.mapSFTPError(error, path: path) }
            offset += UInt64(data.count)
            transferred += Int64(data.count)
            progress?(transferred)
        }
    }

    // MARK: - Mutations

    public func createDirectory(path: String, connection: RemoteConnection, password: String?) async throws {
        let sftp = try await session(for: connection, password: password)
        let p = SFTPService.normalizeRemotePath(path)
        do { try await sftp.createDirectory(atPath: p) } catch { throw Self.mapSFTPError(error, path: p) }
    }

    public func remove(path: String, isDirectory: Bool, connection: RemoteConnection, password: String?) async throws {
        let sftp = try await session(for: connection, password: password)
        try await removeNode(path: SFTPService.normalizeRemotePath(path), isDirectory: isDirectory, sftp: sftp)
    }

    private func removeNode(path: String, isDirectory: Bool, sftp: SFTPClient) async throws {
        try Task.checkCancellation()
        if isDirectory {
            let children = try await sftp.listDirectory(atPath: path).flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }
            for child in children {
                let childPath = path == "/" ? "/\(child.filename)" : "\(path)/\(child.filename)"
                let childIsDir = (child.attributes.permissions ?? 0) & 0o170000 == 0o040000
                try await removeNode(path: childPath, isDirectory: childIsDir, sftp: sftp)
            }
            do { try await sftp.rmdir(at: path) } catch { throw Self.mapSFTPError(error, path: path) }
        } else {
            do { try await sftp.remove(at: path) } catch { throw Self.mapSFTPError(error, path: path) }
        }
    }

    public func rename(path: String, to newPath: String, connection: RemoteConnection, password: String?) async throws {
        let sftp = try await session(for: connection, password: password)
        let a = SFTPService.normalizeRemotePath(path), b = SFTPService.normalizeRemotePath(newPath)
        do { try await sftp.rename(at: a, to: b) } catch { throw Self.mapSFTPError(error, path: a) }
    }

    public func chmod(path: String, mode: Int, recursive: Bool, connection: RemoteConnection, password: String?) async throws {
        let sftp = try await session(for: connection, password: password)
        try await chmodNode(path: SFTPService.normalizeRemotePath(path), mode: mode, recursive: recursive, sftp: sftp)
    }

    private func chmodNode(path: String, mode: Int, recursive: Bool, sftp: SFTPClient) async throws {
        try Task.checkCancellation()
        var attrs = SFTPFileAttributes()
        attrs.permissions = UInt32(mode & 0o7777)
        do { try await sftp.setAttributes(at: path, to: attrs) } catch { throw Self.mapSFTPError(error, path: path) }
        guard recursive, let current = try await attributes(of: path, sftp: sftp), (current.permissions ?? 0) & 0o170000 == 0o040000 else { return }
        let children = try await sftp.listDirectory(atPath: path).flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }
        for child in children {
            try await chmodNode(path: path == "/" ? "/\(child.filename)" : "\(path)/\(child.filename)", mode: mode, recursive: true, sftp: sftp)
        }
    }
}

/// Host key validation against known_hosts (trust on first use), mirroring `StrictHostKeyChecking=accept-new`.
final class KnownHostsValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let host: String
    let port: Int
    let store: KnownHosts
    private let lock = NSLock()
    private var _failure: Error?
    var failure: Error? { lock.lock(); defer { lock.unlock() }; return _failure }

    init(host: String, port: Int, store: KnownHosts) {
        self.host = host
        self.port = port
        self.store = store
    }

    static func describe(_ key: NIOSSHPublicKey) -> (type: String, base64: String) {
        var buffer = ByteBuffer()
        _ = key.write(to: &buffer)
        let bytes = Data(buffer.readableBytesView)
        // The blob starts with an SSH string holding the key type name.
        var type = "unknown"
        if bytes.count >= 4 {
            let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            if length > 0, bytes.count >= 4 + length, let s = String(data: bytes[4..<(4 + length)], encoding: .utf8) { type = s }
        }
        return (type, bytes.base64EncodedString())
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let described = Self.describe(hostKey)
        if described.type.contains("-cert-") {
            // Certificate host keys need the @cert-authority logic OpenSSH has; let it handle them.
            let error = NativeSFTPEngine.EngineUnsupported.negotiation("certificate host key")
            lock.lock(); _failure = error; lock.unlock()
            validationCompletePromise.fail(error)
            return
        }
        switch store.verdict(host: host, port: port, keyType: described.type, keyBase64: described.base64) {
        case .trusted:
            validationCompletePromise.succeed(())
        case .unknown:
            do {
                try store.remember(host: host, port: port, keyType: described.type, keyBase64: described.base64)
                validationCompletePromise.succeed(())
            } catch {
                lock.lock(); _failure = error; lock.unlock()
                validationCompletePromise.fail(error)
            }
        case .mismatch:
            let error = NSError(domain: "SFTPService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: SFTPService.translateErrorMessage("Host key verification failed.", exitCode: 255)
            ])
            lock.lock(); _failure = error; lock.unlock()
            validationCompletePromise.fail(error)
        }
    }
}
