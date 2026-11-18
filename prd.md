# Jiggle — Product Requirements Document

Personal-use macOS menu bar app that keeps the Mac awake and "active" on demand.
Native Swift/SwiftUI, no App Store, no sandbox, no third-party dependencies.

**Target:** macOS 13 Ventura or later, Apple Silicon and Intel, Xcode 15+.

---

## 1. Overview

### Goals

- One click from the menu bar to start or stop keeping the Mac awake.
- Four keep-alive strengths: silent power assertion, idle-timer reset, real cursor nudge, and nudge + click.
- Linked apps: stay active only while chosen apps (e.g. Claude, ChatGPT, WhatsApp) are running; go idle when none are.
- Never fight the user: pause automatically while the mouse or keyboard is in real use.
- Timed sessions (15 min to 4 h, until a time, indefinite) and a global hotkey.
- Idle CPU under 0.5% and memory under 30 MB.

### Non-goals

- App Store or notarized public distribution, auto-update, licensing.
- Windows/Linux versions, a Dock icon, or a main window beyond Settings.
- Simulating keystrokes or text input (clicks only in the opt-in Jiggle + Click mode).

---

## 2. Requirements

v1 ships the P0 features; P1 follows once the core loop is stable.

| ID | Feature | Behaviour | Priority |
| --- | --- | --- | --- |
| F1 | Menu bar toggle | Icon toggles on/off; SF Symbol changes with state (`cursorarrow` / `cursorarrow.motionlines` / `cursorarrow.click.2`) | P0 |
| F2 | Mode: Keep Awake | Holds an IOKit assertion that prevents display and system idle sleep. No permissions, no cursor motion | P0 |
| F3 | Mode: Zen | Calls `IOPMAssertionDeclareUserActivity` every interval to reset the system idle timer; no visible motion | P0 |
| F4 | Mode: Jiggle | Moves cursor by N px and back every interval via `CGEvent`. Needs Accessibility permission | P0 |
| F5 | Interval | 10 s to 10 min, default 60 s; optional ±20% random jitter | P0 |
| F6 | Smart pause | Skip a tick if real mouse/keyboard input happened within the last interval | P0 |
| F7 | Timed session | 15 min, 30 min, 1 h, 2 h, 4 h, until a set time, indefinite. Remaining time shown in menu | P0 |
| F8 | Settings window | Mode, interval, distance (1–20 px), jitter, smart pause, click options, linked apps, hotkey, launch at login | P0 |
| F9 | Persist settings | All settings in `UserDefaults`; restore last mode on launch (starts disabled unless linked-app Auto applies) | P0 |
| F16 | Mode: Jiggle + Click | Jiggle plus a click every Nth tick (default 5th). Left or right, single. Target: pinned point (default) or current position. Skipped during smart pause, while a modifier key is held, or when the frontmost app is blocklisted. Needs Accessibility | P0 |
| F17 | Linked apps | Pick apps from running apps or /Applications; stored by bundle ID. Auto on: start when any linked app launches, stop when the last one quits. Menu shows which linked apps are running | P0 |
| F18 | Linked-app rule and per-app mode | Rule: "is running" (default) or "is frontmost". Optional per-app mode override; strongest mode among running linked apps wins. Manual Start/Stop overrides Auto until the next linked-app launch or quit | P1 |
| F10 | Global hotkey | Default ⌃⌥⌘J toggles on/off | P1 |
| F11 | Launch at login | `SMAppService.mainApp` register/unregister | P1 |
| F12 | Schedule | Auto-enable on chosen weekdays between start/end times | P1 |
| F13 | Battery guard | Auto-stop on battery below a set % (default 20%) | P1 |
| F14 | Stop on lock/sleep | Stop when screen locks or lid closes; optionally resume on unlock | P1 |
| F15 | Notifications | Optional notification when a timed session ends | P1 |

### Menu layout

