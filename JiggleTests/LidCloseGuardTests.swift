import XCTest
@testable import Jiggle

@MainActor
final class LidCloseGuardTests: XCTestCase {
    private func make(
        _ lid: FakeLidSleep, enabled: Bool = true, settings existing: SettingsStore? = nil
    ) throws -> (LidCloseGuard, JiggleEngine, SettingsStore) {
        let settings = try existing ?? makeSettings()
        settings.defaults.set(enabled, forKey: SettingsKey.keepRunningLidClosed)
        let engine = JiggleEngine(settings: settings, services: Fakes().services)
        addTeardownBlock { @MainActor in engine.stop() }
        return (LidCloseGuard(engine: engine, settings: settings, control: lid), engine, settings)
    }

    func testDisablesSleepOnlyWhileSessionRuns() throws {
        let lid = FakeLidSleep()
        let (guardian, engine, settings) = try make(lid)
        guardian.update()
        XCTAssertFalse(lid.sleepDisabled)

        engine.start()
        guardian.update()
        XCTAssertTrue(lid.sleepDisabled)
        XCTAssertTrue(guardian.isEngaged)
        XCTAssertTrue(settings.lidSleepDisabledByJiggle)

        engine.stop()
        guardian.update()
        XCTAssertFalse(lid.sleepDisabled)
        XCTAssertFalse(guardian.isEngaged)
        XCTAssertFalse(settings.lidSleepDisabledByJiggle)
    }

    func testTurningOptionOffRestoresSleep() throws {
        let lid = FakeLidSleep()
        let (guardian, engine, settings) = try make(lid)
        engine.start()
        guardian.update()
        settings.defaults.set(false, forKey: SettingsKey.keepRunningLidClosed)
        guardian.update()
        XCTAssertFalse(lid.sleepDisabled)
    }

    func testDoesNothingWhenOffOrNotSetUp() throws {
        let off = FakeLidSleep()
        let (offGuard, offEngine, _) = try make(off, enabled: false)
        offEngine.start()
        offGuard.update()
        XCTAssertTrue(off.changes.isEmpty)

        let notSetUp = FakeLidSleep()
        notSetUp.isSetUp = false
        let (guardian, engine, _) = try make(notSetUp)
        engine.start()
        guardian.update()
        XCTAssertTrue(notSetUp.changes.isEmpty)
    }

    func testRestoresLeftoverChangeAfterCrash() throws {
        let settings = try makeSettings()
        settings.lidSleepDisabledByJiggle = true
        let lid = FakeLidSleep()
        lid.sleepDisabled = true
        _ = try make(lid, settings: settings)
        XCTAssertEqual(lid.changes, [false])
        XCTAssertFalse(lid.sleepDisabled)
        XCTAssertFalse(settings.lidSleepDisabledByJiggle)
    }

    func testNeverTouchesSleepTheUserDisabled() throws {
        let lid = FakeLidSleep()
        lid.sleepDisabled = true  // Set by the user, not by Jiggle.
        let (guardian, _, _) = try make(lid, enabled: false)
        guardian.update()
        XCTAssertTrue(lid.changes.isEmpty)
        XCTAssertTrue(lid.sleepDisabled)
    }

    func testFailedRestoreKeepsMarkerForNextLaunch() throws {
        let lid = FakeLidSleep()
        let (guardian, engine, settings) = try make(lid)
        engine.start()
        guardian.update()
        lid.failChanges = true
        engine.stop()
        guardian.update()
        XCTAssertTrue(settings.lidSleepDisabledByJiggle)
        XCTAssertNotNil(guardian.errorMessage)
    }
}
