import AppKit
import IOKit.ps

struct BatteryStatus: Equatable, Sendable {
    var onBattery: Bool
    var percent: Int
}

enum BatteryGuard {
    /// Stop when running on battery below `threshold` percent. A threshold of 0 turns the guard off.
    static func shouldStop(_ status: BatteryStatus?, threshold: Int) -> Bool {
        guard let status, threshold > 0 else { return false }
        return status.onBattery && status.percent < threshold
    }
}

enum PowerSource {
    /// Internal battery status, or nil on Macs without one.
    static func current() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                let maxCapacity = description[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0
            else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return BatteryStatus(onBattery: onBattery, percent: capacity * 100 / maxCapacity)
        }
        return nil
    }
}

/// Battery guard (IOKit power-source notifications) and stop-on-lock/sleep with optional resume.
@MainActor
final class PowerMonitor {
    private let engine: JiggleEngine
    private let settings: SettingsStore
    private var runLoopSource: CFRunLoopSource?
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    /// True while lid-closed mode keeps the Mac awake: then lock and display sleep must not stop the session.
    var ignoresLockAndSleep: () -> Bool = { false }
    /// The session stopped by lock/sleep, for resume on unlock.
    private var suspended: (reason: ActiveReason, endsAt: Date?)?

    init(engine: JiggleEngine, settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
    }

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.checkBattery() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.suspendForLockOrSleep() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.suspendForLockOrSleep() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.resumeIfUnlocked() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.suspendForLockOrSleep() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.resume() }
    }

    func checkBattery() {
        guard engine.isActive else { return }
        let threshold = settings.batteryGuardPercent
        guard BatteryGuard.shouldStop(PowerSource.current(), threshold: threshold) else { return }
        engine.stop()
        engine.warning = "Stopped: on battery below \(threshold)%."
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @MainActor @Sendable (PowerMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        }
        observers.append((center, token))
    }

    private func suspendForLockOrSleep() {
        guard settings.stopOnLock, engine.isActive, !ignoresLockAndSleep() else { return }
        suspended = (engine.activeReason ?? .manual, engine.endsAt)
        engine.stop()
    }

    /// Screens can wake while still locked; only resume if the session is not locked.
    private func resumeIfUnlocked() {
        guard !Self.isScreenLocked() else { return }
        resume()
    }

    private func resume() {
        guard let suspended else { return }
        self.suspended = nil
        guard settings.resumeOnUnlock,
              !BatteryGuard.shouldStop(PowerSource.current(), threshold: settings.batteryGuardPercent)
        else { return }
        engine.resume(reason: suspended.reason, endsAt: suspended.endsAt)
    }

    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
