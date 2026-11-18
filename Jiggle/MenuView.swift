import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var engine: JiggleEngine

    private static let presets: [(title: String, seconds: TimeInterval)] = [
        ("15 min", 15 * 60), ("30 min", 30 * 60), ("1 h", 60 * 60), ("2 h", 2 * 60 * 60), ("4 h", 4 * 60 * 60),
    ]

    var body: some View {
        Text(StatusText.line(
            isActive: engine.isActive, mode: engine.runningMode, endsAt: engine.endsAt, now: Date()
        ))
        if let warning = engine.warning {
            Label(warning, systemImage: "exclamationmark.triangle")
            Button("Grant Accessibility…") { PermissionExplainer.show() }
        }
        Divider()
        Button(engine.isActive ? "Stop" : "Start") { engine.toggle() }
        Menu("Start for") {
            ForEach(Self.presets, id: \.title) { preset in
                Button(preset.title) { engine.start(duration: preset.seconds) }
            }
            Divider()
            Button("Until…") { UntilPicker.show(engine: engine) }
            Button("Indefinitely") { engine.start() }
        }
        Picker("Mode", selection: $engine.mode) {
            ForEach(Mode.allCases) { Text($0.title).tag($0) }
        }
        #if DEBUG
        DebugMenu()
        #endif
        Divider()
        SettingsMenuButton()
        Button("Quit Jiggle") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// "Settings…" that works on macOS 13 (selector) and 14+ (`openSettings`), and brings the window forward.
struct SettingsMenuButton: View {
    var body: some View {
        if #available(macOS 14, *) {
            ModernSettingsButton()
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }
}

@available(macOS 14, *)
private struct ModernSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
    }
}
