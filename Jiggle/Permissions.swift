import AppKit
import ApplicationServices

enum Permissions {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt and adds Jiggle to the Accessibility list (unchecked).
    static func requestAccessibility() {
        // Literal value of kAXTrustedCheckOptionPrompt (the C global is not concurrency-safe to reference).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SystemAccessibility: AccessibilityChecking {
    func isTrusted() -> Bool { Permissions.isAccessibilityTrusted() }
}
