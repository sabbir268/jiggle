import AppKit
import CoreGraphics
import IOKit.pwr_mgt

/// IOKit power assertions.
@MainActor
protocol PowerAssertionProviding: Sendable {
    /// Creates a `PreventUserIdleDisplaySleep` assertion. Returns nil on failure.
    func createDisplaySleepAssertion(reason: String) -> IOPMAssertionID?
    /// Declares user activity, reusing `existing` when given. The returned ID must be released.
    func declareUserActivity(name: String, existing: IOPMAssertionID?) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
}

/// Seconds since the last real keyboard/mouse input.
@MainActor
protocol IdleTimeProviding: Sendable {
    func secondsSinceLastInput() -> TimeInterval
}

/// Current cursor position in CG global coordinates (top-left origin).
@MainActor
protocol CursorLocating: Sendable {
    func currentLocation() -> CGPoint
}

/// Synthetic mouse events.
@MainActor
protocol MouseEventPosting: Sendable {
    func moveMouse(to point: CGPoint)
}

/// Accessibility (synthetic input) permission.
@MainActor
protocol AccessibilityChecking: Sendable {
    func isTrusted() -> Bool
}

/// Everything the engine and strategies need from the system, so tests can swap in fakes.
@MainActor
struct SystemServices {
    var power: any PowerAssertionProviding
    var idle: any IdleTimeProviding
    var cursor: any CursorLocating
    var events: any MouseEventPosting
    var accessibility: any AccessibilityChecking

    static var live: SystemServices {
        SystemServices(
            power: IOKitPowerAssertions(),
            idle: IdleMonitor(),
            cursor: SystemCursor(),
            events: CGEventPoster(),
            accessibility: SystemAccessibility()
        )
    }
}

// MARK: - Live implementations

struct IOKitPowerAssertions: PowerAssertionProviding {
    func createDisplaySleepAssertion(reason: String) -> IOPMAssertionID? {
        var id = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    func declareUserActivity(name: String, existing: IOPMAssertionID?) -> IOPMAssertionID? {
        var id = existing ?? IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionDeclareUserActivity(name as CFString, kIOPMUserActiveLocal, &id)
        return result == kIOReturnSuccess ? id : existing
    }

    func release(_ id: IOPMAssertionID) {
        IOPMAssertionRelease(id)
    }
}

struct SystemCursor: CursorLocating {
    func currentLocation() -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CoordinateConversion.cocoaToCG(NSEvent.mouseLocation, primaryScreenHeight: primaryHeight)
    }
}

struct CGEventPoster: MouseEventPosting {
    func moveMouse(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
