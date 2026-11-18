import SwiftUI

/// Temporary test submenu (Debug builds only). Remove in M4.
struct DebugMenu: View {
    @EnvironmentObject private var engine: JiggleEngine
    @AppStorage(SettingsKey.intervalSeconds) private var interval = SettingsDefault.intervalSeconds
    @AppStorage(SettingsKey.smartPause) private var smartPause = SettingsDefault.smartPause
    @AppStorage(SettingsKey.jitterEnabled) private var jitter = SettingsDefault.jitterEnabled

    var body: some View {
        Menu("Debug") {
            Button("Start for 1 min") { engine.start(duration: 60) }
            Picker("Interval", selection: $interval) {
                ForEach([10, 30, 60, 120], id: \.self) { Text("\($0) s").tag($0) }
            }
            Toggle("Smart pause", isOn: $smartPause)
            Toggle("Jitter", isOn: $jitter)
        }
        .onChange(of: interval) { _ in engine.intervalDidChange() }
    }
}
