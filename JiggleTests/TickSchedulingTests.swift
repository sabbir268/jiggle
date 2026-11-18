import XCTest
@testable import Jiggle

final class TickSchedulingTests: XCTestCase {
    func testJitterStaysWithinTwentyPercent() {
        for _ in 0..<1_000 {
            let delay = TickScheduling.jittered(base: 60, enabled: true)
            XCTAssertGreaterThanOrEqual(delay, 48)
            XCTAssertLessThanOrEqual(delay, 72)
        }
    }

    func testJitterRangeEndpoints() {
        XCTAssertEqual(TickScheduling.jittered(base: 60, enabled: true) { $0.lowerBound }, 48, accuracy: 0.0001)
        XCTAssertEqual(TickScheduling.jittered(base: 60, enabled: true) { $0.upperBound }, 72, accuracy: 0.0001)
    }

    func testJitterDisabledReturnsBase() {
        XCTAssertEqual(TickScheduling.jittered(base: 60, enabled: false) { _ in 999 }, 60)
    }

    func testEndsAtAddsDuration() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertEqual(TickScheduling.endsAt(duration: 15 * 60, from: now), now.addingTimeInterval(900))
        XCTAssertNil(TickScheduling.endsAt(duration: nil, from: now))
    }

    func testNextDelayIsCappedByEndsAt() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertEqual(TickScheduling.nextDelay(jitteredInterval: 60, endsAt: nil, now: now), 60)
        XCTAssertEqual(TickScheduling.nextDelay(jitteredInterval: 60, endsAt: now.addingTimeInterval(20), now: now), 20)
        XCTAssertEqual(
            TickScheduling.nextDelay(jitteredInterval: 60, endsAt: now.addingTimeInterval(-5), now: now),
            TickScheduling.minimumDelay
        )
    }

    func testHasEnded() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertFalse(TickScheduling.hasEnded(endsAt: nil, now: now))
        XCTAssertFalse(TickScheduling.hasEnded(endsAt: now.addingTimeInterval(10), now: now))
        XCTAssertTrue(TickScheduling.hasEnded(endsAt: now.addingTimeInterval(0.2), now: now))
        XCTAssertTrue(TickScheduling.hasEnded(endsAt: now.addingTimeInterval(-1), now: now))
    }

    func testNextOccurrenceIsTodayOrTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 14)))
        let later = try XCTUnwrap(calendar.date(bySettingHour: 17, minute: 30, second: 0, of: now))
        let earlier = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now))

        XCTAssertEqual(TickScheduling.nextOccurrence(of: later, after: now, calendar: calendar), later)
        XCTAssertEqual(
            TickScheduling.nextOccurrence(of: earlier, after: now, calendar: calendar),
            earlier.addingTimeInterval(24 * 60 * 60)
        )
    }

    func testCocoaToCGFlipsYAgainstPrimaryScreen() {
        let height: CGFloat = 1_080
        XCTAssertEqual(CoordinateConversion.cocoaToCG(CGPoint(x: 100, y: 1_080), primaryScreenHeight: height), .init(x: 100, y: 0))
        XCTAssertEqual(CoordinateConversion.cocoaToCG(CGPoint(x: 100, y: 0), primaryScreenHeight: height), .init(x: 100, y: 1_080))
        XCTAssertEqual(CoordinateConversion.cocoaToCG(CGPoint(x: 5, y: 80), primaryScreenHeight: height), .init(x: 5, y: 1_000))
        // A screen above the primary one has y > height in Cocoa, so negative y in CG.
        XCTAssertEqual(CoordinateConversion.cocoaToCG(CGPoint(x: 0, y: 1_280), primaryScreenHeight: height), .init(x: 0, y: -200))
    }
}
