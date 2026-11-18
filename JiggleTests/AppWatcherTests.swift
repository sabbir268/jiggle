import XCTest
@testable import Jiggle

private let claude = LinkedApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
private let chatGPT = LinkedApp(bundleID: "com.openai.chat", name: "ChatGPT", modeOverride: .keepAwake)
private let whatsApp = LinkedApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", modeOverride: .jiggle)

final class AppWatcherEvaluationTests: XCTestCase {
    func testRunningRule() {
        let none = AppWatcher.evaluate(linkedApps: [claude], runningIDs: ["com.apple.finder"], frontmostID: nil, rule: .running)
        XCTAssertFalse(none.shouldBeActive)
        let some = AppWatcher.evaluate(
            linkedApps: [claude], runningIDs: [claude.bundleID], frontmostID: "com.apple.finder", rule: .running
        )
        XCTAssertTrue(some.shouldBeActive)
        XCTAssertFalse(some.frontmostIsLinked)
        XCTAssertEqual(some.runningLinked, [claude])
    }

    func testFrontmostRule() {
        let background = AppWatcher.evaluate(
            linkedApps: [claude], runningIDs: [claude.bundleID], frontmostID: "com.apple.finder", rule: .frontmost
        )
        XCTAssertFalse(background.shouldBeActive)
        let front = AppWatcher.evaluate(
            linkedApps: [claude], runningIDs: [claude.bundleID], frontmostID: claude.bundleID, rule: .frontmost
        )
        XCTAssertTrue(front.shouldBeActive)
    }

    func testEffectiveModeIsStrongestRunningOverride() {
        let all = [claude, chatGPT, whatsApp]
        XCTAssertNil(AppWatcher.evaluate(linkedApps: all, runningIDs: [claude.bundleID], frontmostID: nil, rule: .running).effectiveMode)
        XCTAssertEqual(
            AppWatcher.evaluate(linkedApps: all, runningIDs: [claude.bundleID, chatGPT.bundleID], frontmostID: nil, rule: .running)
                .effectiveMode,
            .keepAwake
        )
        XCTAssertEqual(
            AppWatcher.evaluate(linkedApps: all, runningIDs: Set(all.map(\.bundleID)), frontmostID: nil, rule: .running)
                .effectiveMode,
            .jiggle
        )
    }
}

@MainActor
final class AppWatcherTests: XCTestCase {
    private func makeWatcher(_ workspace: FakeWorkspace, apps: [LinkedApp], rule: LinkedRule) throws -> AppWatcher {
        let watcher = AppWatcher(settings: try makeSettings(), workspace: workspace)
        watcher.linkedApps = apps
        watcher.rule = rule
        return watcher
    }

    func testRunningRuleFollowsLaunchAndTerminate() throws {
        let workspace = FakeWorkspace()
        let watcher = try makeWatcher(workspace, apps: [claude, whatsApp], rule: .running)
        XCTAssertFalse(watcher.shouldBeActive)

        workspace.send(.launched(bundleID: claude.bundleID))
        XCTAssertTrue(watcher.shouldBeActive)
        XCTAssertNil(watcher.effectiveMode)

        workspace.send(.launched(bundleID: whatsApp.bundleID))
        XCTAssertEqual(watcher.effectiveMode, .jiggle)
        XCTAssertEqual(watcher.runningLinked.map(\.name), ["Claude", "WhatsApp"])

        workspace.send(.terminated(bundleID: claude.bundleID))
        workspace.send(.terminated(bundleID: whatsApp.bundleID))
        XCTAssertFalse(watcher.shouldBeActive)
        XCTAssertNil(watcher.effectiveMode)
    }

    func testFrontmostRuleFollowsActivation() throws {
        let workspace = FakeWorkspace()
        workspace.running = [claude.bundleID]
        let watcher = try makeWatcher(workspace, apps: [claude], rule: .frontmost)
        XCTAssertFalse(watcher.shouldBeActive)

        workspace.send(.activated(bundleID: claude.bundleID))
        XCTAssertTrue(watcher.frontmostIsLinked)
        XCTAssertTrue(watcher.shouldBeActive)

        workspace.send(.activated(bundleID: "com.apple.Safari"))
        XCTAssertFalse(watcher.shouldBeActive)
    }

    func testSeedsFromRunningApps() throws {
        let workspace = FakeWorkspace()
        workspace.running = [claude.bundleID]
        let settings = try makeSettings()
        settings.linkedApps = [claude]
        let watcher = AppWatcher(settings: settings, workspace: workspace)
        XCTAssertTrue(watcher.shouldBeActive)
    }

    func testLinkedAppsPersist() throws {
        let settings = try makeSettings()
        let watcher = AppWatcher(settings: settings, workspace: FakeWorkspace())
        watcher.link(RunningApp(bundleID: claude.bundleID, name: "Claude"))
        watcher.linkedApps[0].modeOverride = .zen
        XCTAssertEqual(settings.linkedApps, [LinkedApp(bundleID: claude.bundleID, name: "Claude", modeOverride: .zen)])
    }
}
