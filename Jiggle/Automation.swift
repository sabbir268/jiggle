import Combine
import Foundation

/// Wires the M3 extras (hotkey, schedule, power, notifications) to the engine and re-applies settings
/// whenever `UserDefaults` changes. No polling here; the scheduler owns the only 1-minute timer.
@MainActor
final class Automation: ObservableObject {
    let hotKey: HotKey
    let loginItem = LoginItem()

    private let engine: JiggleEngine
    private let settings: SettingsStore
    private let scheduler: Scheduler
    private let power: PowerMonitor
    private let notifier = SessionNotifier()
    private var cancellables: Set<AnyCancellable> = []
    private var defaultsObserver: (any NSObjectProtocol)?
    private var accessibilityObserver: (any NSObjectProtocol)?

    init(engine: JiggleEngine, settings: SettingsStore = SettingsStore(), startServices: Bool = true) {
        self.engine = engine
        self.settings = settings
        hotKey = HotKey { [weak engine] in engine?.toggle() }
        scheduler = Scheduler(engine: engine, settings: settings)
        power = PowerMonitor(engine: engine, settings: settings)

        let notifier = notifier
        engine.onTimedSessionEnded = {
            if settings.notifyOnSessionEnd { notifier.sessionEnded() }
        }
        engine.$endsAt
            .compactMap { $0 }
            .sink { _ in
                MainActor.assumeIsolated {
                    if settings.notifyOnSessionEnd { notifier.requestAuthorizationIfNeeded() }
                }
            }
            .store(in: &cancellables)
        // @Published emits before the value is stored, so check the battery on the next run-loop turn.
        engine.$isActive
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.power.checkBattery() }
            }
            .store(in: &cancellables)

        guard startServices else { return }
        power.start()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        // Posted by macOS whenever the Accessibility list changes. The new trust value can lag the
        // notification slightly, so re-check shortly after and once more a bit later.
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleAccessibilityRefresh() }
        }
        apply()
    }

    private func scheduleAccessibilityRefresh() {
        for delay in [0.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.engine.refreshAccessibility() }
            }
        }
    }

    private func apply() {
        hotKey.setEnabled(settings.hotkeyEnabled)
        scheduler.apply()
        power.checkBattery()
    }
}
