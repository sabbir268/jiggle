import Foundation

/// Menu status line text. Pure, so it can be unit tested.
enum StatusText {
    /// `linkedRunning` / `rule` are only consulted when linked-app Auto is on (`autoEnabled`).
    static func line(
        isActive: Bool,
        mode: Mode?,
        reason: ActiveReason?,
        endsAt: Date?,
        autoEnabled: Bool,
        rule: LinkedRule,
        linkedRunning: [String],
        now: Date
    ) -> String {
        guard isActive, let mode else {
            guard autoEnabled else { return "Inactive" }
            if linkedRunning.isEmpty { return "Inactive — no linked app running" }
            return rule == .frontmost ? "Inactive — no linked app frontmost" : "Inactive"
        }
        if reason == .linked, !linkedRunning.isEmpty {
            return "Active — linked: " + linkedRunning.joined(separator: ", ")
        }
        var line = "Active — \(mode.title)"
        if let endsAt {
            line += " · " + remaining(endsAt.timeIntervalSince(now))
        }
        return line
    }

    static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        guard minutes >= 60 else { return "\(minutes) min left" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h left" : "\(hours) h \(rest) min left"
    }
}
