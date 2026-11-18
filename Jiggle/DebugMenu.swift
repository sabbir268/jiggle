import SwiftUI

/// Temporary M1 test menu. Remove in M4.
struct DebugMenuView: View {
    @EnvironmentObject private var engine: JiggleEngine
    @AppStorage(SettingsKey.intervalSeconds) private var interval = SettingsDefault.intervalSeconds
    @AppStorage(SettingsKey.smartPause) private var smartPause = SettingsDefault.smartPause
    @AppStorage(SettingsKey.jitterEnabled) private var jitter = SettingsDefault.jitterEnabled

    var body: some View {
        Text(status)
        Divider()
        Button(engine.isActive ? "Stop" : "Start") { engine.toggle() }
        Button("Start for 1 min") { engine.start(duration: 60) }
        Button("Start for 15 min") { engine.start(duration: 15 * 60) }
        Picker("Mode", selection: $engine.mode) {
            ForEach(Mode.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Text("Debug")
        Picker("Interval", selection: $interval) {
            ForEach([10, 30, 60, 120], id: \.self) { Text("\($0) s").tag($0) }
        }
        Toggle("Smart pause", isOn: $smartPause)
        Toggle("Jitter", isOn: $jitter)
        Divider()
        Button("Quit Jiggle") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        guard engine.isActive else { return "Inactive" }
        var parts = ["Active", engine.mode.title]
        if let reason = engine.activeReason { parts.append(reason.rawValue) }
        if let endsAt = engine.endsAt {
            let seconds = max(0, Int(endsAt.timeIntervalSinceNow))
            parts.append("\(seconds / 60)m \(seconds % 60)s left")
        }
        return parts.joined(separator: " - ")
    }
}
