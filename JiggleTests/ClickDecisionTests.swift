import XCTest
@testable import Jiggle

final class ClickDecisionTests: XCTestCase {
    private func context(
        tick: Int = 5,
        everyN: Int = 5,
        flags: CGEventFlags = [],
        userActive: Bool = false,
        frontmost: String? = "com.anthropic.claudefordesktop",
        blocklist: [String] = SettingsDefault.clickBlocklist,
        onlyWhenLinkedFrontmost: Bool = false,
        frontmostIsLinked: Bool = false,
        target: ClickTarget = .pinnedPoint,
        point: CGPoint? = CGPoint(x: 10, y: 10)
    ) -> ClickContext {
        ClickContext(
            tickCount: tick, everyNTicks: everyN, modifierFlags: flags, userActive: userActive,
            frontmostBundleID: frontmost, blocklist: blocklist, onlyWhenLinkedFrontmost: onlyWhenLinkedFrontmost,
            frontmostIsLinked: frontmostIsLinked, target: target, pinnedPoint: point
        )
    }

    func testClicksWhenAllChecksPass() {
        XCTAssertNil(ClickDecision.evaluate(context()))
    }

    func testEveryNthTick() {
        let reasons = (1...10).map { ClickDecision.evaluate(context(tick: $0, everyN: 5)) }
        XCTAssertEqual(reasons.filter { $0 == nil }.count, 2)
        XCTAssertNil(reasons[4])
        XCTAssertNil(reasons[9])
        XCTAssertEqual(reasons[0], .notNthTick)
        XCTAssertNil(ClickDecision.evaluate(context(tick: 7, everyN: 1)))
    }

    func testEachModifierBlocksClick() {
        for flag in [CGEventFlags.maskCommand, .maskAlternate, .maskControl, .maskShift] {
            XCTAssertEqual(ClickDecision.evaluate(context(flags: flag)), .modifierHeld)
        }
        // Caps Lock and similar flags do not block.
        XCTAssertNil(ClickDecision.evaluate(context(flags: .maskAlphaShift)))
    }

    func testUserActiveBlocksClick() {
        XCTAssertEqual(ClickDecision.evaluate(context(userActive: true)), .userActive)
    }

    func testBlocklistedFrontmostApp() {
        XCTAssertEqual(ClickDecision.evaluate(context(frontmost: "com.apple.Terminal")), .blocklisted)
        XCTAssertNil(ClickDecision.evaluate(context(frontmost: "com.apple.Terminal", blocklist: [])))
    }

    func testOnlyWhenLinkedFrontmost() {
        XCTAssertEqual(
            ClickDecision.evaluate(context(onlyWhenLinkedFrontmost: true, frontmostIsLinked: false)),
            .linkedNotFrontmost
        )
        XCTAssertNil(ClickDecision.evaluate(context(onlyWhenLinkedFrontmost: true, frontmostIsLinked: true)))
    }

    func testPinnedTargetNeedsPoint() {
        XCTAssertEqual(ClickDecision.evaluate(context(point: nil)), .noPinnedPoint)
        XCTAssertNil(ClickDecision.evaluate(context(target: .currentPosition, point: nil)))
    }
}

@MainActor
final class JiggleClickStrategyTests: XCTestCase {
    private func makeStrategy(_ fakes: Fakes, everyN: Int = 3) throws -> (JiggleClickStrategy, SettingsStore) {
        let settings = try makeSettings()
        settings.defaults.set(everyN, forKey: SettingsKey.clickEveryNTicks)
        settings.clickPoint = CGPoint(x: 40, y: 50)
        fakes.workspace.frontmost = "com.example.editor"
        let strategy = JiggleClickStrategy(services: fakes.services, settings: settings)
        strategy.start()
        addTeardownBlock { @MainActor in strategy.stop() }
        return (strategy, settings)
    }

    func testCounterClicksOnEveryNthTick() throws {
        let fakes = Fakes()
        let (strategy, _) = try makeStrategy(fakes, everyN: 3)
        var reasons: [ClickSkipReason?] = []
        for _ in 1...6 {
            strategy.tick()
            reasons.append(strategy.lastSkipReason)
        }
        XCTAssertEqual(reasons, [.notNthTick, .notNthTick, nil, .notNthTick, .notNthTick, nil])
    }

    func testClickLandsOnPinnedPointAndCursorReturns() throws {
        let fakes = Fakes()
        let (strategy, _) = try makeStrategy(fakes, everyN: 1)
        strategy.tick()
        waitForMainQueue(seconds: 0.4)
        let pinned = CGPoint(x: 40, y: 50)
        let origin = fakes.cursor.location
        XCTAssertEqual(fakes.events.events, [
            .move(CGPoint(x: origin.x + 2, y: origin.y + 2)),
            .move(origin),
            .button(.left, down: true, pinned),
            .button(.left, down: false, pinned),
            .move(origin),
        ])
    }

    func testHeldModifierSkipsClickButStillJiggles() throws {
        let fakes = Fakes()
        let (strategy, _) = try makeStrategy(fakes, everyN: 1)
        fakes.modifiers.flags = .maskShift
        strategy.tick()
        waitForMainQueue(seconds: 0.4)
        XCTAssertEqual(strategy.lastSkipReason, .modifierHeld)
        XCTAssertEqual(fakes.events.events.count, 2)  // Jiggle out and back, no buttons.
        XCTAssertEqual(fakes.power.declarations, 1)
    }

    func testRecentUserInputSkipsClick() throws {
        let fakes = Fakes()
        let (strategy, _) = try makeStrategy(fakes, everyN: 1)
        fakes.idle.seconds = 2
        strategy.tick()
        XCTAssertEqual(strategy.lastSkipReason, .userActive)
    }

    func testBlocklistedFrontmostAppSkipsClick() throws {
        let fakes = Fakes()
        let (strategy, _) = try makeStrategy(fakes, everyN: 1)
        fakes.workspace.frontmost = "com.googlecode.iterm2"
        strategy.tick()
        XCTAssertEqual(strategy.lastSkipReason, .blocklisted)
    }

    func testOnlyWhenLinkedFrontmostUsesLinkedApps() throws {
        let fakes = Fakes()
        let (strategy, settings) = try makeStrategy(fakes, everyN: 1)
        settings.defaults.set(true, forKey: SettingsKey.clickOnlyWhenLinkedFrontmost)
        strategy.tick()
        XCTAssertEqual(strategy.lastSkipReason, .linkedNotFrontmost)

        settings.linkedApps = [LinkedApp(bundleID: "com.example.editor", name: "Editor")]
        strategy.tick()
        XCTAssertNil(strategy.lastSkipReason)
    }

    func testStopReleasesAssertions() throws {
        let fakes = Fakes()
        let (strategy, _) = try makeStrategy(fakes)
        strategy.tick()
        XCTAssertFalse(fakes.power.held.isEmpty)
        strategy.stop()
        XCTAssertTrue(fakes.power.held.isEmpty)
    }
}
