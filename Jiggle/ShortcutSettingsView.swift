import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var hotKey: HotKey
    @AppStorage(SettingsKey.hotkeyEnabled) private var enabled = SettingsDefault.hotkeyEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Start/stop Jiggle with \(HotKey.displayString)", isOn: $enabled)
                if hotKey.registrationFailed {
                    Label("Couldn't register \(HotKey.displayString). Another app may be using it.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Works from any app. No extra permission needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
