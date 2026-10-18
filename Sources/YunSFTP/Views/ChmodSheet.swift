import SwiftUI

public struct ChmodSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: FileItem
    let onApply: (String, Bool) -> Void

    @State private var ownerRead: Bool = true
    @State private var ownerWrite: Bool = true
    @State private var ownerExec: Bool = false

    @State private var groupRead: Bool = true
    @State private var groupWrite: Bool = false
    @State private var groupExec: Bool = false

    @State private var otherRead: Bool = true
    @State private var otherWrite: Bool = false
    @State private var otherExec: Bool = false

    @State private var recursive: Bool = false

    public init(item: FileItem, onApply: @escaping (String, Bool) -> Void) {
        self.item = item
        self.onApply = onApply
    }

    private var octalValue: String {
        let owner = (ownerRead ? 4 : 0) + (ownerWrite ? 2 : 0) + (ownerExec ? 1 : 0)
        let group = (groupRead ? 4 : 0) + (groupWrite ? 2 : 0) + (groupExec ? 1 : 0)
        let other = (otherRead ? 4 : 0) + (otherWrite ? 2 : 0) + (otherExec ? 1 : 0)
        return "0\(owner)\(group)\(other)"
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: item.isDirectory ? "folder.fill" : "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions (chmod)")
                        .font(.headline)
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Divider()

            // Permission Grid
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    Text("Read").font(.caption.bold())
                    Text("Write").font(.caption.bold())
                    Text("Execute").font(.caption.bold())
                }
                GridRow {
                    Text("Owner").font(.callout.bold())
                    Toggle("", isOn: $ownerRead)
                    Toggle("", isOn: $ownerWrite)
                    Toggle("", isOn: $ownerExec)
                }
                GridRow {
                    Text("Group").font(.callout.bold())
                    Toggle("", isOn: $groupRead)
                    Toggle("", isOn: $groupWrite)
                    Toggle("", isOn: $groupExec)
                }
                GridRow {
                    Text("Others").font(.callout.bold())
                    Toggle("", isOn: $otherRead)
                    Toggle("", isOn: $otherWrite)
                    Toggle("", isOn: $otherExec)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 8)

            Divider()

            // Octal notation display
            HStack {
                Text("Octal notation:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(octalValue)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Spacer()
            }

            if item.isDirectory {
                HStack {
                    Toggle("Apply recursively to enclosed files and folders", isOn: $recursive)
                        .font(.subheadline)
                    Spacer()
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Apply") {
                    let mode = octalValue.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                    onApply(mode.isEmpty ? "0" : mode, recursive)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            parseInitialPermissions()
        }
    }

    private func parseInitialPermissions() {
        let perms = item.posixPermissions
        // Example: "rwxr-xr-x" or "-rwxr-xr-x"
        let chars = Array(perms.suffix(9))
        if chars.count == 9 {
            ownerRead = chars[0] == "r"
            ownerWrite = chars[1] == "w"
            ownerExec = chars[2] == "x" || chars[2] == "s"

            groupRead = chars[3] == "r"
            groupWrite = chars[4] == "w"
            groupExec = chars[5] == "x" || chars[5] == "s"

            otherRead = chars[6] == "r"
            otherWrite = chars[7] == "w"
            otherExec = chars[8] == "x" || chars[8] == "t"
        } else if item.isDirectory {
            ownerRead = true; ownerWrite = true; ownerExec = true
            groupRead = true; groupWrite = false; groupExec = true
            otherRead = true; otherWrite = false; otherExec = true
        } else {
            ownerRead = true; ownerWrite = true; ownerExec = false
            groupRead = true; groupWrite = false; groupExec = false
            otherRead = true; otherWrite = false; otherExec = false
        }
    }
}
