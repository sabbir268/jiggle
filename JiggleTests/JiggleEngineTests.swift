import XCTest
@testable import Jiggle

@MainActor
final class JiggleEngineTests: XCTestCase {
    private func makeEngine(_ fakes: Fakes, mode: Mode, now: Date = Date()) throws -> JiggleEngine {
        let settings = try makeSettings()
        settings.mode = mode
        let engine = JiggleEngine(settings: settings, services: fakes.services) { now }
        addTeardownBlock { @MainActor in engine.stop() }
        return engine
    }

    func testStopReleasesKeepAwakeAssertion() throws {
        let fakes = Fakes()
        let engine = try makeEngine(fakes, mode: .keepAwake)
        engine.start()
        XCTAssertEqual(fakes.power.held.count, 1)
        XCTAssertEqual(engine.activeReason, .manual)
        engine.stop()
        XCTAssertTrue(fakes.power.held.isEmpty)
        XCTAssertFalse(engine.isActive)
    }

    func testSwitchingModesKeepsExactlyOneAssertion() throws {
        let fakes = Fakes()
        let engine = try makeEngine(fakes, mode: .zen)
        engine.start()
        for mode in [Mode.keepAwake, .jiggle, .jiggleClick, .zen] {
            engine.mode = mode
            XCTAssertEqual(fakes.power.held.count, 1, "\(mode)")
            XCTAssertEqual(engine.runningMode, mode)
        }
        engine.toggle()
        XCTAssertTrue(fakes.power.held.isEmpty)
    }

    func testTimedSessionEndsAt() throws {
        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        let engine = try makeEngine(Fakes(), mode: .zen, now: now)
        engine.start(duration: 30 * 60)
        XCTAssertEqual(engine.endsAt, now.addingTimeInterval(1_800))
        XCTAssertEqual(engine.activeReason, .timed)
        engine.start()
        XCTAssertNil(engine.endsAt)
        XCTAssertEqual(engine.activeReason, .manual)
    }

    func testJiggleWithoutAccessibilityFallsBackToZen() throws {
        let fakes = Fakes()
        fakes.accessibility.trusted = false
        let engine = try makeEngine(fakes, mode: .jiggle)
        var prompts = 0
        engine.onAccessibilityNeeded = { prompts += 1 }
        engine.start()
        XCTAssertEqual(engine.mode, .jiggle)
        XCTAssertEqual(engine.runningMode, .zen)
        XCTAssertNotNil(engine.warning)
        XCTAssertEqual(prompts, 1)

        fakes.accessibility.trusted = true
        engine.mode = .jiggleClick
        XCTAssertEqual(engine.runningMode, .jiggleClick)
        XCTAssertNil(engine.warning)
    }

    func testGrantWhileStoppedClearsWarning() throws {
        let fakes = Fakes()
        fakes.accessibility.trusted = false
        let engine = try makeEngine(fakes, mode: .zen)
        engine.mode = .jiggle  // Chosen while stopped, without permission.
        XCTAssertNotNil(engine.warning)

        fakes.accessibility.trusted = true
        engine.refreshAccessibility()
        XCTAssertNil(engine.warning)
        XCTAssertFalse(engine.isActive)
    }

    func testGrantWhileRunningUpgradesFromZen() throws {
        let fakes = Fakes()
        fakes.accessibility.trusted = false
        let engine = try makeEngine(fakes, mode: .jiggle)
        engine.start()
        XCTAssertEqual(engine.runningMode, .zen)

        fakes.accessibility.trusted = true
        engine.refreshAccessibility()
        XCTAssertEqual(engine.runningMode, .jiggle)
        XCTAssertNil(engine.warning)
        XCTAssertEqual(fakes.power.held.count, 1)
    }

    func testLinkedAutoStartStopAndManualOverride() throws {
        let fakes = Fakes()
        let settings = try makeSettings()
        let engine = JiggleEngine(settings: settings, services: fakes.services)
        addTeardownBlock { @MainActor in engine.stop() }
        let watcher = AppWatcher(settings: settings, workspace: fakes.workspace)
        let claude = LinkedApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", modeOverride: .keepAwake)
        let other = LinkedApp(bundleID: "com.openai.chat", name: "ChatGPT")
        watcher.linkedApps = [claude, other]
        watcher.autoEnabled = true
        engine.attach(to: watcher)
        XCTAssertFalse(engine.isActive)

        fakes.workspace.send(.launched(bundleID: claude.bundleID))
        XCTAssertTrue(engine.isActive)
        XCTAssertEqual(engine.activeReason, .linked)
        XCTAssertEqual(engine.runningMode, .keepAwake)  // Per-app override.

        engine.stop()  // Manual stop holds...
        fakes.workspace.send(.activated(bundleID: claude.bundleID))
        XCTAssertFalse(engine.isActive)
        fakes.workspace.send(.launched(bundleID: other.bundleID))  // ...until the next linked change.
        XCTAssertTrue(engine.isActive)

        fakes.workspace.send(.terminated(bundleID: claude.bundleID))
        fakes.workspace.send(.terminated(bundleID: other.bundleID))
        XCTAssertFalse(engine.isActive)
        XCTAssertTrue(fakes.power.held.isEmpty)
    }

    func testLinkedChangesDoNotStopManualSession() throws {
        let fakes = Fakes()
        let settings = try makeSettings()
        let engine = JiggleEngine(settings: settings, services: fakes.services)
        addTeardownBlock { @MainActor in engine.stop() }
        let watcher = AppWatcher(settings: settings, workspace: fakes.workspace)
        watcher.linkedApps = [LinkedApp(bundleID: "com.openai.chat", name: "ChatGPT")]
        watcher.autoEnabled = true
        engine.attach(to: watcher)

        engine.start(duration: 600)
        fakes.workspace.send(.launched(bundleID: "com.openai.chat"))
        fakes.workspace.send(.terminated(bundleID: "com.openai.chat"))
        XCTAssertTrue(engine.isActive)
        XCTAssertEqual(engine.activeReason, .timed)
    }
}
