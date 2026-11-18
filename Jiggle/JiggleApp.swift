import SwiftUI

@main
struct JiggleApp: App {
    @StateObject private var engine: JiggleEngine

    init() {
        let engine = JiggleEngine()
        engine.onAccessibilityNeeded = { PermissionExplainer.show() }
        _engine = StateObject(wrappedValue: engine)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(engine)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(engine)
        }
    }

    private var menuBarSymbol: String {
        guard engine.isActive else { return "cursorarrow" }
        return engine.mode == .jiggleClick ? "cursorarrow.click.2" : "cursorarrow.motionlines"
    }
}
