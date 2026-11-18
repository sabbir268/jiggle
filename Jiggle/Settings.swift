import CoreGraphics
import Foundation

enum Mode: String, CaseIterable, Codable, Identifiable, Sendable {
    case keepAwake, zen, jiggle, jiggleClick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepAwake: "Keep Awake"
        case .zen: "Zen"
        case .jiggle: "Jiggle"
        case .jiggleClick: "Jiggle + Click"
        }
    }

    /// Order used when several linked apps override the mode: the strongest wins.
    var strength: Int {
        switch self {
        case .keepAwake: 0
        case .zen: 1
        case .jiggle: 2
        case .jiggleClick: 3
        }
    }

    var needsAccessibility: Bool { self == .jiggle || self == .jiggleClick }
}

enum ClickButton: String, CaseIterable, Sendable {
    case left, right
}

enum ClickTarget: String, CaseIterable, Sendable {
    case pinnedPoint, currentPosition
}

enum LinkedRule: String, CaseIterable, Sendable {
    case running, frontmost
}

struct LinkedApp: Codable, Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String
    var modeOverride: Mode?

    var id: String { bundleID }
}

/// `UserDefaults` / `@AppStorage` keys.
enum SettingsKey {
    static let mode = "mode"
    static let intervalSeconds = "intervalSeconds"
    static let jitterEnabled = "jitterEnabled"
    static let jiggleDistance = "jiggleDistance"
    static let smartPause = "smartPause"
    static let clickEveryNTicks = "clickEveryNTicks"
    static let clickButton = "clickButton"
    static let clickTarget = "clickTarget"
    static let clickPoint = "clickPoint"
    static let clickBlocklist = "clickBlocklist"
    static let clickOnlyWhenLinkedFrontmost = "clickOnlyWhenLinkedFrontmost"
    static let linkedAutoEnabled = "linkedAutoEnabled"
    static let linkedRule = "linkedRule"
    static let linkedApps = "linkedApps"
    static let launchAtLogin = "launchAtLogin"
    static let hotkeyEnabled = "hotkeyEnabled"
    static let batteryGuardPercent = "batteryGuardPercent"
    static let stopOnLock = "stopOnLock"
    static let resumeOnUnlock = "resumeOnUnlock"
    static let scheduleEnabled = "scheduleEnabled"
    static let scheduleDays = "scheduleDays"
    static let scheduleStart = "scheduleStart"
    static let scheduleEnd = "scheduleEnd"
}

enum SettingsDefault {
    static let mode = Mode.zen
    static let intervalSeconds = 60
    static let intervalRange = 10...600
    static let jitterEnabled = true
    static let jitterFraction = 0.2
    static let jiggleDistance = 2
    static let jiggleDistanceRange = 1...20
    static let smartPause = true
    static let clickEveryNTicks = 5
    static let clickEveryNTicksRange = 1...20
    static let clickButton = ClickButton.left
    static let clickTarget = ClickTarget.pinnedPoint
    static let clickBlocklist = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.dt.Xcode",
        "com.apple.finder",
        "com.apple.systempreferences",
    ]
    static let clickOnlyWhenLinkedFrontmost = false
    static let linkedAutoEnabled = false
    static let linkedRule = LinkedRule.running
    static let launchAtLogin = false
    static let hotkeyEnabled = true
    static let batteryGuardPercent = 20
    static let stopOnLock = true
    static let resumeOnUnlock = false
    static let scheduleEnabled = false
    /// `Calendar` weekdays (1 = Sunday): Monday to Friday.
    static let scheduleDays = "2,3,4,5,6"
    /// Minutes after midnight.
    static let scheduleStart = 9 * 60
    static let scheduleEnd = 18 * 60

    static var registrationDictionary: [String: Any] {
        [
            SettingsKey.mode: mode.rawValue,
            SettingsKey.intervalSeconds: intervalSeconds,
            SettingsKey.jitterEnabled: jitterEnabled,
            SettingsKey.jiggleDistance: jiggleDistance,
            SettingsKey.smartPause: smartPause,
            SettingsKey.clickEveryNTicks: clickEveryNTicks,
            SettingsKey.clickButton: clickButton.rawValue,
            SettingsKey.clickTarget: clickTarget.rawValue,
            SettingsKey.clickBlocklist: ListCoding.encode(clickBlocklist),
            SettingsKey.clickOnlyWhenLinkedFrontmost: clickOnlyWhenLinkedFrontmost,
            SettingsKey.linkedAutoEnabled: linkedAutoEnabled,
            SettingsKey.linkedRule: linkedRule.rawValue,
            SettingsKey.launchAtLogin: launchAtLogin,
            SettingsKey.hotkeyEnabled: hotkeyEnabled,
            SettingsKey.batteryGuardPercent: batteryGuardPercent,
            SettingsKey.stopOnLock: stopOnLock,
            SettingsKey.resumeOnUnlock: resumeOnUnlock,
            SettingsKey.scheduleEnabled: scheduleEnabled,
            SettingsKey.scheduleDays: scheduleDays,
            SettingsKey.scheduleStart: scheduleStart,
            SettingsKey.scheduleEnd: scheduleEnd,
        ]
    }
}

