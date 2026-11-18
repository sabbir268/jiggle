# Jiggle

A small personal macOS menu bar app that keeps your Mac awake and "active". Native Swift/SwiftUI,
no dependencies, no network access, no analytics.

## Modes

| Mode | What it does | Permission |
| --- | --- | --- |
| Keep Awake | Holds a power assertion that prevents display and idle sleep | None |
| Zen | Keep Awake + resets the system idle timer every interval | None |
| Jiggle | Zen + nudges the cursor a few pixels and straight back | Accessibility |
| Jiggle + Click | Jiggle + a real click every Nth tick at a pinned point (or the cursor) | Accessibility |

Other features:
- **Smart pause:** Jiggle skips a tick while you are using the mouse or keyboard.
- **Timed sessions:** 15 min to 4 h, until a time, or indefinitely.
- **Linked apps:** stay active only while chosen apps run, or while one is frontmost, with an optional
  mode per app.
- **Schedule:** chosen weekdays and times.
- **Power:** stops on battery below a set level, and on lock or sleep (optionally resuming on unlock).
- **Hotkey and login:** global hotkey ⌃⌥⌘J, launch at login, and a notification when a timed session ends.

## Requirements

- macOS 13 Ventura or later (Apple Silicon or Intel)
- Xcode 15 or later (developed with Xcode 27)

## Build

```sh
# If xcode-select points at the Command Line Tools, select Xcode once:
sudo xcode-select -s /Applications/Xcode.app
# First run of a new Xcode only:
xcodebuild -runFirstLaunch

xcodebuild -scheme Jiggle -configuration Debug build    # build
xcodebuild -scheme Jiggle -configuration Debug test     # unit tests
```

Or open `Jiggle.xcodeproj` and press ⌘R.

### Signing

The project signs ad-hoc ("Sign to Run Locally") by default. That works, but macOS ties the Accessibility
permission to the code signature, so **every rebuild loses it**. To keep it across builds, open the project
in Xcode, then go to Target Jiggle → Signing & Capabilities → Team and pick your Personal Team (a free
Apple ID is enough).

## Install

1. Build a Release copy:
   ```sh
   xcodebuild -scheme Jiggle -configuration Release -derivedDataPath build build
   ```
   Or use Product → Archive → Distribute App → Custom → Copy App in Xcode.
2. Copy `build/Build/Products/Release/Jiggle.app` to `/Applications`.
3. Launch it from `/Applications`. The arrow appears in the menu bar; there is no Dock icon.
4. Optional: Settings → General → **Launch at login**. If macOS asks for approval, click
   "Open Login Items" and enable Jiggle there. Launch at login only works reliably for the copy in
   `/Applications`.

## Distribute as a DMG

```sh
scripts/make-dmg.sh                       # dist/Jiggle-<version>.dmg + .sha256
scripts/make-dmg.sh --release             # also publish GitHub Release v<version> with the DMG
scripts/make-dmg.sh --release --overwrite # replace the files of an existing release
```

The version comes from `MARKETING_VERSION` in the Xcode project; bump it before each new release.
`--release` refuses to run with uncommitted or unpushed changes, so a release always matches the repo.

How the DMG is signed:
- **Without an Apple Developer account,** the app is signed ad-hoc. People who download it must click
  **Open Anyway** in System Settings → Privacy & Security once, and the release notes say so.
- **With a paid Apple Developer Program account,** the DMG is signed and notarized automatically:
  1. Create a "Developer ID Application" certificate in Xcode → Settings → Accounts → Manage Certificates.
  2. Save notary credentials once: `xcrun notarytool store-credentials jiggle-notary`.
  3. Run the script again; it signs, notarizes and staples the DMG.

## Permissions

| Permission | Needed for | How to grant |
| --- | --- | --- |
| Accessibility | Jiggle and Jiggle + Click (posting mouse events) | **Grant Access…** in the explainer, then turn on Jiggle (below) |
| Notifications | "Session ended" alert | Asked the first time you start a timed session |

- **To grant Accessibility:** choose Jiggle or Jiggle + Click, and an explainer opens. Click **Grant Access…**,
  then in System Settings → Privacy & Security → Accessibility turn on **Jiggle**.
- **Until Accessibility is granted:** Jiggle runs Zen, and the menu shows a warning. Once you grant it,
  Jiggle switches to the real mode on the next tick, with no relaunch.
- **If Accessibility stops working after a rebuild:** remove Jiggle from the Accessibility list and add
  it again, or reset it:
  ```sh
  tccutil reset Accessibility com.sabbir.jiggle
  ```

Keep Awake, Zen, the hotkey, linked apps, schedule and power features need no permission.

## Keeping it running with the lid closed

macOS always sleeps a MacBook when the lid closes. Jiggle can't prevent that with a normal power assertion.
There are two ways around it:

- **Clamshell mode:** connect power, an external display and a keyboard or mouse. This is the recommended way.
- **Settings → Power → Lid closed:**
  1. Click **Set Up…** once and enter your password. This installs `/etc/sudoers.d/jiggle-pmset`, which only
     allows `pmset -a disablesleep 0` and `pmset -a disablesleep 1`.
  2. Turn on **Keep running with the lid closed**.

  While a session runs, all system sleep is then off, and lock or screen sleep don't stop it. Sleep comes back
  on Stop, the battery guard, Quit, or the next launch after a crash. **Remove** takes the sudo rule out again.
  A closed, running MacBook can overheat in a bag. If sleep ever stays off, run `sudo pmset -a disablesleep 0`.

## Using Jiggle + Click safely

Clicks are real. Before using this mode:
1. Choose **Set Click Point…** and, during the 3-second countdown, put the cursor on empty space (blank
   area in the linked app, or the desktop).
2. Keep the blocklist on. By default it covers Terminal, iTerm2, Xcode, Finder and System Settings.

A click is skipped (the jiggle still happens) while:
- you hold ⌘, ⌥, ⌃ or ⇧;
- you were active within the interval;
- the frontmost app is blocklisted;
- "only when a linked app is frontmost" is on and none is.

Some employers monitor for, or forbid, activity simulators. Check your policy before using Jiggle on a
work Mac.

## Verify

```sh
pmset -g assertions | grep -i jiggle    # present while active, gone after Stop/Quit
ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'   # drops near 0 each Zen/Jiggle tick
```

## Project layout

See `CLAUDE.md` for the architecture and conventions, and `prd.md` for the full product spec.
