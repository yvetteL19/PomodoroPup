# CLAUDE.md

This file describes the current implementation for agents working in this repository. Treat the source and tests as authoritative when behavior changes.

## Project and commands

PomodoroPup is an offline, sandboxed macOS menu bar Pomodoro timer written in SwiftUI. A dog switches between work and rest poses, and an achievement wall displays earned badges. The current dog view does not wear achievement items.

The repository root contains `PomodoroPup.xcodeproj`, `Package.swift`, `PomodoroPup/`, and `Tests/`. Use macOS 15.5+ and Xcode 16.4+.

```bash
open PomodoroPup.xcodeproj
swift test
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/PomodoroPup-Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/PomodoroPup-Release CODE_SIGNING_ALLOWED=NO build
```

These unsigned builds validate compilation; they do not create a signed or notarized release. The [CI workflow](.github/workflows/ci.yml) runs model/storage tests and both configurations. The existing downloadable 1.0 archive is a historical release, not a rebuild of the current source.

## File responsibilities

| File | Responsibility |
| --- | --- |
| `PomodoroPup/PomodoroPupApp.swift` | Shared `DogViewModel`, `MenuBarExtra`, onboarding window, menu-bar phase/pause display and achievement flash, foreground notification delegate. |
| `PomodoroPup/DogViewModel.swift` | Phase transitions, elapsed-time settlement, daily and batch counts, achievements, lifecycle handling, snapshots, and feedback after successful persistence. |
| `PomodoroPup/TimerClock.swift` | `TimerClock` protocol and `SystemTimerClock`; wall time assigns dates, monotonic uptime measures running phases. |
| `PomodoroPup/StateStore.swift` | Codable state/timer values, strict snapshot validation, one-time legacy backup and migration. |
| `PomodoroPup/ContentView.swift` | Popup, today’s completed-work dots, controls, recovery/storage-error feedback, achievement wall and settings popovers. |
| `PomodoroPup/DogView.swift` | Work image with optional breathing animation; rest GIF or static image. Pausing, the animation setting, and Reduce Motion control animation. |
| `PomodoroPup/SettingsView.swift` | Focus duration, break duration, target count, effects toggles and current statistics. |
| `PomodoroPup/OnboardingView.swift` | Three-page introduction; target selection and optional notification authorization. |
| `PomodoroPup/SoundManager.swift` | System `Glass` sound for phase transitions; bundled achievement audio. |
| `Tests/PomodoroPupCoreTests/` | Production-model tests using an injected clock and isolated preferences; direct storage migration and validation tests. |

## Timer and product rules

`TimerState` has exactly three cases: `.stopped`, `.working`, `.onBreak`. Pause is represented by an active phase with `isTimerRunning == false`. There are no separate short/long-break phases, configurable long breaks, or separate break-tracking timer.

- Starting from `.stopped` clears the batch count and begins a work phase. Resuming retains the same phase duration and remaining time.
- Completed work increments lifetime completions, `dailyCounts[completionDay]`, the consecutive-work count, and the batch count. Skipped work increments none of these and clears the consecutive-work count.
- Work transitions to rest. Rest transitions to work unless the batch has completed `dailyGoal` work sessions, in which case it stops.
- `dailyGoal` currently serves both as the daily target and the batch length; these are not separate settings. UI dots show `todayPomodoros`, not `pomodorosInCycle`.
- Skipping a paused phase leaves the next phase paused. Reset clears the unfinished phase, batch, and consecutive-work count while retaining completed statistics and achievements.
- Actions first settle elapsed time. A click after a phase deadline completes that old phase; Skip does not then also skip the newly entered phase.
- Changing durations affects future phases. An active or paused phase retains `phaseDuration` and `remainingTime`.
- Combine’s one-second timer requests a refresh. `TimerClock.uptime` determines elapsed time; callback count is not the clock. A refresh settles at most one phase and does not invent later completed phases during a long delay.
- Rest uses the same elapsed-time path, retaining fractional seconds in the snapshot. The published statistic displays whole seconds.

All model mutations run on the main run loop. Model tests normally set `automaticTicks: false`; observer integration tests may enable it and post synthetic lifecycle notifications without sleeping the Mac. Tests always isolate preferences and disable effects. Preserve that isolation when adding coverage.

## Persistence and recovery

