# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PomodoroPup is a macOS menu bar Pomodoro timer app with a gamified dog companion. The app is written in SwiftUI and features an achievement system where the dog earns cosmetic items as the user completes focus sessions.

## Building and Running

**Build/Run:**
```bash
open /Users/yiwei/Desktop/PomodoroPup/PomodoroPup.xcodeproj
```
Then use Xcode's standard build (⌘B) and run (⌘R) commands.

**Project location:** The Xcode project file is in the parent directory (`../PomodoroPup.xcodeproj`), while source code is in `PomodoroPup/`.

## Architecture

### App Structure

The app follows MVVM architecture with a MenuBarExtra presentation:

- **PomodoroPupApp.swift**: Entry point. Configures the menu bar extra with:
  - MenuBarLabel: Dynamic status icon (stopped/working/break) + countdown timer with flash effect on achievement unlock
  - Content: ContentView popup window
  - Global `@StateObject` DogViewModel shared via `@EnvironmentObject`

- **DogViewModel.swift**: Core business logic
  - Timer management (Combine-based timer)
  - State machine: `.stopped` → `.working` → (`.shortBreak` or `.longBreak`) → `.stopped`
  - Long break triggers every N pomodoros (default 4, configurable)
  - Achievement tracking and unlock logic with daily reset
  - Sound effect triggers (with toggle)
  - UserDefaults persistence for all state and stats
  - Break time tracking with separate timer

- **ContentView.swift**: Main UI popup
  - Dog display, timer, and controls
  - Settings button (gear icon) and achievement wall button (trophy)
  - Reset button (appears during work state)
  - Achievement wall popover (AchievementView) with progress bar
  - Settings popover (SettingsView)
  - Debug unlock button for testing

- **DogView.swift**: Animated dog character
  - Shows "dog_dance" during breaks (dancing animation with rotation and offset)
  - Shows "dog_focus" during work/stopped (breathing animation when working)
  - Transition animations:
    - Jump animation (work→break): Quick scale-up effect
    - Collar adjustment animation (break→work): Down-press gesture
  - SparkleEffect: Yellow particles burst on achievement unlock
  - Overlays achievement cosmetics (glasses, crown, bone, bulb, party crown) on the focus dog

- **SettingsView.swift**: Configuration panel
  - Time settings: Work duration, short/long break durations, long break interval
  - Companion mode: Sound and animation toggles
  - Statistics display: Total/today pomodoros, consecutive days, streak, total break time

- **SoundManager.swift**: Audio playback singleton
  - Plays MP3/WAV files: `bark.mp3` (work complete), `sigh.mp3` (break complete), `achievement.mp3` (unlock)
  - Respects soundEnabled setting

### State Flow

```
Stopped (25:00) → [Start] → Working (25:00 countdown) → [Complete] →
  ↓
  ├─ Short Break (5:00) [if pomodorosInCycle < 4] → [Complete] → Stopped
  └─ Long Break (15:00) [if pomodorosInCycle >= 4] → [Complete] → Stopped (cycle resets)
```

Each work completion:
- Increments `completedPomodoros`, `todayPomodoros`, `currentStreakPomodoros`, `pomodorosInCycle`
- Triggers achievement checks
- Plays bark sound and triggers jump animation
- Starts break time tracking timer

Each break completion:
- Stops break time tracking
- Plays sigh sound and triggers collar adjustment animation
- Returns to stopped state

Skip during work:
- Resets `currentStreakPomodoros` to 0 (breaks deep work achievement)

### Achievement System

Achievements are defined in `AchievementType` enum with thresholds:
- `icon_bone` (萌新小狗): 10 pomodoros
- `icon_glasses` (高效搭档): 50 pomodoros
- `icon_crown` (专注大师): 200 pomodoros
- `icon_paw` (连续出勤): 3 consecutive days with 4+ pomodoros/day
- `icon_bulb` (深度黑客): 3 consecutive uninterrupted pomodoros (no skips)
- `icon_party` (舞蹈之王): 300 minutes of break time

**Daily Reset Logic:**
- On launch, `checkDailyReset()` compares `lastActiveDate` with today
- If yesterday had 4+ pomodoros and dates are consecutive → increment `consecutiveDays`
- Otherwise → reset `consecutiveDays` to 0
- `todayPomodoros` resets to 0 each day

**Achievement Unlocking:**
- Triggers sparkle animation (SparkleEffect), menu bar flash (3 times), and achievement sound
- Stored in `unlockedAchievements` Set, persisted to UserDefaults
- Displayed as cosmetic overlays on dog (during work/stopped) and in achievement wall grid

### Asset Structure

All assets are in `Assets.xcassets/`:
- Dog images: `dog_focus`, `dog_dance`
- Achievement icons: `icon_bone`, `icon_glasses`, `icon_crown`, `icon_bulb`, `icon_paw`, `icon_party`, `icon_stopped`, `icon_break`
- Audio: `bark.MP3`, `sigh.MP3`, `achievement.MP3` (in project root, not in xcassets)

Custom icons use `.renderingMode(.template)` for automatic dark/light mode adaptation.

## Key Implementation Details

### Menu Bar Icon Logic
The menu bar label dynamically switches between three states:
- Stopped: `icon_stopped` (custom)
- Working: `pawprint.fill` (SF Symbol)
- Break: `icon_break` (custom)

All custom icons must be set to template rendering mode to adapt to macOS appearance.

### Timer Implementation
Uses Combine's `Timer.publish()` in DogViewModel, not SwiftUI's `onReceive`. The timer:
- Decrements `remainingTime` every second
- Calls `completePhase()` at zero
- Can be paused/resumed via `pauseTimer()`/`startTimer()`

### Localization
UI text is in Chinese (开始专注, 暂停, 跳过, etc.). Achievement names and descriptions are also in Chinese.

## Data Persistence

All user data is persisted to UserDefaults:
- Timer state and pomodoro counts
- Unlocked achievements set
- Tracking variables: consecutiveDays, currentStreakPomodoros, totalBreakTime, pomodorosInCycle
- Today's pomodoro count and last active date
- User settings: durations, intervals, sound/animation toggles

Data is saved automatically via `didSet` observers on `@Published` properties.

## Testing Notes

- **Debug unlock**: The hammer icon button in ContentView calls `vm.debugUnlockAll()` to unlock all achievements for UI testing
- **Settings defaults**: Work 25min, short break 5min, long break 15min, interval 4 pomodoros
- No unit tests are currently implemented

## Animation Details

All animations respect the `animationEnabled` setting:

1. **Breathing animation** (work state): dog_focus scales between 0.98-1.02 with 2s easing
2. **Dancing animation** (break state): dog_dance oscillates horizontally ±8px with ±3° rotation, 0.35s duration
3. **Jump animation** (work→break): Scale to 1.15 in 0.1s, applied to dog_dance
4. **Collar adjustment** (break→work): Vertical offset -8px for 0.15s on dog_focus and all cosmetics
5. **Sparkle effect** (achievement unlock): 8 yellow circles radiate outward with fading opacity over 1.5s
6. **Menu bar flash** (achievement unlock): Opacity toggles between 1.0-0.3 six times (3 full flashes) at 0.15s intervals
