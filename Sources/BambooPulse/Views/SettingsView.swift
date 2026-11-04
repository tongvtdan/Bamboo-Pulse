import SwiftUI
import PulseCore

struct SettingsView: View {
    @Bindable var preferences: DisplayPreferences
    let store: MonitorStore
    let attention: NeedsYouNotifications

    var manageSetup: (() -> Void)? = nil
    var usesExistingMonitoring = false

    var body: some View {
        let status = MonitoringStatus(store: store)
        Form {
            Section("Bamboo Pulse") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
            }
            Section("Display") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(DisplayAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Layout", selection: $preferences.viewType) {
                    ForEach(PopoverViewType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .help("Normal shows bamboo. Compact shows a colored status symbol.")
                Toggle("Show session labels", isOn: $preferences.showAliases)
                Toggle("Show session status", isOn: $preferences.showSessionStatus)
            }
            Section("Notifications") {
                Toggle("Notify when a session needs you", isOn: Binding(
                    get: { attention.isEnabled },
                    set: { enabled in Task { await attention.setEnabled(enabled) } }))
                    .disabled(store.isSynthetic)
                if attention.isEnabled && (attention.authorization == .notDetermined || attention.permissionRequestFailed) {
                    Button("Allow notifications…") { Task { await attention.setEnabled(true) } }
                        .disabled(store.isSynthetic || attention.isRequestingPermission)
                }
                Text(attention.statusMessage).font(.callout).foregroundStyle(.secondary)
                Button("Send test notification") { Task { await attention.sendTestNotification() } }
                    .disabled(store.isSynthetic || !attention.isEnabled || attention.isSendingTest || attention.isRequestingPermission)
                if let result = attention.testStatus {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Monitoring") {
                if usesExistingMonitoring {
                    Text("Using existing local monitoring.").foregroundStyle(.secondary)
                }
                if let manageSetup { Button("Manage monitoring…", action: manageSetup) }
                LabeledContent(status.headline, value: status.inventory)
                if let recovery = status.recovery {
                    Text(status.detail).foregroundStyle(.secondary)
                    Text(recovery).font(.callout)
                } else if store.isSynthetic {
                    Text(status.detail).foregroundStyle(.secondary)
                }
            }
            Section("Status guide") {
                StatusLegend()
                Text("Activity and a finished turn don’t mean the task succeeded.").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("About monitoring") {
                    Text(status.coverage).foregroundStyle(.secondary)
                    Text("Unknown means a session’s current status isn’t available.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
    }
}
