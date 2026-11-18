# Jiggle — Task List

M0–M2.5 give you a usable app; M3–M4 are extras and polish.

## M0 — Project setup

- [ ] Create Xcode project, macOS 13 target, SwiftUI
- [ ] Remove App Sandbox, keep Hardened Runtime, set Personal Team signing
- [ ] Set `LSUIElement = YES`
- [ ] Add `CLAUDE.md` and initial git commit

## M1 — Core engine (P0)

- [ ] `Settings.swift` with `@AppStorage` keys and defaults
- [ ] `ActivityStrategy` protocol + `KeepAwakeStrategy` (IOPM assertion)
- [ ] `ZenStrategy` (`IOPMAssertionDeclareUserActivity` per tick)
- [ ] `JiggleStrategy` (CGEvent move + restore, coordinate conversion)
- [ ] `IdleMonitor` + smart pause
- [ ] `JiggleEngine`: start/stop, `DispatchSourceTimer`, jitter, release on every stop path and on terminate
- [ ] Timed sessions with `endsAt` and auto-stop

## M2 — UI (P0)

- [ ] `MenuBarExtra` with state-based SF Symbol icon
- [ ] Menu: status line with countdown, Start/Stop, Start for ▸, Mode ▸, Settings…, Quit
- [ ] Settings window (General tab): mode, interval, distance, jitter, smart pause
- [ ] `Permissions.swift`: Accessibility check, explainer, open System Settings, fallback to Zen

## M2.5 — Click and linked apps (P0)

- [ ] `JiggleClickStrategy`: click every Nth tick, left/right, pinned or current point, restore cursor
- [ ] Click safety: modifier check, smart pause, frontmost-app blocklist, "only when linked app is frontmost" option
- [ ] "Set click point…" with 3-second countdown capture
- [ ] Click settings tab (every N ticks, button, target, point preview, blocklist editor)
- [ ] `AppWatcher`: linked bundle IDs, seed from running apps, launch/terminate/activate notifications
- [ ] Engine wiring: Auto mode starts/stops on linked-app changes; manual override until next change
- [ ] `LinkedAppsView`: add from running apps or /Applications, icons, remove, rule picker, Auto toggle
- [ ] Menu: Linked apps submenu with running dots; status line names running linked apps
- [ ] P1: per-app mode override, strongest mode wins

## M3 — Extras (P1)

- [ ] Global hotkey ⌃⌥⌘J via Carbon `RegisterEventHotKey`
- [ ] Launch at login via `SMAppService.mainApp`
- [ ] Weekday schedule (start/end time)
- [ ] Battery guard and stop on lock/sleep
- [ ] Session-ended notification (`UserNotifications`)

## M4 — Test and install

- [ ] Unit tests: jitter range, session end time, coordinate conversion, smart-pause decision
- [ ] Unit tests: click-skip decision (modifiers, blocklist, frontmost rule, every-Nth counter)
- [ ] Unit tests: `AppWatcher` `shouldBeActive` / effective mode for running and frontmost rules
- [ ] Manual checks (`pmset`, `ioreg`, 1-min display sleep, launch/quit a linked app)
- [ ] Remove debug menu, write README.md
- [ ] Archive, copy to `/Applications`, enable launch at login
- [ ] Optional: simple app icon