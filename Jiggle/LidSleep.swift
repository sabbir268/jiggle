import AppKit

enum LidSleepError: LocalizedError {
    case unsupportedUserName
    case adminCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedUserName: "Your account name contains characters Jiggle can't put in a sudo rule."
        case .adminCommandFailed(let message): message
        }
    }
}

/// System-wide sleep switch (`pmset disablesleep`), the only way to stay awake with the lid closed.
@MainActor
protocol LidSleepControlling: Sendable {
    /// The one-time sudo rule is installed.
    var isSetUp: Bool { get }
    func isSleepDisabled() -> Bool
    /// Returns false when the change could not be made (e.g. the sudo rule is missing).
    func setSleepDisabled(_ disabled: Bool) -> Bool
    /// Installs the sudo rule. Asks for an administrator password.
    func setUp() throws
    /// Removes the sudo rule. Asks for an administrator password.
    func remove() throws
}

/// Uses a narrowly scoped sudoers rule so `pmset -a disablesleep 0|1` runs without a password prompt.
struct SudoPmsetLidSleep: LidSleepControlling {
    static let rulePath = "/private/etc/sudoers.d/jiggle-pmset"
    private static let pmset = "/usr/bin/pmset"

    var isSetUp: Bool { FileManager.default.fileExists(atPath: Self.rulePath) }

    func isSleepDisabled() -> Bool {
        let output = Self.run("/usr/bin/pmset", ["-g"]).output
        return output.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.count == 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
        }
    }

    func setSleepDisabled(_ disabled: Bool) -> Bool {
        Self.run("/usr/bin/sudo", ["-n", Self.pmset, "-a", "disablesleep", disabled ? "1" : "0"]).status == 0
    }

    func setUp() throws {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw LidSleepError.unsupportedUserName
        }
        let rule = """
            # Installed by Jiggle ("Keep running with the lid closed"). Remove from Jiggle's Power settings.
            \(user) ALL=(root) NOPASSWD: \(Self.pmset) -a disablesleep 0, \(Self.pmset) -a disablesleep 1

            """
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("jiggle-pmset-\(UUID().uuidString)")
        try rule.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        try Self.runAsAdmin(
            "/usr/sbin/visudo -cf '\(temp.path)' && /usr/bin/install -m 0440 -o root -g wheel '\(temp.path)' '\(Self.rulePath)'",
            prompt: "Jiggle needs permission to turn sleep off and on while a lid-closed session runs."
        )
    }

    func remove() throws {
        try Self.runAsAdmin("/bin/rm -f '\(Self.rulePath)'", prompt: "Jiggle wants to remove its sleep rule.")
    }

    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func runAsAdmin(_ command: String, prompt: String) throws {
        func quoted(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let source = "do shell script \"\(quoted(command))\" with prompt \"\(quoted(prompt))\" with administrator privileges"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw LidSleepError.adminCommandFailed("Couldn't prepare the administrator request.")
        }
        script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "The administrator request failed."
            throw LidSleepError.adminCommandFailed(message)
        }
    }
}

/// Disables system sleep while a session runs with "Keep running with the lid closed" on, and restores it on
/// every stop path: Stop, battery guard, turning the option off, Quit, and the next launch after a crash.
@MainActor
final class LidCloseGuard: ObservableObject {
    @Published private(set) var isSetUp: Bool
    @Published private(set) var isEngaged = false
    @Published private(set) var errorMessage: String?

    private let engine: JiggleEngine
    private let settings: SettingsStore
    private let control: any LidSleepControlling
    private var terminateObserver: (any NSObjectProtocol)?

    init(engine: JiggleEngine, settings: SettingsStore, control: any LidSleepControlling = SudoPmsetLidSleep()) {
        self.engine = engine
        self.settings = settings
        self.control = control
        isSetUp = control.isSetUp
        // A crash may have left sleep disabled by us; restore it. Never touch a setting the user made.
        if settings.lidSleepDisabledByJiggle {
            restoreSleep()
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreSleep() }
        }
    }

    /// Call when the session or settings change.
    func update() {
        if settings.keepRunningLidClosed && engine.isActive && isSetUp {
            disableSleep()
        } else {
            restoreSleep()
        }
    }

    func setUp() {
        do {
            try control.setUp()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isSetUp = control.isSetUp
        update()
    }

    func remove() {
        restoreSleep()
        do {
            try control.remove()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isSetUp = control.isSetUp
    }

    private func disableSleep() {
        guard !isEngaged else { return }
        if control.setSleepDisabled(true) {
            isEngaged = true
            settings.lidSleepDisabledByJiggle = true
            errorMessage = nil
        } else {
            errorMessage = "Couldn't turn sleep off. Try Set Up again."
        }
    }

    private func restoreSleep() {
        guard isEngaged || settings.lidSleepDisabledByJiggle else { return }
        isEngaged = false
        if control.setSleepDisabled(false) {
            settings.lidSleepDisabledByJiggle = false
        } else {
            // Keep the marker so the next launch tries again.
            errorMessage = "Couldn't turn sleep back on. Run: sudo pmset -a disablesleep 0"
        }
    }
}
