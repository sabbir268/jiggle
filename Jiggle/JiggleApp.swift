import SwiftUI

@main
struct JiggleApp: App {
    @StateObject private var engine: JiggleEngine
    @StateObject private var watcher: AppWatcher
    @StateObject private var capture: ClickPointCapture
    @StateObject private var automation: Automation

    init() {
        let engine = JiggleEngine()
        let watcher = AppWatcher()
        engine.onAccessibilityNeeded = { PermissionExplainer.show() }
        if !Self.isRunningTests { engine.attach(to: watcher) }
        _engine = StateObject(wrappedValue: engine)
        _watcher = StateObject(wrappedValue: watcher)
        _capture = StateObject(wrappedValue: ClickPointCapture())
        _automation = StateObject(wrappedValue: Automation(engine: engine, startServices: !Self.isRunningTests))
    }

    /// Unit tests run inside the app; skip auto-start wiring so a test run never starts a real session.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(engine)
                .environmentObject(watcher)
                .environmentObject(capture)
                .environmentObject(automation.lidGuard)
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
                .environmentObject(automation.hotKey)
                .environmentObject(automation.loginItem)
                .environmentObject(automation.lidGuard)
        }
    }

    private var menuBarSymbol: String {
        guard engine.isActive else { return "cursorarrow" }
        return engine.runningMode == .jiggleClick ? "cursorarrow.click.2" : "cursorarrow.motionlines"
    }
}
