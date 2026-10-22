# Reliability and data preservation

This document describes the first reliability implementation in the current source. It covers timer behavior, local data migration, recovery and validation. It does not describe a newly published release or a complete history of individual focus sessions.

## What is stored

[StateStore.swift](../PomodoroPup/StateStore.swift) stores a JSON-encoded `PersistedState` as `Data` in `UserDefaults` under **`PomodoroPup.state.v1`**. The snapshot has `schemaVersion: 1` and contains:

- Lifetime completed-work count, achievement IDs, consecutive-work count and accumulated rest seconds, including fractions.
- Current batch progress, dated completion totals in `dailyCounts`, historical daily-streak metadata and the last day with a goal notification.
- Focus/rest durations, target count, sound/animation/notification preferences and a fixed reporting time zone.
- An optional current timer checkpoint: phase, remaining time, phase duration, whether it was running when saved, and save time.

This is **daily completion counts plus an active timer checkpoint**. It does not retain individual session IDs, individual start/end times, pause events, tasks or a per-session duration history. Lifetime totals from earlier versions cannot be expanded into missing historical sessions.

`hasCompletedOnboarding` remains a separate legacy preferences key used by onboarding. The local migration backup is in the same preferences store; it is not an independent backup or cloud synchronization service.

## Migration from the original key/value format

When a current snapshot exists, it is authoritative. Legacy values are not merged over it.

When no current snapshot exists, the store first copies all present known legacy keys into **`PomodoroPup.legacyBackup.v1`**, only if that backup does not already exist. It then converts the data and saves a validated v1 snapshot. It never updates or removes the legacy keys and never replaces an existing migration backup. On an empty first launch, it creates a default current snapshot without manufacturing legacy data.

The backup includes the original values of these keys when present:

```
timerState, completedPomodoros, unlockedAchievements, consecutiveDays,
currentStreakPomodoros, totalBreakTime, pomodorosInCycle, todayPomodoros,
lastActiveDate, workDuration, breakDuration, dailyGoal, soundEnabled,
animationEnabled, notificationEnabled, hasCompletedOnboarding
```

Conversion rules:

| Legacy data | Migration behavior |
| --- | --- |
| Lifetime count, consecutive-work count and accumulated rest | Preserve valid values; ordinary negative counters become zero. Unsafe numeric values fail migration with the raw backup and legacy keys retained. |
| Achievement IDs | Preserve all string IDs, including IDs unknown to the current app. |
| Focus/rest durations and target | Use defaults for missing values and constrain supported settings to work 1–120 minutes, rest 1–60 minutes, target 1–20. |
| `todayPomodoros` | Place under the valid `lastActiveDate` in `dailyCounts`, even when that date is earlier than today. With no valid date, retain the raw value in the backup instead of assigning it to today. |
| `consecutiveDays` | Preserve as `legacyStreakCount`, with `legacyStreakEndDay` set to the calendar day before valid `lastActiveDate`. Without a valid date, retain the count but leave its end day unknown. |
| `pomodorosInCycle` | Start the new batch count at zero because the old count included skipped work. Do not change lifetime or valid dated completion totals. |
| `timerState` | Do not restore an active timer. The old format never stored remaining time, so neither remaining work nor offline completions can be reconstructed. |

The backup preserves the data available at migration time. If an earlier version had already overwritten statistics or preferences before this migration, the new store cannot reconstruct the missing values.

## Invalid data and safe stopping

The current snapshot is decoded strictly. Malformed JSON, an unexpected stored type, missing required fields, unsupported `schemaVersion`, and invalid numeric/date/timer values produce an error. No empty fallback snapshot replaces them. Saving also checks an existing snapshot before allowing a replacement, so a failed load cannot be followed by an accidental default-state overwrite.

Validation includes finite, nonnegative rest time; nonnegative counts; valid calendar keys and time zone; supported settings ranges; and a working/resting timer whose remaining time is within its phase duration. Numeric upper bounds reserve arithmetic headroom and prevent conversion/overflow crashes; they are technical safeguards, not a user-facing productivity limit. A stopped state has no active timer checkpoint.

On a read or save failure, [DogViewModel.swift](../PomodoroPup/DogViewModel.swift) stops the timer, exposes a storage error and suppresses normal success feedback. The UI disables timer actions and settings. The saved snapshot, migration backup and original legacy keys stay in place. A save failure can leave the visible in-memory state newer than the last saved state; the error is a stop condition, not evidence that the latest action was persisted.

Investigation should preserve copies of the original data and use an isolated preferences suite or separate test account. Do not delete v1 data or rewrite production preferences to force a fallback migration. There is no in-app data-repair or import workflow in this stage.

## Timing, pause and recovery

[TimerClock.swift](../PomodoroPup/TimerClock.swift) separates wall time from monotonic uptime. Wall time assigns calendar days; uptime measures the amount consumed by a running phase. The Combine timer requests a refresh every second. A late refresh consumes elapsed time rather than subtracting exactly one second.

