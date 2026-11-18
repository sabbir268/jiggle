import SwiftUI

struct PowerSettingsView: View {
    @AppStorage(SettingsKey.batteryGuardPercent) private var batteryGuard = SettingsDefault.batteryGuardPercent
    @AppStorage(SettingsKey.stopOnLock) private var stopOnLock = SettingsDefault.stopOnLock
    @AppStorage(SettingsKey.resumeOnUnlock) private var resumeOnUnlock = SettingsDefault.resumeOnUnlock

    private static let guardOptions = [0, 10, 20, 30, 50]

    var body: some View {
        Form {
            Section {
                Picker("Stop on battery below", selection: $batteryGuard) {
                    ForEach(Self.guardOptions, id: \.self) { percent in
                        Text(percent == 0 ? "Off" : "\(percent)%").tag(percent)
                    }
                }
                Text(batteryDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Stop when the screen locks or the Mac sleeps", isOn: $stopOnLock)
                Toggle("Resume when unlocked", isOn: $resumeOnUnlock)
                    .disabled(!stopOnLock)
            }
        }
        .formStyle(.grouped)
    }

    private var batteryDescription: String {
        guard let status = PowerSource.current() else { return "No battery found." }
        return "Battery \(status.percent)%, \(status.onBattery ? "on battery" : "on power adapter")."
    }
}
