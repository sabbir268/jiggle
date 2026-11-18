import AppKit
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
    @Published private(set) var endsAt: Date?
    @Published private(set) var activeReason: ActiveReason?
    @Published var warning: String?

    private let settings: SettingsStore
    private let services: SystemServices
    private let now: () -> Date
    private var strategy: (any ActivityStrategy)?
    private var timer: DispatchSourceTimer?
    private var lastOwnActivityAt: Date?
    private var terminateObserver: (any NSObjectProtocol)?

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
        isActive = false
        endsAt = nil
        activeReason = nil
    }

    func toggle() {
        isActive ? stop() : start()
    }

    // MARK: - Internals

    private func start(endsAt: Date?, reason: ActiveReason) {
        if !isActive {
            let strategy = makeStrategy(for: mode)
            strategy.start()
            self.strategy = strategy
            isActive = true
        }
        self.endsAt = endsAt
        activeReason = (endsAt != nil && reason == .manual) ? .timed : reason
        scheduleNextTick()
    }

    private func modeDidChange(from oldValue: Mode) {
        guard mode != oldValue else { return }
        settings.mode = mode
        guard isActive else { return }
        strategy?.stop()
        let strategy = makeStrategy(for: mode)
        strategy.start()
        self.strategy = strategy
        lastOwnActivityAt = nil
    }

    private func makeStrategy(for mode: Mode) -> any ActivityStrategy {
        let settings = settings
        switch mode {
        case .keepAwake:
            return KeepAwakeStrategy(power: services.power)
        case .zen:
            return ZenStrategy(power: services.power)
        case .jiggle, .jiggleClick:
            // Jiggle + Click uses plain Jiggle until JiggleClickStrategy lands (M2.5).
            return JiggleStrategy(services: services) { settings.jiggleDistance }
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
            stop()
            return
        }
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
