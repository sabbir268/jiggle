import XCTest
@testable import Jiggle

final class StatusTextTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 0)

    private func line(
        active: Bool = true, mode: Mode? = .zen, reason: ActiveReason? = .manual, endsIn: TimeInterval? = nil,
        auto: Bool = false, rule: LinkedRule = .running, linked: [String] = []
    ) -> String {
        StatusText.line(
            isActive: active, mode: mode, reason: reason, endsAt: endsIn.map { now.addingTimeInterval($0) },
            autoEnabled: auto, rule: rule, linkedRunning: linked, now: now
        )
    }

    func testLines() {
        XCTAssertEqual(line(), "Active — Zen")
        XCTAssertEqual(line(reason: .timed, endsIn: 42 * 60), "Active — Zen · 42 min left")
        XCTAssertEqual(line(reason: .timed, endsIn: 90 * 60), "Active — Zen · 1 h 30 min left")
        XCTAssertEqual(line(reason: .linked, linked: ["Claude", "WhatsApp"]), "Active — linked: Claude, WhatsApp")
        XCTAssertEqual(line(active: false, mode: nil), "Inactive")
        XCTAssertEqual(line(active: false, mode: nil, auto: true), "Inactive — no linked app running")
    }
}

final class ScheduleWindowTests: XCTestCase {
    private func date(weekday: Int, hour: Int, minute: Int = 0) throws -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // 2026-03-01 is a Sunday (weekday 1).
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: weekday, hour: hour, minute: minute
        )))
        return (date, calendar)
    }

    func testDaytimeWindow() throws {
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let (monday10, calendar) = try date(weekday: 2, hour: 10)
        XCTAssertTrue(ScheduleWindow.contains(monday10, days: weekdays, start: 540, end: 1080, calendar: calendar))
        let (monday18, _) = try date(weekday: 2, hour: 18)
        XCTAssertFalse(ScheduleWindow.contains(monday18, days: weekdays, start: 540, end: 1080, calendar: calendar))
        let (sunday10, _) = try date(weekday: 1, hour: 10)
        XCTAssertFalse(ScheduleWindow.contains(sunday10, days: weekdays, start: 540, end: 1080, calendar: calendar))
    }

    func testOvernightWindowBelongsToStartDay() throws {
        let friday: Set<Int> = [6]
        let (friday23, calendar) = try date(weekday: 6, hour: 23)
        XCTAssertTrue(ScheduleWindow.contains(friday23, days: friday, start: 22 * 60, end: 6 * 60, calendar: calendar))
        let (saturday5, _) = try date(weekday: 7, hour: 5)
        XCTAssertTrue(ScheduleWindow.contains(saturday5, days: friday, start: 22 * 60, end: 6 * 60, calendar: calendar))
        let (thursday5, _) = try date(weekday: 5, hour: 5)
        XCTAssertFalse(ScheduleWindow.contains(thursday5, days: friday, start: 22 * 60, end: 6 * 60, calendar: calendar))
    }
}

final class BatteryGuardTests: XCTestCase {
    func testGuard() {
        XCTAssertTrue(BatteryGuard.shouldStop(BatteryStatus(onBattery: true, percent: 19), threshold: 20))
        XCTAssertFalse(BatteryGuard.shouldStop(BatteryStatus(onBattery: true, percent: 20), threshold: 20))
        XCTAssertFalse(BatteryGuard.shouldStop(BatteryStatus(onBattery: false, percent: 5), threshold: 20))
        XCTAssertFalse(BatteryGuard.shouldStop(BatteryStatus(onBattery: true, percent: 5), threshold: 0))
        XCTAssertFalse(BatteryGuard.shouldStop(nil, threshold: 20))
    }
}

final class CodingTests: XCTestCase {
    func testPointRoundTrip() {
        let point = CGPoint(x: 812.5, y: -40)
        XCTAssertEqual(PointCoding.decode(PointCoding.encode(point)), point)
        XCTAssertNil(PointCoding.decode(nil))
        XCTAssertNil(PointCoding.decode("garbage"))
    }

    func testListAndDays() {
        XCTAssertEqual(ListCoding.decode(ListCoding.encode(["a", "b"])), ["a", "b"])
        XCTAssertEqual(DayCoding.decode("2,3,9,x"), [2, 3])
        XCTAssertEqual(DayCoding.encode([6, 2]), "2,6")
    }
}
