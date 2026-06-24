# 🍅🐶 PomodoroPup

> A macOS menu bar Pomodoro timer with a gamified dog companion that earns cosmetic rewards as you focus.

![Platform](https://img.shields.io/badge/platform-macOS%2015.5%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI-green)
![Architecture](https://img.shields.io/badge/architecture-MVVM-lightgrey)

PomodoroPup lives quietly in your menu bar. Start a focus session and a little dog works alongside you; take a break and it kicks back with a cup of coffee. Complete enough sessions and you unlock achievements — a bone, glasses, a crown — turning the discipline of focusing into a small, rewarding ritual.

**[中文文档 →](README.zh-CN.md)**

---

## ⬇️ Download

Prebuilt builds are published under [**Releases**](https://github.com/yvetteL19/PomodoroPup/releases). Because the app is not signed with an Apple Developer certificate, macOS may warn that the developer "cannot be verified" or that the file is "damaged" on first launch.

**To open it:**
1. Download and unzip — **don't** double-click the app directly.
2. **Right-click** the app icon and choose **Open**.
3. Click **Open** in the warning dialog.

(Or go to **System Settings → Privacy & Security → Open Anyway**.)

Prefer to build it yourself? See [Build & Run](#-build--run) below.

---

## 📸 Screenshots

| Ready to focus | Focusing | On break |
| :---: | :---: | :---: |
| ![Ready](docs/screenshots/02_ready.png) | ![Focusing](docs/screenshots/01_main.png) | ![Break](docs/screenshots/05_break.png) |

| Achievements wall | Settings |
| :---: | :---: |
| ![Achievements](docs/screenshots/04_achievements.png) | ![Settings](docs/screenshots/03_settings.png) |

---

## ✨ Features

- **Lives in the menu bar** — a status icon plus a live countdown, always one glance away. No extra window cluttering your desktop.
- **Animated dog companion** — a focused pup with a subtle breathing animation while you work, and a relaxed coffee-sipping dog (animated GIF) during breaks.
- **Cycle-based Pomodoro flow** — work and break phases chain automatically and stop once you hit your daily goal, so you can start once and forget about it.
- **Achievement system** — six unlockable achievements rewarding milestones, consistency, deep work, and rest. Each unlock triggers a menu-bar flash, a trophy shake, and a sound.
- **Progress at a glance** — cycle dots show how many rounds you've completed today; the achievement wall shows progress toward the next milestone.
- **Native notifications** — gentle banners when it's time to break, continue, or when you've hit your daily goal.
- **Fully configurable** — focus/break durations, daily cycle goal, and toggles for sound, animation, and notifications.
- **Bilingual** — English and Simplified Chinese, switched automatically by your system language.
- **Onboarding** — a short three-step welcome that sets your daily goal and requests notification permission.
- **Persistent & private** — all stats and settings are stored locally in `UserDefaults`; nothing leaves your machine. The app runs sandboxed.

---

## 🔄 How it works

```
 Stopped (25:00)
     │  Start
     ▼
 Working ──complete──► Break ──complete──► Working ──► … 
     ▲                                                 │
     └──────── cycle goal reached ──► Stopped ◄────────┘
```

- Each **completed** work session increments your total, today's count, your uninterrupted streak, and the cycle counter.
- After a work session the app moves to a **break** automatically; after the break it returns to work — until you reach the **daily cycle goal** (default 4 rounds), at which point it stops and congratulates you.
- **Skipping** a work session still advances the cycle but resets your uninterrupted streak (which the "Deep Worker" achievement depends on).
- Total break time is tracked separately and feeds the "Dance King" achievement.

---

## 🏆 Achievements

| Icon | Name | How to unlock |
| :---: | :--- | :--- |
| 🦴 | **Rookie Pup** | Complete 10 pomodoros |
| 👓 | **Efficient Partner** | Complete 50 pomodoros |
| 👑 | **Focus Master** | Complete 200 pomodoros |
| 🐾 | **Daily Streak** | 3 consecutive days with 4+ pomodoros each |
| 💡 | **Deep Worker** | 3 consecutive pomodoros without skipping |
| ✨ | **Dance King** | Accumulate 300 minutes of break time |

Unlocking an achievement plays a sound, flashes the menu-bar label three times, and shakes the trophy button.

---

## 🛠 Build & Run

**Requirements:** macOS 15.5+, Xcode 16+.

```bash
git clone https://github.com/yvetteL19/PomodoroPup.git
cd PomodoroPup
open PomodoroPup.xcodeproj
```

Then build and run from Xcode (**⌘R**). The app appears in your menu bar — click the icon to open the popup.

Building from the command line:

```bash
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Debug -destination 'platform=macOS' build
```

---

## 🧱 Architecture

The app follows **MVVM** with SwiftUI's `MenuBarExtra` for presentation.

| File | Responsibility |
| :--- | :--- |
| `PomodoroPupApp.swift` | App entry point; configures `MenuBarExtra`, the live menu-bar label (with achievement flash), and the onboarding window. |
| `DogViewModel.swift` | Core logic: the Combine-based timer, state machine, cycle/achievement tracking, `UserDefaults` persistence, sounds, and notifications. |
| `ContentView.swift` | Main popup UI — dog, countdown, cycle dots, controls — plus the achievements wall and settings popovers. |
| `DogView.swift` | The animated dog: breathing focus pose, and the GIF/static rest pose (via an `NSViewRepresentable` GIF player). |
| `SettingsView.swift` | Time settings, companion-mode toggles, and statistics. |
| `OnboardingView.swift` | Three-page first-run welcome flow. |
| `SoundManager.swift` | AVFoundation / system-sound playback. |

**Tech stack:** SwiftUI · Combine · AppKit (GIF rendering & sounds) · UserNotifications · AVFoundation.

---

## 🌐 Localization

UI strings live in `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings` and are resolved through `NSLocalizedString`. The app follows your system language automatically.

---

## 🔒 Privacy

PomodoroPup is fully offline and sandboxed. All counters, streaks, and settings are stored locally via `UserDefaults`. There is no analytics, no account, and no network access.

---

## 📁 Project Structure

```
PomodoroPup/
├── PomodoroPup.xcodeproj/        # Xcode project
├── PomodoroPup/                  # Source
│   ├── PomodoroPupApp.swift
│   ├── DogViewModel.swift
│   ├── ContentView.swift
│   ├── DogView.swift
│   ├── SettingsView.swift
│   ├── OnboardingView.swift
│   ├── SoundManager.swift
│   ├── Assets.xcassets/          # Dog art, achievement icons
│   ├── en.lproj / zh-Hans.lproj  # Localizations
│   └── *.MP3                     # Sound effects
├── docs/screenshots/            # README screenshots
└── README.md
```

---

<p align="center">Made with 🍅 and 🐶 — focus a little, get rewarded a little.</p>
