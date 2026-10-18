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

    private var selectedIndex: Int? {
        guard let id = selectedConnectionId else { return nil }
        return connectionManager.connections.firstIndex(where: { $0.id == id })
    }

    private var selectedConnection: RemoteConnection? {
        guard let idx = selectedIndex, idx < connectionManager.connections.count else { return nil }
        return connectionManager.connections[idx]
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
                                    connectionManager.deleteConnection(id: conn.id)
                                    if selectedConnectionId == conn.id {
                                        selectedConnectionId = connectionManager.connections.first?.id
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Bottom import button
                VStack(spacing: 4) {
                    Button(action: importFromForkLift2) {
                        Label("Import from ForkLift 2", systemImage: "arrow.down.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
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
            if let idx = selectedIndex, idx < connectionManager.connections.count {
                let conn = connectionManager.connections[idx]
                VStack(spacing: 14) {
                    // Header
                    HStack {
                        Image(systemName: conn.connectionProtocol.systemIconName)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conn.displayTitle)
                                .font(.title3.bold())
                            if conn.isImportedFromForkLift2 {
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
                            TextField("Friendly name", text: $connectionManager.connections[idx].name)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Protocol:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .trailing)
                            Picker("", selection: $connectionManager.connections[idx].connectionProtocol) {
                                ForEach(ConnectionProtocol.allCases) { proto in
                                    Text(proto.rawValue).tag(proto)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: connectionManager.connections[idx].connectionProtocol) { proto in
                                connectionManager.connections[idx].port = proto.defaultPort
                            }
                        }

                        HStack {
                            Text("Server:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .trailing)
                            TextField("host or IP (e.g. synology.me)", text: $connectionManager.connections[idx].host)
                                .textFieldStyle(.roundedBorder)

                            Text("Port:")
                                .font(.system(size: 11, weight: .medium))

                            // Pure numeric string binding - guarantees NO commas can ever be typed or displayed
                            TextField("Port", text: Binding(
                                get: { String(connectionManager.connections[idx].port) },
                                set: { newVal in
                                    let digits = newVal.filter { $0.isNumber }
                                    if let p = Int(digits) {
                                        connectionManager.connections[idx].port = p
                                    } else if digits.isEmpty {
                                        connectionManager.connections[idx].port = 0
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
                            TextField("Username", text: $connectionManager.connections[idx].username)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Path:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .trailing)
                            TextField("/path/to/folder", text: $connectionManager.connections[idx].remotePath)
                                .textFieldStyle(.roundedBorder)
                        }

                        if connectionManager.connections[idx].connectionProtocol == .sftp {
                            HStack {
                                Text("Auth Type:")
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 80, alignment: .trailing)
                                Picker("", selection: $connectionManager.connections[idx].authType) {
                                    ForEach(AuthenticationType.allCases) { auth in
                                        Text(auth.rawValue).tag(auth)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if connectionManager.connections[idx].authType == .sshKey {
                                HStack {
                                    Text("Private Key:")
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 80, alignment: .trailing)
                                    TextField("Key file path", text: $connectionManager.connections[idx].keyFilePath)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Browse...") {
                                        selectKeyFile(idx: idx)
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

                                        if KeychainService.shared.loadPassword(for: conn) != nil {
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
                            Button(action: { runTest(for: connectionManager.connections[idx]) }) {
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
                            .disabled(isTesting || connectionManager.connections[idx].host.isEmpty)

                            if connectionManager.connections[idx].connectionProtocol == .sftp {
                                Button(action: { connectionManager.openSSHTerminal(for: connectionManager.connections[idx]) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "terminal")
                                        Text("Open SSH in Terminal")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(connectionManager.connections[idx].host.isEmpty)
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
                            let idToDelete = connectionManager.connections[idx].id
                            KeychainService.shared.deletePassword(for: connectionManager.connections[idx])
                            connectionManager.deleteConnection(id: idToDelete)
                            selectedConnectionId = connectionManager.connections.first?.id
                        }

                        Spacer()

                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        if isEditMode {
                            Button("Connect") {
                                connectAction(conn: connectionManager.connections[idx])
                            }
                            .buttonStyle(.bordered)
                            .disabled(connectionManager.connections[idx].host.isEmpty)

                            Button("Save") {
                                saveAction(conn: connectionManager.connections[idx])
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        } else {
                            Button("Save") {
                                saveAction(conn: connectionManager.connections[idx])
                            }
                            .buttonStyle(.bordered)

                            Button("Connect") {
                                connectAction(conn: connectionManager.connections[idx])
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(connectionManager.connections[idx].host.isEmpty)
                        }
                    }
                }
                .padding(20)
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
        let newConn = RemoteConnection(name: "New Server", connectionProtocol: .sftp, host: "", port: 22)
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

    private func importFromForkLift2() {
        let res = connectionManager.importFromForkLift2Manually()
        if res.connectionsCount > 0 {
            importMessage = "Imported \(res.connectionsCount) connections!"
            selectedConnectionId = connectionManager.connections.last?.id
        } else {
            importMessage = "Already up to date."
        }
    }

    private func selectKeyFile(idx: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let sshPath = ("~/.ssh" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: sshPath) {
            panel.directoryURL = URL(fileURLWithPath: sshPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            connectionManager.connections[idx].keyFilePath = url.path
        }
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
