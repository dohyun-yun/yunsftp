import SwiftUI

public struct BatchRenameSheet: View {
    let items: [FileItem]
    var pane: PaneModel? = nil
    var onRenamed: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var rule = BatchRenameRule()
    @State private var isRenaming = false
    @State private var errorMessage: String? = nil

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Multi-Rename (\(items.count) items)")
                    .font(.headline)
                Spacer()
            }

            // Rule Configuration
            GroupBox(label: Text("Rename Rule").font(.subheadline.bold())) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Action:", selection: $rule.actionType) {
                        ForEach(RenameActionType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch rule.actionType {
                    case .replaceText:
                        HStack {
                            TextField("Find text:", text: $rule.findText)
                            TextField("Replace with:", text: $rule.replaceText)
                        }
                        Toggle("Case sensitive", isOn: $rule.caseSensitive)

                    case .addPrefix:
                        TextField("Prefix:", text: $rule.prefixText)

                    case .addSuffix:
                        TextField("Suffix:", text: $rule.suffixText)

                    case .changeCase:
                        Picker("Case:", selection: $rule.caseType) {
                            ForEach(CaseType.allCases) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }

                    case .numbering:
                        HStack {
                            Stepper("Start: \(rule.startNumber)", value: $rule.startNumber, in: 0...9999)
                            Stepper("Step: \(rule.stepNumber)", value: $rule.stepNumber, in: 1...100)
                            Stepper("Digits: \(rule.paddingDigits)", value: $rule.paddingDigits, in: 1...6)
                        }
                    }

                    Toggle("Apply to file extension", isOn: $rule.applyToExtension)
                }
                .padding(8)
            }

            // Preview Table
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview:")
                    .font(.subheadline.bold())

                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let newName = rule.apply(to: item.name, index: index)
                        HStack(spacing: 10) {
                            Text(item.name)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .help(item.name)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)

                            Text(newName)
                                .font(.system(size: 11, weight: item.name != newName ? .bold : .regular))
                                .foregroundColor(item.name != newName ? .primary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .help(newName)
                        }
                    }
                }
                .frame(height: 190)
                .border(Color.secondary.opacity(0.2))
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Rename All") {
                    performRename()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isRenaming || items.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 680, idealWidth: 700, minHeight: 490)
    }

    private func performRename() {
        isRenaming = true
        errorMessage = nil

        let isRemote = pane?.isRemote ?? (items.first?.url.scheme == "sftp")
        let conn = pane?.remoteConnection
        let pwd = pane?.remotePassword ?? (conn?.authType == .password ? (conn != nil ? KeychainService.shared.loadPassword(for: conn!) : nil) : nil)

        Task {
            do {
                for (index, item) in items.enumerated() {
                    let newName = rule.apply(to: item.name, index: index).precomposedStringWithCanonicalMapping
                    if newName != item.name && !newName.isEmpty {
                        if isRemote, let conn = conn {
                            let oldPath = SFTPService.normalizeRemotePath(item.url.path)
                            let parent = (oldPath as NSString).deletingLastPathComponent
                            let cleanParent = parent.isEmpty ? "/" : parent
                            let newPath = cleanParent == "/" ? "/\(newName)" : "\(cleanParent)/\(newName)"
                            try await SFTPService.shared.rename(remotePath: oldPath, to: newPath, connection: conn, password: pwd)
                        } else {
                            _ = try await FileSystemService.shared.rename(url: item.url, to: newName)
                        }
                    }
                }
                await MainActor.run {
                    isRenaming = false
                    onRenamed()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRenaming = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
