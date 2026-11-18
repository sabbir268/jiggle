import AppKit

struct RunningApp: Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String

    var id: String { bundleID }
}

enum WorkspaceEvent: Sendable, Equatable {
    case launched(bundleID: String)
    case terminated(bundleID: String)
    case activated(bundleID: String?)
}

/// NSWorkspace access, behind a protocol so `AppWatcher` can be tested with a fake.
@MainActor
protocol WorkspaceProviding: Sendable {
    func runningBundleIDs() -> Set<String>
    func frontmostBundleID() -> String?
    /// Running apps with a Dock presence (`activationPolicy == .regular`), for the "Link an app" menu.
    func runningRegularApps() -> [RunningApp]
    /// Delivers launch/terminate/activate events on the main actor. Keep the returned tokens alive.
    func observe(_ handler: @escaping @MainActor @Sendable (WorkspaceEvent) -> Void) -> [any NSObjectProtocol]
    func icon(forBundleID bundleID: String) -> NSImage?
    func activate(bundleID: String)
}

struct LiveWorkspace: WorkspaceProviding {
    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func runningRegularApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                app.bundleIdentifier.map { RunningApp(bundleID: $0, name: app.localizedName ?? $0) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func observe(_ handler: @escaping @MainActor @Sendable (WorkspaceEvent) -> Void) -> [any NSObjectProtocol] {
        let center = NSWorkspace.shared.notificationCenter
        func add(
            _ name: Notification.Name,
            _ makeEvent: @escaping @Sendable (String?) -> WorkspaceEvent?
        ) -> any NSObjectProtocol {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let event = makeEvent(app?.bundleIdentifier) else { return }
                MainActor.assumeIsolated { handler(event) }
            }
        }
        return [
            add(NSWorkspace.didLaunchApplicationNotification) { $0.map { .launched(bundleID: $0) } },
            add(NSWorkspace.didTerminateApplicationNotification) { $0.map { .terminated(bundleID: $0) } },
            add(NSWorkspace.didActivateApplicationNotification) { .activated(bundleID: $0) },
        ]
    }

    func icon(forBundleID bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func activate(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }
}