`PersistedState` is a versioned JSON snapshot under `PomodoroPup.state.v1`. It contains settings, achievements, daily completion counts, batch/consecutive counters, historical streak metadata, and an optional active timer checkpoint. It is not a full session ledger: there are no individual session records, task labels, or duration history.

`StateStore` reads the snapshot into a value before the model assigns observable properties. Do not reintroduce full-state writes from statistic `didSet` observers during loading. `settingsChanged()` is guarded while loading; normal changes use `update` and then persist once. Feedback is emitted only after persistence succeeds.

When no current snapshot exists, legacy values are copied once to `PomodoroPup.legacyBackup.v1`, then converted. Legacy keys remain unchanged, including `hasCompletedOnboarding`, which onboarding still uses. Unknown achievement IDs survive migration. Legacy batch progress is reset because it included skips; lifetime and dated completed-work counts are preserved. The old format did not save remaining time, so it cannot supply a recovered timer.

Malformed, unsupported-version, or invalid-range current snapshots must throw and remain untouched. The model stops, shows a storage error, disables timer actions/settings, and does not replace the data with defaults. Preserve the backup and original values when investigating; do not use destructive defaults-reset commands as a normal repair step.

Running phases are checkpointed on the nominal one-second refresh and on actions. Restart always restores an active checkpoint paused, even if `wasRunning` is true. Sleep settles the active fragment and pauses; wake remains paused. Normal termination requests the same pause/checkpoint path. Offline/sleep time is never retrospectively awarded. A crash may lose time since the last successfully persisted checkpoint; no exact one-second durability guarantee is made.

## Calendar and achievements

The model uses a Gregorian calendar and the time zone saved at initial storage creation or migration. Later changes to the system time zone do not reassign old days. A delayed completion is assigned to the phase’s computed completion boundary, not simply the refresh callback’s day. Refreshing on popup activation and calendar-day changes updates today’s display without clearing batch or lifetime progress.

Daily streaks require at least four completed sessions per day, independently of the configured target. During migration, old `consecutiveDays` is kept as `legacyStreakCount`, ending on the day before old `lastActiveDate`; old `todayPomodoros` belongs to `lastActiveDate`. Missing/invalid dates remain available in the raw backup rather than being invented as today’s work.

| Achievement ID | Condition |
| --- | --- |
| `icon_bone` | 10 lifetime completed sessions |
| `icon_glasses` | 50 lifetime completed sessions |
| `icon_crown` | 200 lifetime completed sessions |
| `icon_paw` | Three consecutive days with at least four completions each |
| `icon_bulb` | Three consecutive completed sessions without skipping work or resetting |
| `icon_party` | 300 minutes of accumulated running rest |

Achievements are reevaluated after model updates, including rest refreshes. The set prevents duplicate unlocks. Recovery/load reevaluation is silent. `debugUnlockAll()` exists only in Debug builds; there is no debug-unlock button in the current UI.

## Notifications, assets and localization

Natural phase transitions can play the system `Glass` sound and send an immediate local notification. The rest message uses the configured rest duration. Goal notification checks actual completed work and is limited by `lastGoalNotificationDay`; skipped work alone cannot trigger it. Notification content has no sound when `soundEnabled` is false. OS authorization and system settings still determine actual delivery.

Notification permission is requested by onboarding. The current settings toggle does not display OS authorization status or provide a system-settings shortcut; do not describe that as implemented.

Assets actually used by `DogView` are `dog_work`, `dog_rest` (GIF data asset), and `dog_rest_static`. Badge assets are displayed in the achievement wall. The bundle also contains `achievement.MP3`, `bark.MP3`, and `sigh.MP3`; current phase transitions use the system sound rather than the latter two files. There are no sparkle, jump, collar-adjustment, or cosmetic-overlay effects in the current view.

User-facing strings are in `PomodoroPup/en.lproj/Localizable.strings` and `PomodoroPup/zh-Hans.lproj/Localizable.strings`; update both when adding UI text. Animated dog, trophy and menu-bar feedback respect the animation setting and Reduce Motion.

## Verification boundary

Use [docs/reliability.md](docs/reliability.md) for data contracts, commands, and the manual validation checklist. Automated tests must use a unique `UserDefaults` suite and disable real notifications/audio. They exercise model lifecycle methods, not actual Mac sleep, native notification delivery, accessibility rendering, or release signing. Do not claim those manual checks have passed without performing them in an isolated test environment.
