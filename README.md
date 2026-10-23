# 🍅🐶 PomodoroPup

> A macOS menu bar Pomodoro timer with an animated dog companion and achievement badges.

![Platform](https://img.shields.io/badge/platform-macOS%2015.5%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI-green)
![Architecture](https://img.shields.io/badge/architecture-MVVM-lightgrey)

PomodoroPup lives quietly in your menu bar. Start a focus session and a little dog works alongside you; take a break and it kicks back with a cup of coffee. Complete sessions to unlock badges in the achievement wall — a bone, glasses, a crown — and make focusing a small, rewarding ritual. These are achievement icons; the current app does not dress the dog in unlocked items.

**[中文文档 →](README.zh-CN.md)**

---

## ⬇️ Download

**[⬇️ Download PomodoroPup 1.0 (.zip)](https://github.com/yvetteL19/PomodoroPup/releases/download/v1.0/PomodoroPup.1.0.zip)** — or browse all [Releases](https://github.com/yvetteL19/PomodoroPup/releases).

Because the app is not signed with an Apple Developer certificate, macOS may warn that the developer "cannot be verified" or that the file is "damaged" on first launch.

**To open it:**

1. Download and unzip — **don't** double-click the app directly.
2. **Right-click** the app icon and choose **Open**.
3. Click **Open** in the warning dialog.

(Or go to **System Settings → Privacy & Security → Open Anyway**.)

The download above is the existing 1.0 release. The reliability and experience changes described below apply to the current source; this work has not published a replacement archive. To use the current source, see [Build & Run](#-build--run).

---

## 📸 Interface previews

These are native SwiftUI renders of the current source using isolated sample preferences and a fake notification service. They show layout, not proof of real notification delivery. The 1.0 download still has the earlier interface.

| First start | Dark appearance | Ready for the next focus |
| :---: | :---: | :---: |
| ![Welcome](docs/screenshots/phase-two-welcome.png) | ![Dark appearance](docs/screenshots/phase-two-ready-dark.png) | ![Waiting](docs/screenshots/phase-two-waiting.png) |

---

## ✨ Features

- **Lives in the menu bar** — a status icon plus a live countdown, always one glance away. No extra window cluttering your desktop.
- **Animated dog companion** — a focused pup with a subtle breathing animation while you work, and a relaxed coffee-sipping dog (animated GIF) during breaks.
- **Your next session, your choice** — completed work enters a break; rest ends waiting for you to start again. Automatically starting the next focus is an optional setting. The daily goal provides feedback without limiting further work.
- **Achievement system** — six badges reward milestones, consistency, consecutive completed sessions, and rest. Sounds and animations respect their settings; visual effects also respect Reduce Motion.
- **Progress at a glance** — a text count and progress bar show today’s completed work sessions, excluding skips. The achievement wall shows progress toward the next milestone.
- **Native notifications** — reminders for breaks, the next session and daily goals. Settings shows actual macOS permission and alert status, with permission recovery and a test reminder.
- **Native settings window** — focus/break durations, daily target, optional automation, sound, animation and reminders. The panel offers settings, quit and keyboard actions; app shortcuts do not run globally.
- **Bilingual** — English and Simplified Chinese, switched automatically by your system language.
- **One-screen first start** — choose 10, 25 or 45 minutes and begin; notification authorization is optional. The welcome explains where to find the menu bar timer.
- **Paused recovery** — active timers are checkpointed during use and restored paused after restart or sleep. Resume explicitly; time away is not counted as work or rest.
- **Protected local data** — versioned snapshots preserve statistics and preferences; legacy values are backed up before migration. Unreadable or unsupported data stops the timer and is preserved. The app runs offline and sandboxed.

---

## 🔄 How it works

```
 Ready → Start → Work → Break → Wait → Start next focus
                              └─ optional automation → Work
 Any active phase → Pause → Resume the same phase
 Restart / sleep → Restore paused → Resume explicitly
```

- Only a naturally **completed** work phase increments the lifetime total, the completion-day count, the consecutive-work count, and the current batch count.
- A completed work phase transitions to a break. By default, rest ends waiting for you to start the next focus. The daily target (default 4) never prevents another session.
- **End break** always waits for your next start, even with automation enabled. Ending an unfinished focus through the secondary menu adds no completion; the confirmation explains that its unfinished timer is cleared.
- **Reset** abandons the unfinished phase, clears the current batch and consecutive-work count, and retains completed work and achievements. A phase already at its deadline is settled before the action.
- **Start** from the ready state begins a fresh batch. Today’s progress remains separate and is not cleared by a new batch or reset.
- Changes to focus/break durations apply to future phases, including a waiting focus that has not started. A running or paused phase retains its own duration and remaining time.
- Break time accumulates only while a break is running. Sleeping, paused, and offline intervals are excluded.
- Daily totals use the calendar day of completion in the time zone saved when the new storage is first created or legacy data is migrated. Changing the system time zone does not rewrite existing day totals.

The current storage contains daily completion counts and the current timer checkpoint, not a history of individual sessions. Read [Experience rules](docs/experience.md), [Reliability and data preservation](docs/reliability.md), and the [native acceptance record](docs/native-acceptance-2026-10-23.md) for migration details, recovery limits, and completed/pending checks.

---

## 🏆 Achievements

| Icon | Name | How to unlock |
| :---: | :--- | :--- |
| 🦴 | **Rookie Pup** | Complete 10 pomodoros |
| 👓 | **Efficient Partner** | Complete 50 pomodoros |
| 👑 | **Focus Master** | Complete 200 pomodoros |
| 🐾 | **Daily Streak** | 3 consecutive days with 4+ pomodoros each |
| 💡 | **Deep Worker** | 3 consecutive completed pomodoros without skipping work or resetting |
| ✨ | **Dance King** | Accumulate 300 minutes of break time |

New achievements can play a sound, flash the menu-bar label, and shake the trophy button when those effects are enabled. Loading an existing achievement does not replay its celebration.

---

## 🛠 Build & Run

**Requirements:** macOS 15.5+, Xcode 16.4+ selected as the active developer tools.

```bash
git clone https://github.com/yvetteL19/PomodoroPup.git
cd PomodoroPup
open PomodoroPup.xcodeproj
```

Then build and run from Xcode (**⌘R**). A first-launch welcome explains the menu bar entry. Click that entry to open the timer; use settings or quit from the panel.

Run deterministic model and storage tests without launching the app:

```bash
swift test
```

Build both configurations without signing (local validation, not a distributable release):

```bash
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/PomodoroPup-Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/PomodoroPup-Release CODE_SIGNING_ALLOWED=NO build
```

Tests use isolated `UserDefaults` suites and an injected clock. They do not launch the menu bar app or alter its real preferences. The [macOS CI workflow](.github/workflows/ci.yml) runs the same test and build checks. Passing these checks does not verify real system sleep, notification delivery, or distribution signing; see the [manual checklist](docs/reliability.md#manual-checks-not-yet-performed).

---

## 🧱 Architecture

The app follows **MVVM** with SwiftUI's `MenuBarExtra` for presentation.

| File | Responsibility |
| :--- | :--- |
| `PomodoroPupApp.swift` | App entry point; configures `MenuBarExtra`, the live menu-bar label (with achievement flash), the first-launch welcome, and an independent settings window. |
| `DogViewModel.swift` | Phase transitions, elapsed-time settlement, daily/batch statistics, achievements, lifecycle recovery, and feedback after a successful save. |
| `TimerClock.swift` | Injectable wall time for dates and monotonic uptime for elapsed time. |
| `StateStore.swift` | Versioned JSON snapshots, validation, and legacy migration with a one-time backup. |
| `ContentView.swift` | Main popup: dog, countdown, today’s text and progress bar, phase/pause/waiting/recovery/error states, and controls; achievement wall, settings and quit entries. |
| `DogView.swift` | The animated dog: breathing focus pose, and the GIF/static rest pose (via an `NSViewRepresentable` GIF player). |
| `SettingsView.swift` | Time settings, companion-mode toggles, and statistics. |
| `OnboardingView.swift` | Single-page first-run welcome with duration presets. |
| `NotificationService.swift` | Injectable system notification permission, alert status, authorization and reminder delivery. |
| `SoundManager.swift` | AVFoundation / system-sound playback. |

**Tech stack:** SwiftUI · Combine · AppKit (GIF rendering & sounds) · UserNotifications · AVFoundation.

---

## 🌐 Localization

UI strings live in `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings` and are resolved through `NSLocalizedString`. The app follows your system language automatically.

---

## 🔒 Privacy

PomodoroPup is fully offline and sandboxed. Settings, achievements, daily completion counts, and the current timer checkpoint are stored locally via `UserDefaults`. There is no analytics, no account, and no network access. The legacy migration backup is local to the same preferences store; it is not cloud sync or an independent backup service.

---

## 📁 Project Structure

```
PomodoroPup/
├── PomodoroPup.xcodeproj/        # Xcode project
├── PomodoroPup/                  # Source
│   ├── PomodoroPupApp.swift
│   ├── DogViewModel.swift
│   ├── TimerClock.swift
│   ├── StateStore.swift
│   ├── NotificationService.swift
│   ├── ContentView.swift
│   ├── DogView.swift
│   ├── SettingsView.swift
│   ├── OnboardingView.swift
│   ├── SoundManager.swift
│   ├── Assets.xcassets/          # Dog art, achievement icons
│   ├── en.lproj / zh-Hans.lproj  # Localizations
│   └── *.MP3                     # Sound effects
├── Tests/PomodoroPupCoreTests/  # Deterministic model and storage tests
├── Package.swift                # Production model exposed to SwiftPM tests
├── .github/workflows/ci.yml      # macOS tests and Debug/Release builds
├── docs/reliability.md           # Data/recovery rules and manual validation
├── docs/screenshots/            # Earlier README screenshots
└── README.md
```

---

<p align="center">Made with 🍅 and 🐶 — focus a little, get rewarded a little.</p>
