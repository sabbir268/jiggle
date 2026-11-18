import AppKit
import SwiftUI

/// The menu bar icon. Its own view so it re-renders when the engine, the click-point countdown or
/// lid-closed mode changes.
struct MenuBarLabel: View {
    @ObservedObject var engine: JiggleEngine
    @ObservedObject var capture: ClickPointCapture
    @ObservedObject var lidGuard: LidCloseGuard

    var body: some View {
        if let countdown = capture.countdown {
            Text("\(Image(systemName: "scope")) \(countdown)")
        } else if lidGuard.isEngaged, let tinted = MenuBarIcon.lidClosed(symbol) {
            Image(nsImage: tinted)
        } else {
            Image(systemName: symbol)
        }
    }

    private var symbol: String {
        guard engine.isActive else { return "cursorarrow" }
        return engine.runningMode == .jiggleClick ? "cursorarrow.click.2" : "cursorarrow.motionlines"
    }
}

@MainActor
enum MenuBarIcon {
    /// A soft red, readable on both light and dark menu bars.
    static let lidClosedColor = NSColor.systemRed.blended(withFraction: 0.2, of: .white) ?? .systemRed

    /// Menu bar images are monochrome templates; a palette color plus `isTemplate = false` keeps the tint.
    static func lidClosed(_ symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [lidClosedColor]))
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Jiggle, lid-closed mode")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }
}
