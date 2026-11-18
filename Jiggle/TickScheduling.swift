import CoreGraphics
import Foundation

enum TickScheduling {
    /// Shortest delay we arm the timer with, so a session that is already over still fires promptly.
    static let minimumDelay: TimeInterval = 0.05

    /// `base` ± `fraction` when jitter is enabled, else `base`.
    static func jittered(
        base: TimeInterval,
        enabled: Bool,
        fraction: Double = SettingsDefault.jitterFraction,
        random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> TimeInterval {
        guard enabled, fraction > 0 else { return base }
        return base * random((1 - fraction)...(1 + fraction))
    }

    static func endsAt(duration: TimeInterval?, from now: Date) -> Date? {
        duration.map { now.addingTimeInterval($0) }
    }

    /// Delay until the next tick: the jittered interval, capped so a timed session ends on time.
    static func nextDelay(jitteredInterval: TimeInterval, endsAt: Date?, now: Date) -> TimeInterval {
        var delay = jitteredInterval
        if let endsAt { delay = min(delay, endsAt.timeIntervalSince(now)) }
        return max(delay, minimumDelay)
    }

    /// The next moment (today or tomorrow) with the hour and minute of `time`, for "Start until…".
    static func nextOccurrence(of time: Date, after now: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let candidate = calendar.nextDate(
            after: now, matching: DateComponents(hour: parts.hour, minute: parts.minute, second: 0),
            matchingPolicy: .nextTime
        )
        return candidate ?? now.addingTimeInterval(24 * 60 * 60)
    }

    /// True once `endsAt` has passed (with a little tolerance for timer leeway).
    static func hasEnded(endsAt: Date?, now: Date, tolerance: TimeInterval = 0.5) -> Bool {
        guard let endsAt else { return false }
        return now.addingTimeInterval(tolerance) >= endsAt
    }
}

enum CoordinateConversion {
    /// Cocoa global (bottom-left origin of the primary screen) → CG global (top-left origin).
    static func cocoaToCG(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
