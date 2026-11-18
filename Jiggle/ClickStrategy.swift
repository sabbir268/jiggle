import CoreGraphics
import Foundation

enum ClickSkipReason: String, Sendable {
    case notNthTick, modifierHeld, userActive, blocklisted, linkedNotFrontmost, noPinnedPoint
}

struct ClickContext: Sendable {
    var tickCount: Int
    var everyNTicks: Int
    var modifierFlags: CGEventFlags
    var userActive: Bool
    var frontmostBundleID: String?
    var blocklist: [String]
    var onlyWhenLinkedFrontmost: Bool
    var frontmostIsLinked: Bool
    var target: ClickTarget
    var pinnedPoint: CGPoint?
}

enum ClickDecision {
    static let blockingModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    /// nil means click; otherwise the reason to skip the click (the jiggle still happens).
    static func evaluate(_ context: ClickContext) -> ClickSkipReason? {
        let n = max(1, context.everyNTicks)
        if context.tickCount % n != 0 { return .notNthTick }
        if !context.modifierFlags.intersection(blockingModifiers).isEmpty { return .modifierHeld }
        if context.userActive { return .userActive }
        if let front = context.frontmostBundleID, context.blocklist.contains(front) { return .blocklisted }
        if context.onlyWhenLinkedFrontmost, !context.frontmostIsLinked { return .linkedNotFrontmost }
        if context.target == .pinnedPoint, context.pinnedPoint == nil { return .noPinnedPoint }
        return nil
    }
}

/// Jiggle, plus a single click every Nth tick when every safety check passes.
@MainActor
final class JiggleClickStrategy: ActivityStrategy {
    /// Click after the jiggle's 50 ms restore move has happened.
    static let clickDelay: DispatchTimeInterval = .milliseconds(150)
    static let buttonHold: DispatchTimeInterval = .milliseconds(40)

    private let jiggle: JiggleStrategy
    private let services: SystemServices
    private let settings: SettingsStore
    private var tickCount = 0
    private var lastTickAt: Date?
    private var isRunning = false
    private(set) var lastSkipReason: ClickSkipReason?

    init(services: SystemServices, settings: SettingsStore) {
        self.services = services
        self.settings = settings
        jiggle = JiggleStrategy(services: services) { settings.jiggleDistance }
    }

    func start() {
        isRunning = true
        tickCount = 0
        lastTickAt = nil
        jiggle.start()
    }

    func tick() {
        let now = Date()
        tickCount += 1
        // Read idle time before this tick's own jiggle, which would otherwise look like user input.
        let decision = ClickDecision.evaluate(context(now: now))
        lastSkipReason = decision
        jiggle.tick()
        lastTickAt = now
        guard decision == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickDelay) { [weak self] in
            MainActor.assumeIsolated { self?.click() }
        }
    }

    func stop() {
        isRunning = false
        jiggle.stop()
    }

    private func context(now: Date) -> ClickContext {
        let frontmost = services.workspace.frontmostBundleID()
        let linkedIDs = Set(settings.linkedApps.map(\.bundleID))
        return ClickContext(
            tickCount: tickCount,
            everyNTicks: settings.clickEveryNTicks,
            modifierFlags: services.modifiers.currentFlags(),
            userActive: SmartPause.shouldSkipTick(
                idleSeconds: services.idle.secondsSinceLastInput(),
                interval: TimeInterval(settings.intervalSeconds),
                secondsSinceOwnActivity: lastTickAt.map { now.timeIntervalSince($0) }
            ),
            frontmostBundleID: frontmost,
            blocklist: settings.clickBlocklist,
            onlyWhenLinkedFrontmost: settings.clickOnlyWhenLinkedFrontmost,
            frontmostIsLinked: frontmost.map(linkedIDs.contains) ?? false,
            target: settings.clickTarget,
            pinnedPoint: settings.clickPoint
        )
    }

    private func click() {
        guard isRunning else { return }
        // Re-check modifiers: the user may have pressed one during the short delay.
        guard services.modifiers.currentFlags().intersection(ClickDecision.blockingModifiers).isEmpty else { return }
        let saved = services.cursor.currentLocation()
        let target = settings.clickTarget == .pinnedPoint ? settings.clickPoint : saved
        guard let point = target else { return }
        let button = settings.clickButton
        let events = services.events
        events.postMouseButton(button, down: true, at: point)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.buttonHold) {
            MainActor.assumeIsolated {
                events.postMouseButton(button, down: false, at: point)
                events.moveMouse(to: saved)
            }
        }
    }
}

/// "Set click point…": a 3-second countdown (shown in the menu bar), then the cursor position is stored.
@MainActor
final class ClickPointCapture: ObservableObject {
    @Published private(set) var countdown: Int?

    private let settings: SettingsStore
    private let cursor: any CursorLocating

    init(settings: SettingsStore = SettingsStore(), cursor: any CursorLocating = SystemCursor()) {
        self.settings = settings
        self.cursor = cursor
    }

    func capturePoint() {
        guard countdown == nil else { return }
        Task {
            for remaining in stride(from: 3, through: 1, by: -1) {
                countdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            settings.clickPoint = cursor.currentLocation()
            countdown = nil
        }
    }
}