A refresh can complete **at most one phase**. If a 25-minute work phase is observed late, it is credited once and the rest phase begins with its full duration. The extra delay does not create a series of unattended work/rest completions. The completion is attributed to the computed end boundary, including a boundary before midnight even if the callback arrives after midnight.

Only completed work advances total, daily and batch progress. A skip changes phase without awarding work; paused skips remain paused. Reset clears the current batch and consecutive-work count but retains completed work. Actions first settle a phase that has already reached its deadline, preventing a late Skip click from skipping two phases.

An active phase retains its own duration snapshot when settings change. Starting from the ready state begins a new batch. The main-view dots show today’s completed work, so they are not reset by a new batch. The same configured target currently controls daily goal and batch length; separate settings are outside this stage.

During a running phase, refreshes checkpoint the current state at a nominal one-second cadence. Actions also checkpoint. On normal termination the model settles the active fragment and pauses before saving. A crash or interruption can lose the fragment since the last successfully persisted checkpoint; delayed callbacks and `UserDefaults` persistence mean this is not a strict one-second durability guarantee.

On restart, a valid active checkpoint always restores **paused**, even if `wasRunning` was true. The user must select Resume. `savedAt` is not used to award offline work or rest. Sleep handling settles the current fragment and pauses; wake remains paused and does not add the sleeping interval. If a wake arrives without a preceding sleep callback, the model conservatively stops without awarding the gap. These lifecycle rules have automated model coverage; actual system sleep delivery remains a manual check below.

## Daily totals and legacy streaks

The model uses a Gregorian calendar and a time zone fixed when the current storage is first created or migrated. That identifier is persisted. A later system time-zone change does not rewrite historical day assignments. This version does not expose a setting to change the reporting time zone.

Each completed work phase increases the count for its completion day. Popup activation, running refreshes and calendar-day notifications update today’s display. Crossing midnight does not clear lifetime or batch progress, and the first completion after midnight is retained.

The daily-streak achievement continues to require **at least four completions each day**, regardless of the configurable target. The model derives the current streak from `dailyCounts`, using the legacy streak endpoint/count to preserve older continuity that cannot be reconstructed into dated records. Completing the fourth session on the third consecutive qualifying day can unlock the badge immediately. A missed day breaks continuity. Rest achievements are reevaluated during rest updates.

## Tests and builds

Use macOS with Xcode 16.4+ selected as the active developer tools. From the repository root:

```bash
swift test
```

[Package.swift](../Package.swift) exposes the production model, store, clock and sound manager to the test target. Tests use unique `UserDefaults` suites; model tests inject a clock and suppress audio/notifications. Most disable automatic subscriptions; observer integration tests may enable them and post synthetic lifecycle notifications without sleeping the Mac. They do not launch the real menu bar app or modify its preferences.

Coverage includes persistence migration and round trips, invalid/unsupported snapshots, paused recovery, skips, resets, delayed callbacks, zero-time completion, midnight attribution, clock adjustments, daily streaks, batch restart, duration changes, and simulated sleep/wake methods.

Build both application configurations without signing:

```bash
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/PomodoroPup-Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/PomodoroPup-Release CODE_SIGNING_ALLOWED=NO build
```

[CI](../.github/workflows/ci.yml) defines these tests and builds. A local build or test run does not establish that hosted CI has run successfully. These commands also do not sign, notarize, distribute or launch an app.

## Manual checks not yet performed

The following are release-validation tasks, **not completed checks** for this implementation. Use an isolated test environment so real user data is not changed.

- **Actual Mac sleep and wake:** test active work, active rest and an already paused phase; close the lid or sleep the system, wake later, and confirm paused state, stable totals and explicit Resume. Repeat near a phase deadline.
- **Normal quit and unexpected termination:** restart an isolated build during both work and rest; inspect restored phase, duration, remaining time and unchanged offline statistics. Distinguish the last saved checkpoint from the exact instant of a forced stop.
- **Native notification delivery:** test authorized, denied and not-yet-requested permission; app foreground/background; OS Focus mode; actual completion, rest transition and daily target. Check dynamic rest duration and confirm no success alert from pure skips.
- **Sound behavior:** with app sound disabled and notifications enabled, verify actual native notification and app audio are silent; with sound enabled, check that phase and achievement sounds do not create an excessive combined alert.
- **Permission recovery:** onboarding Skip and system denial still need a usable manual recovery path; the settings toggle currently does not expose OS permission status or a system-settings shortcut.
- **Calendar events and UI:** keep the isolated app open across midnight while idle, working and resting; check today’s dots and settings counts. Verify behavior after a system time-zone change against the stored reporting zone.
- **Accessibility and visuals:** verify VoiceOver’s pause/status/progress labels, Reduce Motion, animation toggle, paused static dog, text clipping, and light/dark appearance. Source-level labels and animation guards do not replace visual inspection.
- **Distribution:** validate signing, notarization, Gatekeeper behavior and installation/update behavior on a clean Mac before publishing a new archive. Existing download links still point to the original 1.0 release.
