import CoreGraphics
import Foundation

struct IdleMonitor: IdleTimeProviding {
    /// `kCGAnyInputEventType`: matches every input event type.
    static let anyInputEventType = CGEventType(rawValue: ~0)!

    func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEventType)
    }
}

enum SmartPause {
    /// Input within this many seconds after Jiggle's own tick is attributed to Jiggle (e.g. the 50 ms restore move).
    static let ownActivityGrace: TimeInterval = 1.0

    /// True when the user was active within `interval` and the tick should be skipped.
    /// Input that Jiggle itself generated on its previous tick does not count as user activity.
    static func shouldSkipTick(
        idleSeconds: TimeInterval,
        interval: TimeInterval,
        secondsSinceOwnActivity: TimeInterval?
    ) -> Bool {
        guard idleSeconds < interval else { return false }
        if let own = secondsSinceOwnActivity, idleSeconds >= own - ownActivityGrace {
            return false  // The most recent input is our own synthetic activity.
        }
        return true
    }
}
