import CoreGraphics
import Foundation
import IOKit.pwr_mgt

@MainActor
protocol ActivityStrategy: AnyObject {
    func start()
    func tick()
    func stop()
}

/// Holds a display-sleep assertion from start to stop.
@MainActor
final class KeepAwakeStrategy: ActivityStrategy {
    private let power: any PowerAssertionProviding
    private var assertionID: IOPMAssertionID?

    init(power: any PowerAssertionProviding) {
        self.power = power
    }

    func start() {
        guard assertionID == nil else { return }
        assertionID = power.createDisplaySleepAssertion(reason: "Jiggle Keep Awake")
    }

    func tick() {}

    func stop() {
        if let assertionID { power.release(assertionID) }
        assertionID = nil
    }
}

/// Keep Awake plus a declared user activity every tick (resets the system idle timer).
@MainActor
final class ZenStrategy: ActivityStrategy {
    private let power: any PowerAssertionProviding
    private let keepAwake: KeepAwakeStrategy
    private var activityID: IOPMAssertionID?

    init(power: any PowerAssertionProviding) {
        self.power = power
        keepAwake = KeepAwakeStrategy(power: power)
    }

    func start() {
        keepAwake.start()
    }

    func tick() {
        activityID = power.declareUserActivity(name: "Jiggle", existing: activityID)
    }

    func stop() {
        if let activityID { power.release(activityID) }
        activityID = nil
        keepAwake.stop()
    }
}

/// Zen plus a real cursor nudge by `distance` px and back 50 ms later.
@MainActor
final class JiggleStrategy: ActivityStrategy {
    static let restoreDelay: DispatchTimeInterval = .milliseconds(50)

    private let zen: ZenStrategy
    private let cursor: any CursorLocating
    private let events: any MouseEventPosting
    private let distance: () -> Int

    init(services: SystemServices, distance: @escaping () -> Int) {
        zen = ZenStrategy(power: services.power)
        cursor = services.cursor
        events = services.events
        self.distance = distance
    }

    func start() {
        zen.start()
    }

    func tick() {
        zen.tick()
        let origin = cursor.currentLocation()
        let offset = CGFloat(distance())
        events.moveMouse(to: CGPoint(x: origin.x + offset, y: origin.y + offset))
        let events = events
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) {
            MainActor.assumeIsolated { events.moveMouse(to: origin) }
        }
    }

    func stop() {
        zen.stop()
    }
}
