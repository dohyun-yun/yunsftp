import SwiftUI
import AppKit

public struct ConnectSheet: View {
    @ObservedObject var connectionManager = ConnectionManager.shared
    @Environment(\.dismiss) private var dismiss
    var initialConnection: RemoteConnection? = nil
    var isEditMode: Bool = false
    var autoRunTest: Bool = false
    var onConnect: (RemoteConnection, String?) -> Void

    @State private var selectedConnectionId: UUID? = nil
    @State private var inputPassword: String = ""
    @State private var savePasswordToKeychain: Bool = true
    @State private var isPromptingPassword: Bool = false
    @State private var testResult: ConnectionTestResult? = nil
    @State private var isTesting: Bool = false
    @State private var importMessage: String? = nil

    private var selectedConnection: RemoteConnection? {
        guard let id = selectedConnectionId else { return nil }
        return connectionManager.connection(for: id)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar: Saved Connections List
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Connections")
                        .font(.headline)
                    Spacer()
                    Button(action: createNewConnection) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Add New Connection")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // List
                List(selection: $selectedConnectionId) {
                    if connectionManager.connections.isEmpty {
                        Text("No saved connections")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(connectionManager.connections) { conn in
                            ConnectionRowView(
                                connection: conn,
                                isSelected: selectedConnectionId == conn.id
                            )
                            .tag(conn.id)
                            .contextMenu {
                                Button("Open SSH in Terminal") {
                                    connectionManager.openSSHTerminal(for: conn)
                                }
                                Button("Test Connection") {
                                    runTest(for: conn)
                                }
                                Divider()
                                Button("Duplicate") {
                                    connectionManager.duplicateConnection(conn)
                                    selectedConnectionId = connectionManager.connections.last?.id
                                }
                                Button("Delete", role: .destructive) {
                                    deleteConnectionSafely(id: conn.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Bottom import menu
                VStack(spacing: 4) {
                    Menu {
                        Button("SSH config (~/.ssh/config)") { report(connectionManager.importFromSSHConfig()) }
                            .disabled(!FileManager.default.fileExists(atPath: SSHConfigImporter.userConfigURL.path))
                        Button("Cyberduck bookmarks") { report(connectionManager.importFromCyberduck()) }
                            .disabled(!FileManager.default.fileExists(atPath: CyberduckImporter.bookmarksDirectory.path))
                        Button("ForkLift 2 bookmarks") { importFromForkLift2() }
                            .disabled(!MigrationService.shared.hasForkLift2Data())
                    } label: {
                        Label("Import…", systemImage: "arrow.down.doc")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.vertical, 6)

                    if let msg = importMessage {
                        Text(msg)
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(width: 220)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Right Form: Connection Details & Testing
            // Right Form: Connection Details & Testing
            if let selectedId = selectedConnectionId,
               let binding = connectionManager.binding(for: selectedId) {
                ConnectionDetailEditorView(
                    connection: binding,
                    isEditMode: isEditMode,
                    isTesting: isTesting,
                    testResult: testResult,
                    inputPassword: $inputPassword,
                    savePasswordToKeychain: $savePasswordToKeychain,
                    onRunTest: {
                        if let conn = connectionManager.connection(for: selectedId) {
                            runTest(for: conn)
                        }
                    },
                    onOpenSSHTerminal: {
                        if let conn = connectionManager.connection(for: selectedId) {
                            connectionManager.openSSHTerminal(for: conn)
                        }
                    },
                    onDelete: {
                        deleteConnectionSafely(id: selectedId)
                    },
                    onCancel: {
                        dismiss()
                    },
                    onSave: {
                        if let conn = connectionManager.connection(for: selectedId) {
                            saveAction(conn: conn)
                        }
                    },
                    onConnect: {
                        if let conn = connectionManager.connection(for: selectedId) {
                            connectAction(conn: conn)
                        }
                    }
                )
                .id(selectedId)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Select or create a connection")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Create Connection") {
                        createNewConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 720, height: 500)
        .overlay {
            if isPromptingPassword, let conn = selectedConnection {
                ZStack {
                    Color.black.opacity(0.35)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            isPromptingPassword = false
                        }

                    PasswordPromptSheet(
                        connection: conn,
                        onConnect: { pwd, save in
                            inputPassword = pwd
                            if save {
                                KeychainService.shared.savePassword(pwd, for: conn)
                            }
                            isPromptingPassword = false
                            onConnect(conn, pwd)
                            dismiss()
                        },
                        onCancel: {
                            isPromptingPassword = false
                        }
                    )
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                }
            }
        }
        .onAppear {
            if let initial = initialConnection {
                selectedConnectionId = initial.id
            } else if selectedConnectionId == nil {
                selectedConnectionId = connectionManager.connections.first?.id
            }
            loadSavedPasswordForSelection()
            if autoRunTest, let conn = selectedConnection, !conn.host.isEmpty {
                runTest(for: conn)
            }
        }
        .onChange(of: selectedConnectionId) { _ in
            testResult = nil
            loadSavedPasswordForSelection()
        }
    }

    private func loadSavedPasswordForSelection() {
        if let conn = selectedConnection {
            if let saved = KeychainService.shared.loadPassword(for: conn) {
                inputPassword = saved
            } else {
                inputPassword = ""
            }
        } else {
            inputPassword = ""
        }
    }

    private func createNewConnection() {
        let newConn = RemoteConnection(name: "New Server", connectionProtocol: .sftp, host: "", port: 22,
                                       allowLegacyAlgorithms: SettingsStore.shared.settings.legacyAlgorithmsByDefault)
        connectionManager.addConnection(newConn)
        selectedConnectionId = newConn.id
        testResult = nil
        inputPassword = ""
    }

    private func runTest(for conn: RemoteConnection) {
        isTesting = true
        testResult = nil
        Task {
            let res = await connectionManager.testConnection(conn)
            await MainActor.run {
                self.testResult = res
                self.isTesting = false
            }
        }
    }

    private func report(_ added: Int) {
        importMessage = added > 0 ? "Imported \(added) connections!" : "Nothing new to import."
        if added > 0 { selectedConnectionId = connectionManager.connections.last?.id }
    }

    private func importFromForkLift2() {
        let res = connectionManager.importFromForkLift2Manually()
        if res.connectionsCount > 0 {
            importMessage = "Imported \(res.connectionsCount) connections!"
            selectedConnectionId = connectionManager.connections.last?.id
        } else {
            importMessage = "Already up to date."
        }
    }

    private func deleteConnectionSafely(id: UUID) {
        if let conn = connectionManager.connection(for: id) {
            KeychainService.shared.deletePassword(for: conn)
        }

        let remaining = connectionManager.connections.filter { $0.id != id }
        if selectedConnectionId == id {
            selectedConnectionId = remaining.first?.id
        }

        testResult = nil
        inputPassword = ""
        connectionManager.deleteConnection(id: id)

        loadSavedPasswordForSelection()
    }

    private func saveAction(conn: RemoteConnection) {
        connectionManager.updateConnection(conn)
        if conn.authType == .password {
            let trimmed = inputPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && savePasswordToKeychain {
                KeychainService.shared.savePassword(trimmed, for: conn)
            }
        }
        dismiss()
    }

    private func connectAction(conn: RemoteConnection) {
        // If password auth is selected, verify password
        if conn.authType == .password {
            let trimmed = inputPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Check if keychain has it
                if let saved = KeychainService.shared.loadPassword(for: conn), !saved.isEmpty {
                    inputPassword = saved
                } else {
                    // Prompt user for password before connecting
                    isPromptingPassword = true
                    return
                }
            } else if savePasswordToKeychain {
                KeychainService.shared.savePassword(trimmed, for: conn)
            }
        }

        let pwd = inputPassword.isEmpty ? nil : inputPassword
        onConnect(conn, pwd)
        dismiss()
    }
}

private struct ConnectionDetailEditorView: View {
    @Binding var connection: RemoteConnection
    var isEditMode: Bool
    var isTesting: Bool
    var testResult: ConnectionTestResult?
    @Binding var inputPassword: String
    @Binding var savePasswordToKeychain: Bool
    var onRunTest: () -> Void
    var onOpenSSHTerminal: () -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void
    var onConnect: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Image(systemName: connection.connectionProtocol.systemIconName)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.displayTitle)
                        .font(.title3.bold())
                    if connection.isImportedFromForkLift2 {
                        Text("Migrated from ForkLift 2")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            // Configuration Form
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Name:")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .trailing)
                    TextField("Friendly name", text: $connection.name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Protocol:")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: $connection.connectionProtocol) {
                        ForEach(ConnectionProtocol.implemented.contains(connection.connectionProtocol)
                                ? ConnectionProtocol.implemented
                                : ConnectionProtocol.implemented + [connection.connectionProtocol]) { proto in
                            Text(proto.rawValue).tag(proto)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: connection.connectionProtocol) { proto in
                        connection.port = proto.defaultPort
                    }
                }

                HStack {
                    Text("Server:")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .trailing)
                    TextField("host or IP (e.g. 192.168.1.10 or nas.example.com)", text: $connection.host)
                        .textFieldStyle(.roundedBorder)

                    Text("Port:")
                        .font(.system(size: 11, weight: .medium))

                    // Pure numeric string binding - guarantees NO commas can ever be typed or displayed
                    TextField("Port", text: Binding(
                        get: { String(connection.port) },
                        set: { newVal in
                            let digits = newVal.filter { $0.isNumber }
                            if let p = Int(digits) {
                                connection.port = p
                            } else if digits.isEmpty {
                                connection.port = 0
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                }

                HStack {
                    Text("Username:")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .trailing)
                    TextField("Username", text: $connection.username)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Path:")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .trailing)
                    TextField("/path/to/folder", text: $connection.remotePath)
                        .textFieldStyle(.roundedBorder)
                }

                if connection.connectionProtocol == .sftp {
                    HStack {
                        Text("Auth Type:")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 80, alignment: .trailing)
                        Picker("", selection: $connection.authType) {
                            ForEach(AuthenticationType.allCases) { auth in
                                Text(auth.rawValue).tag(auth)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(alignment: .top) {
                        Spacer().frame(width: 84)
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Allow legacy SSH algorithms (SHA-1 key exchange, ssh-rsa)", isOn: $connection.allowLegacyAlgorithms)
                                .font(.system(size: 10))
                            Text("Only for old devices that fail with \"no matching key exchange method\". Weakens security for this connection.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }

                    if connection.authType == .sshKey {
                        HStack {
                            Text("Private Key:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .trailing)
                            TextField("Key file path", text: $connection.keyFilePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                selectKeyFile()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Password:")
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 80, alignment: .trailing)
                                SecureField("Server password (leave blank to prompt on connect)", text: $inputPassword)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Spacer().frame(width: 84)
                                Toggle("Save password in Keychain", isOn: $savePasswordToKeychain)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)

                                if KeychainService.shared.loadPassword(for: connection) != nil {
                                    Text("• Saved in Keychain")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Test Connection Box
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(action: onRunTest) {
                        HStack(spacing: 4) {
                            if isTesting {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || connection.host.isEmpty)

                    if connection.connectionProtocol == .sftp {
                        Button(action: onOpenSSHTerminal) {
                            HStack(spacing: 4) {
                                Image(systemName: "terminal")
                                Text("Open SSH in Terminal")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(connection.host.isEmpty)
                    }

                    Spacer()
                }

                if let res = testResult {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: res.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(res.isSuccess ? .green : .red)
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(res.message)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(res.isSuccess ? .primary : .red)

                            if let ip = res.resolvedIP {
                                Text(verbatim: "IP: \(ip)  •  Latency: \(String(Int(res.latencyMs))) ms")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(res.isSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
            }

            Spacer()

            // Bottom Actions
            HStack {
                Button("Delete Connection", role: .destructive) {
                    onDelete()
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                if isEditMode {
                    Button("Connect") {
                        onConnect()
                    }
                    .buttonStyle(.bordered)
                    .disabled(connection.host.isEmpty)

                    Button("Save") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Save") {
                        onSave()
                    }
                    .buttonStyle(.bordered)

                    Button("Connect") {
                        onConnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(connection.host.isEmpty)
                }
            }
        }
        .padding(20)
    }

    private func selectKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let sshPath = ("~/.ssh" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: sshPath) {
            panel.directoryURL = URL(fileURLWithPath: sshPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            connection.keyFilePath = url.path
        }
    }
}

private struct ConnectionRowView: View {
    let connection: RemoteConnection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: connection.connectionProtocol.systemIconName)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Text(connection.displaySubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            if connection.isImportedFromForkLift2 {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .help("Migrated from ForkLift 2")
            }
        }
        .padding(.vertical, 3)
    }
}
