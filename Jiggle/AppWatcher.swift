import AppKit
import Combine

/// What the engine reacts to. Only published when it actually changes.
struct LinkedState: Equatable, Sendable {
    var autoEnabled: Bool
    var shouldBeActive: Bool
    var effectiveMode: Mode?
    var runningLinkedIDs: [String]
}

struct LinkedEvaluation: Equatable, Sendable {
    var runningLinked: [LinkedApp]
    var frontmostIsLinked: Bool
    var shouldBeActive: Bool
    var effectiveMode: Mode?
}

/// Tracks which linked apps are running / frontmost. Notification-driven, no polling.
@MainActor
final class AppWatcher: ObservableObject {
    @Published var linkedApps: [LinkedApp] {
        didSet { settings.linkedApps = linkedApps; recompute() }
    }
    @Published var rule: LinkedRule {
        didSet { settings.defaults.set(rule.rawValue, forKey: SettingsKey.linkedRule); recompute() }
    }
    @Published var autoEnabled: Bool {
        didSet { settings.defaults.set(autoEnabled, forKey: SettingsKey.linkedAutoEnabled); recompute() }
    }

    @Published private(set) var runningLinked: [LinkedApp] = []
    @Published private(set) var frontmostIsLinked = false
    @Published private(set) var shouldBeActive = false
    @Published private(set) var effectiveMode: Mode?
    /// Running regular apps that are not linked yet, for the "+" menu.
    @Published private(set) var addableApps: [RunningApp] = []
    @Published private(set) var state: LinkedState

    private let settings: SettingsStore
    private let workspace: any WorkspaceProviding
    private var runningIDs: Set<String>
    private var frontmostID: String?
    private var observers: [any NSObjectProtocol] = []

    init(settings: SettingsStore = SettingsStore(), workspace: any WorkspaceProviding = LiveWorkspace()) {
        self.settings = settings
        self.workspace = workspace
        linkedApps = settings.linkedApps
        rule = settings.linkedRule
        autoEnabled = settings.linkedAutoEnabled
        runningIDs = workspace.runningBundleIDs()
        frontmostID = workspace.frontmostBundleID()
        state = LinkedState(autoEnabled: false, shouldBeActive: false, effectiveMode: nil, runningLinkedIDs: [])
        recompute()
        refreshAddableApps()
        observers = workspace.observe { [weak self] event in self?.handle(event) }
    }

    // MARK: - Linking

    func link(_ app: RunningApp) {
        guard !linkedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        linkedApps.append(LinkedApp(bundleID: app.bundleID, name: app.name, modeOverride: nil))
        refreshAddableApps()
    }

    func unlink(bundleID: String) {
        linkedApps.removeAll { $0.bundleID == bundleID }
        refreshAddableApps()
    }

    func isRunning(_ app: LinkedApp) -> Bool { runningIDs.contains(app.bundleID) }
    func icon(for bundleID: String) -> NSImage? { workspace.icon(forBundleID: bundleID) }
    func activate(_ app: LinkedApp) { workspace.activate(bundleID: app.bundleID) }

    // MARK: - Events

    func handle(_ event: WorkspaceEvent) {
        switch event {
        case .launched(let id):
            runningIDs.insert(id)
            refreshAddableApps()
        case .terminated(let id):
            runningIDs.remove(id)
            refreshAddableApps()
        case .activated(let id):
            frontmostID = id
        }
        recompute()
    }

    /// Pure evaluation of the linked-app rules.
    nonisolated static func evaluate(
        linkedApps: [LinkedApp], runningIDs: Set<String>, frontmostID: String?, rule: LinkedRule
    ) -> LinkedEvaluation {
        let running = linkedApps.filter { runningIDs.contains($0.bundleID) }
        let frontmostIsLinked = frontmostID.map { id in linkedApps.contains { $0.bundleID == id } } ?? false
        let shouldBeActive = rule == .running ? !running.isEmpty : frontmostIsLinked
        let effectiveMode = running.compactMap(\.modeOverride).max { $0.strength < $1.strength }
        return LinkedEvaluation(
            runningLinked: running, frontmostIsLinked: frontmostIsLinked,
            shouldBeActive: shouldBeActive, effectiveMode: effectiveMode
        )
    }

    private func recompute() {
        let result = Self.evaluate(linkedApps: linkedApps, runningIDs: runningIDs, frontmostID: frontmostID, rule: rule)
        if runningLinked != result.runningLinked { runningLinked = result.runningLinked }
        if frontmostIsLinked != result.frontmostIsLinked { frontmostIsLinked = result.frontmostIsLinked }
        if shouldBeActive != result.shouldBeActive { shouldBeActive = result.shouldBeActive }
        if effectiveMode != result.effectiveMode { effectiveMode = result.effectiveMode }
        let newState = LinkedState(
            autoEnabled: autoEnabled, shouldBeActive: result.shouldBeActive,
            effectiveMode: result.effectiveMode, runningLinkedIDs: result.runningLinked.map(\.bundleID)
        )
        if state != newState { state = newState }
    }

    private func refreshAddableApps() {
        let linked = Set(linkedApps.map(\.bundleID))
        let own = Bundle.main.bundleIdentifier
        let apps = workspace.runningRegularApps().filter { !linked.contains($0.bundleID) && $0.bundleID != own }
        if apps != addableApps { addableApps = apps }
    }
}
