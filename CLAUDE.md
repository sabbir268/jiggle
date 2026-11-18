# Jiggle

Personal-use macOS menu bar app that keeps the Mac awake and "active". Full product spec: `prd.md`;
task checklist: `tasks.md`. This file is the working summary for coding sessions.

## Project facts

- SwiftUI app, macOS 13+, Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY = complete`.
- App Sandbox **off**, Hardened Runtime **on**, `LSUIElement = YES` (no Dock icon), bundle ID `com.sabbir.jiggle`.
- `Jiggle.xcodeproj` uses a file-system-synchronized group: any `.swift` file placed in `Jiggle/` is compiled
  automatically, no pbxproj edits needed. Info.plist is generated (`INFOPLIST_KEY_*` build settings).
- Signing is ad-hoc (`CODE_SIGN_IDENTITY = "-"`, no team). Accessibility permission is tied to the code
  signature, so it is lost on every rebuild until a team is set (or `tccutil reset Accessibility com.sabbir.jiggle`).
- **No third-party dependencies or Swift packages.**

## Build

```sh
xcodebuild -scheme Jiggle -configuration Debug build
xcodebuild -scheme Jiggle -configuration Debug test
```

Under XCTest (`XCTestConfigurationFilePath` set) the app skips linked-app and automation wiring, so tests
never start a real session.

`xcode-select` on this machine points at the Command Line Tools, so prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (or run `sudo xcode-select -s /Applications/Xcode.app`).
Every build must finish with zero errors **and zero warnings**.

## Workflow

Work milestone by milestone (M1 → M2 → M2.5 → M3 → M4). After each one: build, fix all errors and warnings,
commit with a short clear message (no AI co-author / attribution trailers), list what to test manually
(including `pmset -g assertions` checks), then wait for the go-ahead.

## Architecture

| File | Responsibility |
| --- | --- |
| `JiggleApp.swift` | `@main`; `MenuBarExtra` (`.menu` style) + `Settings` scene; owns `JiggleEngine` and `AppWatcher` as `@StateObject`, injects them as environment objects |
| `Settings.swift` | `Mode`, `ClickButton`, `ClickTarget`, `LinkedRule`, `LinkedApp`; `SettingsKey` (`@AppStorage` keys), `SettingsDefault`, `SettingsStore` (typed reader for non-view code) |
| `SystemServices.swift` | Protocols for everything that touches the system (power assertions, idle time, cursor, event posting) + live implementations, bundled in `SystemServices` |
| `IdleMonitor.swift` | `secondsSinceLastInput()` via `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`; pure smart-pause decision |
| `TickScheduling.swift` | Pure helpers: jitter (±20 %), `endsAt`, next-tick delay, Cocoa→CG coordinate conversion |
| `ActivityStrategy.swift` | `protocol ActivityStrategy { start(); tick(); stop() }` + `KeepAwakeStrategy`, `ZenStrategy`, `JiggleStrategy` |
| `ClickStrategy.swift` | Pure `ClickDecision.evaluate` (skip reasons), `JiggleClickStrategy` (wraps Jiggle), `ClickPointCapture` (3-s countdown shown in the menu bar) |
| `AppWatcher.swift` | Owns `linkedApps`, `rule`, `autoEnabled`; publishes running/frontmost state and a deduplicated `LinkedState` for the engine |
| `Workspace.swift` | `WorkspaceProviding` (NSWorkspace running/frontmost apps, launch/terminate/activate notifications, icons) + live impl |
| `JiggleEngine.swift` | `@MainActor ObservableObject`: `isActive`, `mode`, `endsAt`, `activeReason`, `warning`; `start(duration:reason:)`, `stop()`, `toggle()`; one `DispatchSourceTimer` |
| `Permissions.swift` | `AXIsProcessTrusted`, prompt, open Accessibility settings |
| `PermissionExplainer.swift`, `UntilPicker.swift`, `WindowPresenter.swift` | Auxiliary AppKit-hosted windows (agent app: no `Window` scenes, which could auto-open at launch) |
| `StatusText.swift` | Pure menu status line formatting |
| `MenuView.swift`, `SettingsView.swift`, `ClickSettingsView.swift`, `LinkedAppsView.swift` | UI. Settings tab selection lives in `UserDefaults` key `settingsTab` so menu items can open a given tab |
| `HotKey.swift`, `LoginItem.swift`, `PowerMonitor.swift` | Carbon hotkey ⌃⌥⌘J, `SMAppService.mainApp`, battery guard + lock/sleep |
| `Scheduler.swift`, `SessionNotifier.swift` | Pure `ScheduleWindow.contains` + 1-minute edge-based checker; timed-session-ended notification |
| `LidSleep.swift` | Lid-closed mode: `pmset -a disablesleep` via a scoped sudo rule; restored on every stop path and after a crash |
| `scripts/make-dmg.sh`, `scripts/render-icon.swift` | DMG packaging + GitHub Release (`--release`); app icon generator |
| `Automation.swift` | Owns the M3 extras; re-applies settings on `UserDefaults.didChangeNotification` |
| `*SettingsView.swift` | One file per Settings tab (General, Click, Linked Apps, Schedule, Power, Shortcut) |
| `JiggleTests/` | Hosted XCTest bundle (macOS 14 target, required by Xcode 27's XCTest). `Fakes.swift` fakes every system protocol |

### Modes (strength order keepAwake < zen < jiggle < jiggleClick)

- **Keep Awake**: `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, "Jiggle Keep Awake")` on start, released on stop; tick no-op.
- **Zen**: Keep Awake + `IOPMAssertionDeclareUserActivity("Jiggle", kIOPMUserActiveLocal, &id)` each tick (the returned ID is reused and released on stop).
- **Jiggle**: Zen + post `.mouseMoved` to point+distance, then back to the original point 50 ms later
  (`CGEventSource(stateID: .hidSystemState)`, `.cghidEventTap`). Point comes from `NSEvent.mouseLocation`
  converted with `NSScreen.screens[0].frame.height`. Needs Accessibility.
- **Jiggle + Click**: Jiggle + every `clickEveryNTicks`-th tick a mouseDown/mouseUp (40 ms apart) at the pinned point
  or current position, then cursor restored. Skip the click (still jiggle) when a modifier is held, user was active
  within the interval, frontmost app is blocklisted, `clickOnlyWhenLinkedFrontmost` and frontmost is not linked,
  or target is pinned and no point is set. Needs Accessibility.

### Engine rules

- Single `DispatchSourceTimer` on the main queue, re-armed one-shot each tick with jitter; the delay is capped so a
  timed session ends on time (`endsAt`).
- Smart pause: skip the tick if `secondsSinceLastInput() < interval` — but input caused by Jiggle's own previous
  tick (synthetic events / declared activity) does not count as user input.
- Assertions stay held while ticks are skipped. Everything is released in `stop()` and on `NSApplication.willTerminate`.
- Switching mode while active stops the old strategy and starts the new one.
- `mode` is what the user chose; `runningMode` is what actually runs. A Jiggle mode without Accessibility runs
  Zen, sets `warning` and calls `onAccessibilityNeeded` (explainer); every tick re-checks and upgrades/downgrades.
- `JiggleEngine.mode` is the source of truth for the mode (it persists to `UserDefaults`); UI binds to the engine,
  not to `@AppStorage("mode")`.
- Linked auto: automatic starts never pop up the permission explainer. An app's mode override wins over the global mode during linked sessions.
- Linked auto: `shouldBeActive` true → `start(reason: .linked)` with `effectiveMode ?? mode`; false → stop if
  `activeReason == .linked`. Manual Start/Stop overrides auto until the next AppWatcher change.

### Settings keys and defaults

mode `zen` · intervalSeconds 60 (10–600) · jitterEnabled true (±20 %) · jiggleDistance 2 (1–20) · smartPause true ·
clickEveryNTicks 5 (1–20) · clickButton left · clickTarget pinnedPoint · clickPoint "x,y" string, unset by default ·
clickBlocklist com.apple.Terminal, com.googlecode.iterm2, com.apple.dt.Xcode, com.apple.finder,
com.apple.systempreferences (stored newline-separated) · clickOnlyWhenLinkedFrontmost false · linkedAutoEnabled false ·
linkedRule running · linkedApps JSON `Data` of `[LinkedApp]` · launchAtLogin false · hotkeyEnabled true ·
batteryGuardPercent 20 · stopOnLock true · resumeOnUnlock false · scheduleEnabled false · scheduleDays "2,3,4,5,6"
(Calendar weekdays) · scheduleStart 540 / scheduleEnd 1080 (minutes after midnight).

## Conventions

- No force unwraps except the `CGEventType(rawValue: ~0)!` constant.
- Small, single-purpose files. Anything touching the system (idle time, modifier flags, event posting, cursor,
  power assertions, NSWorkspace) goes behind a protocol so tests can fake it.
- No network code, no analytics, never log input events.
- Idle CPU < 0.5 %, memory < 30 MB: no polling loops besides the single tick timer and the 1-minute schedule check;
  app tracking is notification-driven.
- Every assertion created must be released on every stop path; manual test notes always include `pmset -g assertions`.
- Never compare `Date`s with `<=` or `>=`: with the Xcode 27 toolchain on macOS 27 they segfault (null jump in
  `Date.>=`). Compare `timeIntervalSince(_:)` values instead; `<`, `>` and `==` are fine.
