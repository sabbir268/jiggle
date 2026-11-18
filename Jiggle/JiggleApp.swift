import SwiftUI

@main
struct JiggleApp: App {
    @StateObject private var engine = JiggleEngine()

    var body: some Scene {
        MenuBarExtra {
            DebugMenuView()
                .environmentObject(engine)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        guard engine.isActive else { return "cursorarrow" }
        return engine.mode == .jiggleClick ? "cursorarrow.click.2" : "cursorarrow.motionlines"
    }
}
