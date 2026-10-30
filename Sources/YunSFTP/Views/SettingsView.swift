import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    public init() {}

    public var body: some View {
        TabView {
            generalTab.tabItem { Label(L("General"), systemImage: "gearshape") }
            columnsTab.tabItem { Label(L("List"), systemImage: "list.bullet.rectangle") }
            connectionsTab.tabItem { Label(L("Connections"), systemImage: "network") }
        }
        .frame(width: 440)
        .padding(.bottom, 8)
    }

    private var generalTab: some View {
        Form {
            Toggle(L("Show relative dates (Today, Yesterday)"), isOn: $store.settings.showRelativeDates)
            Toggle(L("Ask before deleting files on a server"), isOn: $store.settings.confirmRemoteDelete)
            Toggle(L("Check for updates once a day"), isOn: $store.settings.checkForUpdates)
            Text(L("A single request to GitHub Releases. Nothing about you or your servers is sent."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(L("Open SSH sessions in"), selection: $store.settings.terminalApp) {
                ForEach(TerminalApp.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
    }

    private var columnsTab: some View {
        Form {
            Section(L("Columns")) {
                Toggle(L("Size"), isOn: $store.settings.showSize)
                Toggle(L("Date Modified"), isOn: $store.settings.showDateModified)
                Toggle(L("Kind"), isOn: $store.settings.showKind)
                Toggle(L("Permissions"), isOn: $store.settings.showPermissions)
            }
            Section(L("Text")) {
                HStack {
                    Slider(value: $store.settings.fontSize, in: AppSettings.fontSizeRange, step: 1) {
                        Text(L("Font size"))
                    }
                    Text("\(Int(store.settings.fontSize)) pt")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(20)
    }

    private var connectionsTab: some View {
        Form {
            Picker(L("Transfer engine"), selection: $store.settings.transferEngine) {
                Text(L("Native (recommended)")).tag(TransferEngine.native)
                Text(L("OpenSSH command-line tools")).tag(TransferEngine.openSSH)
            }
            .pickerStyle(.radioGroup)
            Text(L("The native engine gives byte-level progress and faster operations. OpenSSH is used automatically for servers or keys it cannot handle."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Toggle(L("Allow legacy SSH algorithms on new connections"), isOn: $store.settings.legacyAlgorithmsByDefault)
            Text("Only needed for old devices that fail with \"no matching key exchange method\". Existing connections keep their own setting.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
