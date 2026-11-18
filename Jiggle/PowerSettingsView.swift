import SwiftUI

struct PowerSettingsView: View {
    @EnvironmentObject private var lidGuard: LidCloseGuard
    @AppStorage(SettingsKey.keepRunningLidClosed) private var lidClosed = SettingsDefault.keepRunningLidClosed
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
            lidClosedSection
        }
        .formStyle(.grouped)
    }

    private var lidClosedSection: some View {
        Section {
            Toggle("Keep running with the lid closed", isOn: $lidClosed)
                .disabled(!lidGuard.isSetUp)
            LabeledContent("Setup") {
                HStack {
                    Text(lidGuard.isSetUp ? "Done" : "Needed once")
                        .foregroundStyle(.secondary)
                    if lidGuard.isSetUp {
                        Button("Remove") { lidGuard.remove() }
                    } else {
                        Button("Set Up…") { lidGuard.setUp() }
                    }
                }
            }
            if lidGuard.isEngaged {
                Label("System sleep is off for this session.", systemImage: "laptopcomputer")
            }
            if let error = lidGuard.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Lid closed")
        } footer: {
            Text("""
                While a session runs, this turns off all system sleep (pmset disablesleep), even on battery, and \
                lock or screen sleep won't stop the session. Sleep comes back when the session stops, the battery \
                guard triggers, or Jiggle quits. Don't put a running Mac in a bag: it can overheat. Set Up asks for \
                your password once to install a sudo rule that only allows pmset -a disablesleep 0 or 1.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var batteryDescription: String {
        guard let status = PowerSource.current() else { return "No battery found." }
        return "Battery \(status.percent)%, \(status.onBattery ? "on battery" : "on power adapter")."
    }
}
