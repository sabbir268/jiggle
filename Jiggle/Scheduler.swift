import Foundation

enum ScheduleWindow {
    /// True when `date` is inside the weekly window. `start`/`end` are minutes after midnight; a window
    /// whose end is before its start runs overnight and belongs to the day it starts on.
    static func contains(_ date: Date, days: Set<Int>, start: Int, end: Int, calendar: Calendar = .current) -> Bool {
        guard start != end else { return false }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        let now = hour * 60 + minute
        if start < end {
            return days.contains(weekday) && now >= start && now < end
        }
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return (days.contains(weekday) && now >= start) || (days.contains(previousDay) && now < end)
    }
}

/// Checks the schedule once a minute (only while it is enabled). Acts on window edges, so a manual
/// Stop inside the window holds until the next window, and only schedule-started sessions are stopped.
@MainActor
final class Scheduler {
    private let engine: JiggleEngine
    private let settings: SettingsStore
    private var timer: DispatchSourceTimer?
    private var wasInside: Bool?

    init(engine: JiggleEngine, settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
    }

    /// Call whenever settings change.
    func apply() {
        guard settings.scheduleEnabled else {
            timer?.cancel()
            timer = nil
            wasInside = nil
            if engine.activeReason == .schedule { engine.stop() }
            return
        }
        if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.check() }
            }
            timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
            timer.resume()
            self.timer = timer
        }
        check()
    }

    private func check() {
        let inside = ScheduleWindow.contains(
            Date(), days: settings.scheduleDays, start: settings.scheduleStart, end: settings.scheduleEnd
        )
        defer { wasInside = inside }
        guard inside != wasInside else { return }
        if inside {
            if !engine.isActive { engine.start(reason: .schedule) }
        } else if engine.activeReason == .schedule {
            engine.stop()
        }
    }
}