1. Status line: "Active — Zen · 42 min left", "Active — linked: Claude, WhatsApp" or "Inactive — no linked app running"
2. Start / Stop
3. Start for ▸ 15 min · 30 min · 1 h · 2 h · 4 h · Until… · Indefinitely
4. Mode ▸ Keep Awake · Zen · Jiggle · Jiggle + Click (checkmark on current)
5. Linked apps ▸ Auto on/off · each linked app with a running dot · Link an app…
6. Set click point… (shown in Jiggle + Click mode)
7. Settings… (⌘,)
8. Quit Jiggle (⌘Q)

### Non-functional requirements

- **CPU:** one `DispatchSourceTimer`, no polling loops; app tracking is notification-driven. Idle CPU < 0.5%.
- **Memory:** < 30 MB resident.
- **Reliability:** all assertions released on stop, quit and termination (`applicationWillTerminate`).
- **Privacy:** no network access, no analytics, no logging of input events.
- **Permissions:** Accessibility requested only when Jiggle or Jiggle + Click is chosen, with an explanation and a button to open System Settings.

### Acceptance criteria

- With Keep Awake on and display sleep set to 1 min, the screen stays on for 10+ min.
- With Zen on, `HIDIdleTime` (via `ioreg`) resets each interval.
- With Jiggle on, the cursor nudges and returns to the same point; with smart pause on, no nudge while you move the mouse.
- In Jiggle + Click with a pinned point, the click lands on that point and the cursor returns; no click while ⌘, ⌥, ⌃ or ⇧ is held.
- With Auto on and Claude linked: launching Claude starts Jiggle within 2 s; quitting it stops Jiggle and releases all assertions within 2 s.
- A 15-min session stops itself and releases every assertion (`pmset -g assertions` shows none from Jiggle).
- Settings survive an app restart.

---

## 3. Technical design

Swift 5.9 + SwiftUI `MenuBarExtra`, `LSUIElement` agent app (no Dock icon), App Sandbox **off**, Hardened Runtime on, signed with your free Apple Development certificate.

### Modes

| Mode | API | What it defeats | Permission |
| --- | --- | --- | --- |
| Keep Awake | `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)` held until stop | Display sleep, system sleep, screensaver | None |
| Zen | `IOPMAssertionDeclareUserActivity(..., kIOPMUserActiveLocal, ...)` each tick | Above + resets system idle time | None |
| Jiggle | `CGEvent` `.mouseMoved` posted to `.cghidEventTap`, +N px then back | Above + apps that watch real cursor movement | Accessibility |
| Jiggle + Click | Jiggle tick, plus every Nth tick: save point, post mouseDown/mouseUp at pinned point 40 ms apart, move back | Above + apps that only count clicks | Accessibility |

**Smart pause** reads `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`; below the interval, the tick is skipped. Jiggle restores the exact original point from `NSEvent.mouseLocation` (convert Cocoa bottom-left to CG top-left using the main screen height).

**Click safety.** The pinned point is captured with a 3-second countdown ("move your cursor where clicks should land") — choose empty space in the linked app or the desktop. Before each click, skip it if:

- `CGEventSource.flagsState(.combinedSessionState)` shows ⌘/⌥/⌃/⇧ held,
- the user was active within the interval,
- the frontmost app is on the blocklist (defaults: Terminal, iTerm2, Xcode, Finder, System Settings),
- "click only when a linked app is frontmost" is on and it isn't.

**Linked apps.** `AppWatcher` keeps the linked bundle IDs and the subset running. It seeds from `NSWorkspace.shared.runningApplications`, then listens to `didLaunchApplicationNotification`, `didTerminateApplicationNotification` and (frontmost rule) `didActivateApplicationNotification`. On each change it publishes `shouldBeActive` and the effective mode; `JiggleEngine` starts, stops or switches strategy. No polling. Example bundle IDs: Claude `com.anthropic.claudefordesktop`, ChatGPT `com.openai.chat`, WhatsApp `net.whatsapp.WhatsApp` — the picker reads them from the chosen `.app` with `Bundle(url:)?.bundleIdentifier`.

