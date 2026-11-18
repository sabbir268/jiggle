import AppKit
import SwiftUI

/// Shows small auxiliary windows (permission explainer, "Until…" picker) from anywhere, including menu actions.
/// Jiggle is an agent app, so each window also activates the app to come to the front.
@MainActor
enum WindowPresenter {
    private static var windows: [String: NSWindow] = [:]

    static func show(id: String, title: String, @ViewBuilder content: () -> some View) {
        let controller = NSHostingController(rootView: content())
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
            window.contentViewController = controller
        } else {
            window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            windows[id] = window
        }
        window.title = title
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close(id: String) {
        windows[id]?.close()
    }
}
