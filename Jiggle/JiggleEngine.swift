import AppKit
import Combine
import Foundation

enum ActiveReason: String, Sendable {
    case manual, timed, linked, schedule
}

@MainActor
final class JiggleEngine: ObservableObject {
    @Published private(set) var isActive = false
    @Published var mode: Mode {
        didSet { modeDidChange(from: oldValue) }
    }
    /// The mode actually running: `mode` (or a linked app's override), or Zen while Accessibility is missing.
    @Published private(set) var runningMode: Mode?
    @Published private(set) var endsAt: Date?
    @Published private(set) var activeReason: ActiveReason?
    @Published var warning: String?

    /// Called when a Jiggle mode is chosen or started without Accessibility permission (shows the explainer).
    var onAccessibilityNeeded: (() -> Void)?
    /// Called when a timed session reaches its end time on its own.
    var onTimedSessionEnded: (() -> Void)?

    private let settings: SettingsStore
    private let services: SystemServices
    private let now: () -> Date
    private var strategy: (any ActivityStrategy)?
    private var timer: DispatchSourceTimer?
    private var lastOwnActivityAt: Date?
    private var terminateObserver: (any NSObjectProtocol)?
    private var linkedSubscription: AnyCancellable?
    /// Strongest per-app override among running linked apps; applies only to linked sessions.
    private var linkedModeOverride: Mode?
    private var lastLinkedState: LinkedState?

    /// The mode this session wants before the Accessibility check.
    private var desiredMode: Mode {
        activeReason == .linked ? (linkedModeOverride ?? mode) : mode
    }

    init(
        settings: SettingsStore = SettingsStore(),
        services: SystemServices = .live,
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.services = services
        self.now = now
        mode = settings.mode
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    // MARK: - Control

    /// Starts (or extends) a session. `duration` nil means indefinitely.
    func start(duration: TimeInterval? = nil, reason: ActiveReason = .manual) {
        start(endsAt: TickScheduling.endsAt(duration: duration, from: now()), reason: reason)
    }

    /// Starts a session that ends at `date`.
    func start(until date: Date, reason: ActiveReason = .timed) {
        start(endsAt: date, reason: reason)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        strategy?.stop()
        strategy = nil
        lastOwnActivityAt = nil
        linkedModeOverride = nil
        runningMode = nil
        isActive = false
        endsAt = nil
        activeReason = nil
    }

    func toggle() {
        isActive ? stop() : start()
    }

    /// Re-arms the pending tick after the interval setting changes, so a shorter interval applies right away.
    func intervalDidChange() {
        guard isActive else { return }
        scheduleNextTick()
    }

    // MARK: - Linked apps

    /// Follows the watcher: start when a linked app becomes active, stop when none is.
    /// A manual Start/Stop sticks until the watcher's state changes again.
    func attach(to watcher: AppWatcher) {
        linkedSubscription = watcher.$state
            .removeDuplicates()
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.linkedStateChanged(state) }
            }
    }

    /// Restarts a session that was stopped by lock/sleep, if it is still meaningful.
    func resume(reason: ActiveReason, endsAt: Date?) {
        guard !isActive else { return }
        if let endsAt, endsAt.timeIntervalSince(now()) <= 0 { return }  // Not `Date <=` (see TickScheduling).
        if reason == .linked {
            if let lastLinkedState { linkedStateChanged(lastLinkedState) }
        } else {
            start(endsAt: endsAt, reason: reason)
        }
    }

    private func linkedStateChanged(_ state: LinkedState) {
        lastLinkedState = state
        guard state.autoEnabled else {
            if activeReason == .linked { stop() }
            return
        }
        if state.shouldBeActive {
            linkedModeOverride = state.effectiveMode
            if !isActive {
                start(endsAt: nil, reason: .linked)
            } else if activeReason == .linked {
                run(resolvedMode(promptIfNeeded: false))
            }
        } else if activeReason == .linked {
            stop()
        }
    }

    // MARK: - Internals

    /// Starts (or updates) a session ending at `endsAt` (nil: indefinitely).
    func start(endsAt: Date?, reason: ActiveReason) {
        self.endsAt = endsAt
        activeReason = (endsAt != nil && reason == .manual) ? .timed : reason
        isActive = true
        // Automatic starts (linked, schedule) never pop up the permission explainer; the menu warning is enough.
        run(resolvedMode(promptIfNeeded: reason == .manual || reason == .timed))
        scheduleNextTick()
    }

    private func modeDidChange(from oldValue: Mode) {
        guard mode != oldValue else { return }
        settings.mode = mode
        if activeReason == .linked, linkedModeOverride != nil { return }  // An app override wins.
        let resolved = resolvedMode(promptIfNeeded: true)
        if isActive { run(resolved) }
    }

    /// `desiredMode`, or Zen when it needs Accessibility and that is missing. Updates `warning`.
    private func resolvedMode(promptIfNeeded: Bool) -> Mode {
        let wanted = desiredMode
        guard wanted.needsAccessibility, !services.accessibility.isTrusted() else {
            warning = nil
            return wanted
        }
        if warning == nil, promptIfNeeded { onAccessibilityNeeded?() }
        warning = "\(wanted.title) needs Accessibility permission. Running Zen instead."
        return .zen
    }

    /// Switches to `newMode`'s strategy if it differs from the one running.
    private func run(_ newMode: Mode) {
        guard newMode != runningMode || strategy == nil else { return }
        strategy?.stop()
        let strategy = makeStrategy(for: newMode)
        strategy.start()
        self.strategy = strategy
        runningMode = newMode
        lastOwnActivityAt = nil
    }

    private func makeStrategy(for mode: Mode) -> any ActivityStrategy {
        let settings = settings
        switch mode {
        case .keepAwake:
            return KeepAwakeStrategy(power: services.power)
        case .zen:
            return ZenStrategy(power: services.power)
        case .jiggle:
            return JiggleStrategy(services: services) { settings.jiggleDistance }
        case .jiggleClick:
            return JiggleClickStrategy(services: services, settings: settings)
        }
    }

    private func scheduleNextTick() {
        let timer = timer ?? makeTimer()
        let interval = TickScheduling.jittered(
            base: TimeInterval(settings.intervalSeconds),
            enabled: settings.jitterEnabled
        )
        let delay = TickScheduling.nextDelay(jitteredInterval: interval, endsAt: endsAt, now: now())
        timer.schedule(deadline: .now() + delay, repeating: .never, leeway: .milliseconds(500))
    }

    private func makeTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleTick() }
        }
        timer.resume()
        self.timer = timer
        return timer
    }

    private func handleTick() {
        guard isActive else { return }
        let current = now()
        if TickScheduling.hasEnded(endsAt: endsAt, now: current) {
            let wasTimed = activeReason == .timed
            stop()
            if wasTimed { onTimedSessionEnded?() }
            return
        }
        // Upgrade once Accessibility is granted, or fall back if it is revoked.
        run(resolvedMode(promptIfNeeded: false))
        let skip = settings.smartPause && SmartPause.shouldSkipTick(
            idleSeconds: services.idle.secondsSinceLastInput(),
            interval: TimeInterval(settings.intervalSeconds),
            secondsSinceOwnActivity: lastOwnActivityAt.map { current.timeIntervalSince($0) }
        )
        if !skip {
            strategy?.tick()
            lastOwnActivityAt = current
        }
        scheduleNextTick()
    }
}
