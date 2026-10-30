import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    public init() {}

    public var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            columnsTab.tabItem { Label("List", systemImage: "list.bullet.rectangle") }
            connectionsTab.tabItem { Label("Connections", systemImage: "network") }
        }
        .frame(width: 440)
        .padding(.bottom, 8)
    }

    private var generalTab: some View {
        Form {
            Toggle("Show relative dates (Today, Yesterday)", isOn: $store.settings.showRelativeDates)
            Toggle("Ask before deleting files on a server", isOn: $store.settings.confirmRemoteDelete)
            Toggle("Check for updates once a day", isOn: $store.settings.checkForUpdates)
            Text("A single request to GitHub Releases. Nothing about you or your servers is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Open SSH sessions in", selection: $store.settings.terminalApp) {
                ForEach(TerminalApp.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
    }

    private var columnsTab: some View {
        Form {
            Section("Columns") {
                Toggle("Size", isOn: $store.settings.showSize)
                Toggle("Date Modified", isOn: $store.settings.showDateModified)
                Toggle("Kind", isOn: $store.settings.showKind)
                Toggle("Permissions", isOn: $store.settings.showPermissions)
            }
            Section("Text") {
                HStack {
                    Slider(value: $store.settings.fontSize, in: AppSettings.fontSizeRange, step: 1) {
                        Text("Font size")
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
            Toggle("Allow legacy SSH algorithms on new connections", isOn: $store.settings.legacyAlgorithmsByDefault)
            Text("Only needed for old devices that fail with \"no matching key exchange method\". Existing connections keep their own setting.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
