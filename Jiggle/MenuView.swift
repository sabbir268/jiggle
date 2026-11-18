import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var engine: JiggleEngine
    @EnvironmentObject private var watcher: AppWatcher
    @EnvironmentObject private var capture: ClickPointCapture

    private static let presets: [(title: String, seconds: TimeInterval)] = [
        ("15 min", 15 * 60), ("30 min", 30 * 60), ("1 h", 60 * 60), ("2 h", 2 * 60 * 60), ("4 h", 4 * 60 * 60),
    ]

    var body: some View {
        Text(StatusText.line(
            isActive: engine.isActive, mode: engine.runningMode, reason: engine.activeReason,
            endsAt: engine.endsAt, autoEnabled: watcher.autoEnabled, rule: watcher.rule,
            linkedRunning: watcher.runningLinked.map(\.name), now: Date()
        ))
        .onAppear { engine.refreshAccessibility() }
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
        LinkedAppsMenu()
        if engine.mode == .jiggleClick {
            Button(capture.countdown == nil ? "Set Click Point…" : "Capturing in \(capture.countdown ?? 0)…") {
                capture.capturePoint()
            }
            .disabled(capture.countdown != nil)
        }
        Divider()
        SettingsMenuButton(title: "Settings…", tab: nil)
            .keyboardShortcut(",")
        Button("Quit Jiggle") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct LinkedAppsMenu: View {
    @EnvironmentObject private var watcher: AppWatcher

    var body: some View {
        Menu("Linked Apps") {
            Toggle("Auto", isOn: $watcher.autoEnabled)
            Divider()
            ForEach(watcher.linkedApps) { app in
                let running = watcher.isRunning(app)
                Button {
                    watcher.activate(app)
                } label: {
                    Label { Text(app.name) } icon: { Image(nsImage: running ? StatusDot.running : StatusDot.stopped) }
                }
                .disabled(!running)
            }
            if !watcher.linkedApps.isEmpty { Divider() }
            SettingsMenuButton(title: "Link an App…", tab: .linked)
        }
    }
}

/// Colored (non-template) dots, so the menu keeps the green.
@MainActor
enum StatusDot {
    static let running = make(.systemGreen)
    static let stopped = make(.tertiaryLabelColor)

    private static func make(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Opens Settings (optionally on a given tab) on macOS 13 (selector) and 14+ (`openSettings`),
/// and brings the window forward.
struct SettingsMenuButton: View {
    let title: String
    let tab: SettingsTab?

    var body: some View {
        if #available(macOS 14, *) {
            ModernSettingsButton(title: title, tab: tab)
        } else {
            Button(title) {
                SettingsTab.select(tab)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

@available(macOS 14, *)
private struct ModernSettingsButton: View {
    let title: String
    let tab: SettingsTab?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(title) {
            SettingsTab.select(tab)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
    }
}
