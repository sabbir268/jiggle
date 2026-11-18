# Jiggle — Task List

M0–M2.5 give you a usable app; M3–M4 are extras and polish.

## M0 — Project setup

- [x] Create Xcode project, macOS 13 target, SwiftUI
- [ ] Remove App Sandbox, keep Hardened Runtime, set Personal Team signing (sandbox off and Hardened Runtime on are done; signing is still ad-hoc)
- [x] Set `LSUIElement = YES`
- [x] Add `CLAUDE.md` and initial git commit

## M1 — Core engine (P0)

- [x] `Settings.swift` with `@AppStorage` keys and defaults
- [x] `ActivityStrategy` protocol + `KeepAwakeStrategy` (IOPM assertion)
- [x] `ZenStrategy` (`IOPMAssertionDeclareUserActivity` per tick)
- [x] `JiggleStrategy` (CGEvent move + restore, coordinate conversion)
- [x] `IdleMonitor` + smart pause
- [x] `JiggleEngine`: start/stop, `DispatchSourceTimer`, jitter, release on every stop path and on terminate
- [x] Timed sessions with `endsAt` and auto-stop

## M2 — UI (P0)

- [x] `MenuBarExtra` with state-based SF Symbol icon
- [x] Menu: status line with countdown, Start/Stop, Start for ▸, Mode ▸, Settings…, Quit
- [x] Settings window (General tab): mode, interval, distance, jitter, smart pause
- [x] `Permissions.swift`: Accessibility check, explainer, open System Settings, fallback to Zen

## M2.5 — Click and linked apps (P0)

- [x] `JiggleClickStrategy`: click every Nth tick, left/right, pinned or current point, restore cursor
- [x] Click safety: modifier check, smart pause, frontmost-app blocklist, "only when linked app is frontmost" option
- [x] "Set click point…" with 3-second countdown capture
- [x] Click settings tab (every N ticks, button, target, point preview, blocklist editor)
- [x] `AppWatcher`: linked bundle IDs, seed from running apps, launch/terminate/activate notifications
- [x] Engine wiring: Auto mode starts/stops on linked-app changes; manual override until next change
- [x] `LinkedAppsView`: add from running apps or /Applications, icons, remove, rule picker, Auto toggle
- [x] Menu: Linked apps submenu with running dots; status line names running linked apps
- [x] P1: per-app mode override, strongest mode wins

## M3 — Extras (P1)

- [x] Global hotkey ⌃⌥⌘J via Carbon `RegisterEventHotKey`
- [x] Launch at login via `SMAppService.mainApp`
- [x] Weekday schedule (start/end time)
- [x] Battery guard and stop on lock/sleep
- [x] Session-ended notification (`UserNotifications`)

## M4 — Test and install

- [x] Unit tests: jitter range, session end time, coordinate conversion, smart-pause decision
- [x] Unit tests: click-skip decision (modifiers, blocklist, frontmost rule, every-Nth counter)
- [x] Unit tests: `AppWatcher` `shouldBeActive` / effective mode for running and frontmost rules
- [ ] Manual checks (`pmset`, `ioreg`, 1-min display sleep, launch/quit a linked app)
- [x] Remove debug menu, write README.md
- [ ] Archive, copy to `/Applications`, enable launch at login
- [ ] Optional: simple app icon