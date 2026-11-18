import SwiftUI

@main
struct JiggleApp: App {
    @StateObject private var engine: JiggleEngine
    @StateObject private var watcher: AppWatcher
    @StateObject private var capture: ClickPointCapture

    init() {
        let engine = JiggleEngine()
        let watcher = AppWatcher()
        engine.onAccessibilityNeeded = { PermissionExplainer.show() }
        engine.attach(to: watcher)
        _engine = StateObject(wrappedValue: engine)
        _watcher = StateObject(wrappedValue: watcher)
        _capture = StateObject(wrappedValue: ClickPointCapture())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(engine)
                .environmentObject(watcher)
                .environmentObject(capture)
        } label: {
            if let countdown = capture.countdown {
                Text("\(Image(systemName: "scope")) \(countdown)")
            } else {
                Image(systemName: menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(engine)
                .environmentObject(watcher)
                .environmentObject(capture)
        }
    }

    private var menuBarSymbol: String {
        guard engine.isActive else { return "cursorarrow" }
        return engine.runningMode == .jiggleClick ? "cursorarrow.click.2" : "cursorarrow.motionlines"
    }
}