### Components

| File | Responsibility |
| --- | --- |
| `JiggleApp.swift` | `@main`, `MenuBarExtra` + `Settings` scene, injects engine and watcher |
| `JiggleEngine.swift` | `ObservableObject`: `isActive`, `mode`, `endsAt`, `activeReason`; start/stop, timer, assertion lifecycle |
| `ActivityStrategy.swift` | Protocol `start() / tick() / stop()` + Keep Awake, Zen, Jiggle strategies |
| `ClickStrategy.swift` | `JiggleClickStrategy`: click every Nth tick, safety checks, point capture |
| `AppWatcher.swift` | Linked apps store, running/frontmost tracking, `shouldBeActive` + effective mode |
| `IdleMonitor.swift` | Seconds since last real input |
| `Permissions.swift` | Accessibility check, prompt, open System Settings |
| `Settings.swift` | `@AppStorage` keys and defaults |
| `MenuView.swift` / `SettingsView.swift` / `LinkedAppsView.swift` | UI |
| `HotKey.swift` | Carbon `RegisterEventHotKey` wrapper (P1) |
| `LoginItem.swift` | `SMAppService.mainApp` (P1) |
| `PowerMonitor.swift` | Battery via `IOPSCopyPowerSourcesInfo`; lock/sleep via `NSWorkspace` + `com.apple.screenIsLocked` (P1) |

### Gotchas

- Accessibility permission is tied to the code signature. Ad-hoc ("Sign to Run Locally") builds lose it on every rebuild; sign with your Apple ID's team so it sticks.
- `CGEvent` posting fails silently without permission: check `AXIsProcessTrusted()` before each tick and fall back to Zen with a menu warning.
- Keep assertion IDs and release them with `IOPMAssertionRelease` on every stop path.
- Linking works for native apps only — WhatsApp Web or ChatGPT in a browser tab can't be told apart from the browser.
- Real clicks can do real things (send a message, press a button). Keep the pinned point on empty space and keep the blocklist on.
- Work machines: some employers monitor or forbid activity simulators — check policy before using it on a company Mac.

---

## 4. Setup and build

1. Install Xcode 15+ from the App Store, open it once, then run `xcode-select --install` and `sudo xcodebuild -license accept`.
2. Xcode → Settings → Accounts → add your Apple ID (free Personal Team is enough).
3. File → New → Project → macOS → App. Name `Jiggle`, SwiftUI, Swift, no tests/Core Data. Bundle ID e.g. `com.sabbir.jiggle`. Save to `~/Projects/Jiggle`, tick "Create Git repository".
4. Target → General: Minimum Deployment macOS 13.0.
5. Target → Signing & Capabilities: Team = Personal Team; delete **App Sandbox**; keep **Hardened Runtime**.
6. Target → Info: add `Application is agent (UIElement)` = `YES`.
7. In Terminal at the project folder run `claude` and paste the prompt from `CLAUDE_CODE_PROMPT.md`.
8. Build and run with ⌘R, or `xcodebuild -scheme Jiggle -configuration Release build`.
9. First Jiggle start: approve the prompt, enable Jiggle in System Settings → Privacy & Security → Accessibility, then relaunch.
10. Product → Archive → Distribute App → Custom → Copy App; drag `Jiggle.app` into `/Applications`; turn on Launch at login.

### Verify

- `pmset -g assertions | grep -i jiggle` — assertion present while active, gone after stop.
- `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'` — idle seconds drop near 0 each Zen/Jiggle tick.
- Set Display sleep to 1 minute and leave the Mac untouched for 5 minutes.

**Accessibility lost after a rebuild?** Remove Jiggle from the Accessibility list and re-add it from `/Applications`, or run `tccutil reset Accessibility com.sabbir.jiggle`.