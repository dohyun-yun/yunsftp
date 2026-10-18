import SwiftUI
import AppKit

public struct PasswordPromptSheet: View {
    let connection: RemoteConnection
    var onConnect: (String, Bool) -> Void
    var onCancel: () -> Void

    @State private var password: String = ""
    @State private var saveToKeychain: Bool = true
    @FocusState private var isFieldFocused: Bool

    public init(
        connection: RemoteConnection,
        onConnect: @escaping (String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.connection = connection
        self.onConnect = onConnect
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Password Required")
                        .font(.headline)
                    Text("Enter password to connect to:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(verbatim: "\(connection.username.isEmpty ? "Server" : connection.username)@\(connection.formattedHostPort)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                Spacer()
            }

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 10) {
                Text("Password:")
                    .font(.system(size: 11, weight: .medium))

                SecureField("Enter server password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submit()
                    }

                Toggle("Remember password in Keychain", isOn: $saveToKeychain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Bottom Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420, height: 230)
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        onConnect(password, saveToKeychain)
    }
}
