import Foundation

/// Menu status line text. Pure, so it can be unit tested.
enum StatusText {
    static func line(isActive: Bool, mode: Mode?, endsAt: Date?, now: Date) -> String {
        guard isActive, let mode else { return "Inactive" }
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
