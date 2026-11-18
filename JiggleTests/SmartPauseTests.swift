import XCTest
@testable import Jiggle

final class SmartPauseTests: XCTestCase {
    func testIdleLongerThanIntervalDoesNotSkip() {
        XCTAssertFalse(SmartPause.shouldSkipTick(idleSeconds: 61, interval: 60, secondsSinceOwnActivity: nil))
        XCTAssertFalse(SmartPause.shouldSkipTick(idleSeconds: 60, interval: 60, secondsSinceOwnActivity: nil))
    }

    func testRecentUserInputSkips() {
        XCTAssertTrue(SmartPause.shouldSkipTick(idleSeconds: 5, interval: 60, secondsSinceOwnActivity: nil))
    }

    func testOwnPreviousTickIsNotUserInput() {
        // Our last tick was 50 s ago and the latest input is ~50 s old: that input was ours.
        XCTAssertFalse(SmartPause.shouldSkipTick(idleSeconds: 49.9, interval: 60, secondsSinceOwnActivity: 50))
        // Jitter made this tick come early (48 s): still our own input.
        XCTAssertFalse(SmartPause.shouldSkipTick(idleSeconds: 48, interval: 60, secondsSinceOwnActivity: 48))
    }

    func testUserInputAfterOwnTickSkips() {
        XCTAssertTrue(SmartPause.shouldSkipTick(idleSeconds: 10, interval: 60, secondsSinceOwnActivity: 50))
    }
}
