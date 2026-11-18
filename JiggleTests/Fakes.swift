import AppKit
import IOKit.pwr_mgt
import XCTest
@testable import Jiggle

@MainActor
final class FakePower: PowerAssertionProviding {
    private var nextID: IOPMAssertionID = 100
    private(set) var held: Set<IOPMAssertionID> = []
    private(set) var declarations = 0

    func createDisplaySleepAssertion(reason: String) -> IOPMAssertionID? {
        nextID += 1
        held.insert(nextID)
        return nextID
    }

    func declareUserActivity(name: String, existing: IOPMAssertionID?) -> IOPMAssertionID? {
        declarations += 1
        if let existing { return existing }
        nextID += 1
        held.insert(nextID)
        return nextID
    }

    func release(_ id: IOPMAssertionID) {
        held.remove(id)
    }
}

@MainActor
final class FakeIdle: IdleTimeProviding {
    var seconds: TimeInterval = 1_000
    func secondsSinceLastInput() -> TimeInterval { seconds }
}

@MainActor
final class FakeCursor: CursorLocating {
    var location = CGPoint(x: 500, y: 300)
    func currentLocation() -> CGPoint { location }
}

@MainActor
final class FakeEvents: MouseEventPosting {
    enum Event: Equatable {
        case move(CGPoint)
        case button(ClickButton, down: Bool, CGPoint)
    }

    private(set) var events: [Event] = []

    func moveMouse(to point: CGPoint) { events.append(.move(point)) }

    func postMouseButton(_ button: ClickButton, down: Bool, at point: CGPoint) {
        events.append(.button(button, down: down, point))
    }
}

@MainActor
final class FakeAccessibility: AccessibilityChecking {
    var trusted = true
    func isTrusted() -> Bool { trusted }
}

@MainActor
final class FakeModifiers: ModifierFlagsProviding {
    var flags: CGEventFlags = []
    func currentFlags() -> CGEventFlags { flags }
}

@MainActor
final class FakeWorkspace: WorkspaceProviding {
    var running: Set<String> = []
    var frontmost: String?
    var regularApps: [RunningApp] = []
    private var handler: (@MainActor @Sendable (WorkspaceEvent) -> Void)?

    func runningBundleIDs() -> Set<String> { running }
    func frontmostBundleID() -> String? { frontmost }
    func runningRegularApps() -> [RunningApp] { regularApps }
    func icon(forBundleID bundleID: String) -> NSImage? { nil }
    func activate(bundleID: String) {}

    func observe(_ handler: @escaping @MainActor @Sendable (WorkspaceEvent) -> Void) -> [any NSObjectProtocol] {
        self.handler = handler
        return []
    }

    /// Updates the fake system state and delivers the event like NSWorkspace would.
    func send(_ event: WorkspaceEvent) {
        switch event {
        case .launched(let id): running.insert(id)
        case .terminated(let id): running.remove(id)
        case .activated(let id): frontmost = id
        }
        handler?(event)
    }
}

@MainActor
struct Fakes {
    let power = FakePower()
    let idle = FakeIdle()
    let cursor = FakeCursor()
    let events = FakeEvents()
    let accessibility = FakeAccessibility()
    let modifiers = FakeModifiers()
    let workspace = FakeWorkspace()

    var services: SystemServices {
        SystemServices(
            power: power, idle: idle, cursor: cursor, events: events,
            accessibility: accessibility, modifiers: modifiers, workspace: workspace
        )
    }
}

extension XCTestCase {
    /// Settings backed by a throwaway `UserDefaults` suite.
    func makeSettings() throws -> SettingsStore {
        let name = "JiggleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return SettingsStore(defaults: defaults)
    }

    /// Lets main-queue work scheduled with `asyncAfter` run.
    func waitForMainQueue(seconds: TimeInterval) {
        let done = expectation(description: "main queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }
}