/// Newline-separated string lists (the click blocklist), so they fit in `@AppStorage`.
enum ListCoding {
    static func encode(_ items: [String]) -> String { items.joined(separator: "\n") }

    static func decode(_ string: String) -> [String] {
        string.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// `CGPoint` stored as `"x,y"`.
enum PointCoding {
    static func encode(_ point: CGPoint) -> String { "\(point.x),\(point.y)" }

    static func decode(_ string: String?) -> CGPoint? {
        guard let parts = string?.split(separator: ","), parts.count == 2,
              let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }
}

/// Typed, clamped access to settings for non-view code. Views use `@AppStorage` with the same keys.
struct SettingsStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: SettingsDefault.registrationDictionary)
    }

    var mode: Mode {
        get { defaults.string(forKey: SettingsKey.mode).flatMap(Mode.init(rawValue:)) ?? SettingsDefault.mode }
        nonmutating set { defaults.set(newValue.rawValue, forKey: SettingsKey.mode) }
    }

    var intervalSeconds: Int { clamped(SettingsKey.intervalSeconds, SettingsDefault.intervalRange) }
    var jitterEnabled: Bool { defaults.bool(forKey: SettingsKey.jitterEnabled) }
    var jiggleDistance: Int { clamped(SettingsKey.jiggleDistance, SettingsDefault.jiggleDistanceRange) }
    var smartPause: Bool { defaults.bool(forKey: SettingsKey.smartPause) }
    var clickEveryNTicks: Int { clamped(SettingsKey.clickEveryNTicks, SettingsDefault.clickEveryNTicksRange) }

    var clickButton: ClickButton {
        defaults.string(forKey: SettingsKey.clickButton).flatMap(ClickButton.init(rawValue:))
            ?? SettingsDefault.clickButton
    }

    var clickTarget: ClickTarget {
        defaults.string(forKey: SettingsKey.clickTarget).flatMap(ClickTarget.init(rawValue:))
            ?? SettingsDefault.clickTarget
    }

    var clickPoint: CGPoint? {
        get { PointCoding.decode(defaults.string(forKey: SettingsKey.clickPoint)) }
        nonmutating set { defaults.set(newValue.map(PointCoding.encode), forKey: SettingsKey.clickPoint) }
    }

    var clickBlocklist: [String] { ListCoding.decode(defaults.string(forKey: SettingsKey.clickBlocklist) ?? "") }
    var clickOnlyWhenLinkedFrontmost: Bool { defaults.bool(forKey: SettingsKey.clickOnlyWhenLinkedFrontmost) }
    var linkedAutoEnabled: Bool { defaults.bool(forKey: SettingsKey.linkedAutoEnabled) }

    var linkedRule: LinkedRule {
        defaults.string(forKey: SettingsKey.linkedRule).flatMap(LinkedRule.init(rawValue:))
            ?? SettingsDefault.linkedRule
    }

    var linkedApps: [LinkedApp] {
        get {
            guard let data = defaults.data(forKey: SettingsKey.linkedApps) else { return [] }
            return (try? JSONDecoder().decode([LinkedApp].self, from: data)) ?? []
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: SettingsKey.linkedApps)
        }
    }

    private func clamped(_ key: String, _ range: ClosedRange<Int>) -> Int {
        min(max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }
}
