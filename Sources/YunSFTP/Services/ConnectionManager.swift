import Foundation
import AppKit
import SwiftUI

@MainActor
public class ConnectionManager: ObservableObject {
    public static let shared = ConnectionManager()

    @Published public var connections: [RemoteConnection] = [] {
        didSet {
            saveConnections()
        }
    }
    @Published public var isTesting: [UUID: Bool] = [:]
    @Published public var testResults: [UUID: ConnectionTestResult] = [:]

    private let storageKey = "yunsftp_SavedConnections"
    private let migrationDoneKey = "yunsftp_MigrationDone"

    public init() {
        loadConnections()
        checkAndPerformAutoMigration()
    }

    public func loadConnections() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([RemoteConnection].self, from: data) {
            self.connections = list
        }
    }

    public func saveConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func checkAndPerformAutoMigration() {
        let migrationDone = UserDefaults.standard.bool(forKey: migrationDoneKey)
        if !migrationDone && connections.isEmpty {
            let result = MigrationService.shared.migrateFromForkLift2()
            if !result.importedConnections.isEmpty {
                self.connections = result.importedConnections
                saveConnections()
            }
            // View settings are adopted only on this one-time first launch, never on manual import.
            if result.sourceFound {
                result.importedSettings?.save()
            }
            UserDefaults.standard.set(true, forKey: migrationDoneKey)
        }
    }

    public func importFromForkLift2Manually() -> (connectionsCount: Int, favoritesCount: Int) {
        let result = MigrationService.shared.migrateFromForkLift2()
        var addedConns = 0

        for conn in result.importedConnections {
            if !connections.contains(where: { $0.host == conn.host && $0.port == conn.port }) {
                connections.append(conn)
                addedConns += 1
            }
        }

        if addedConns > 0 {
            saveConnections()
        }

        return (addedConns, result.importedFavorites.count)
    }

    public func addConnection(_ connection: RemoteConnection) {
        connections.append(connection)
        saveConnections()
    }

    public func updateConnection(_ connection: RemoteConnection) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
            saveConnections()
        }
    }

    public func connection(for id: UUID) -> RemoteConnection? {
        connections.first(where: { $0.id == id })
    }

    public func binding(for id: UUID) -> Binding<RemoteConnection>? {
        guard connections.contains(where: { $0.id == id }) else { return nil }
        return Binding<RemoteConnection>(
            get: {
                self.connections.first(where: { $0.id == id }) ?? RemoteConnection(id: id, name: "", host: "")
            },
            set: { updated in
                if let idx = self.connections.firstIndex(where: { $0.id == id }) {
                    self.connections[idx] = updated
                }
            }
        )
    }

    public func deleteConnection(id: UUID) {
        connections.removeAll { $0.id == id }
        testResults.removeValue(forKey: id)
        isTesting.removeValue(forKey: id)
        saveConnections()
    }

    public func duplicateConnection(_ connection: RemoteConnection) {
        var copy = connection
        copy.id = UUID()
        copy.name = "\(connection.name) Copy"
        connections.append(copy)
        saveConnections()
    }

    public func testConnection(_ connection: RemoteConnection) async -> ConnectionTestResult {
        isTesting[connection.id] = true

        let isSSH = (connection.connectionProtocol == .sftp)
        let res = await ConnectionTestService.shared.testConnection(
            host: connection.host,
            port: connection.port,
            isSSH: isSSH
        )

        testResults[connection.id] = res
        isTesting[connection.id] = false

        // Update connection metadata
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx].lastTestedDate = Date()
            connections[idx].lastTestStatusSummary = res.isSuccess ? "Success (\(Int(res.latencyMs))ms)" : "Failed"
            saveConnections()
        }

        return res
    }

    /// Builds the interactive `ssh` command line for Terminal. Every user-controlled field is
    /// single-quoted for the shell and `--` prevents a host starting with `-` from being parsed
    /// as an option.
    nonisolated public static func sshCommand(for connection: RemoteConnection) -> String {
        let q = SFTPService.posixShellEscape
        var parts = ["ssh", "-p", String(connection.port)]
        if connection.authType == .sshKey && !connection.keyFilePath.isEmpty {
            parts += ["-i", q((connection.keyFilePath as NSString).expandingTildeInPath)]
        }
        if connection.allowLegacyAlgorithms {
            parts += SFTPService.legacySSHOptions.map { $0 == "-o" ? $0 : q($0) }
        }
        let target = connection.username.isEmpty ? connection.host : "\(connection.username)@\(connection.host)"
        parts += ["--", q(target)]
        return parts.joined(separator: " ")
    }

    public func openSSHTerminal(for connection: RemoteConnection) {
        guard !connection.host.isEmpty else { return }
        TerminalService.runInTerminal(Self.sshCommand(for: connection))
    }
}
