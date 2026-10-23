# Phase two: a complete focus and rest experience

This stage builds on the reliability changes. It keeps the native menu bar app, offline storage and existing dog artwork. It does not introduce payments, accounts, a session-history database or wearable pet items.

## Product rules

| Situation | Main action | Result |
| --- | --- | --- |
| First launch | Choose 10, 25 or 45 minutes and start | Begin the first focus session; notifications remain optional. |
| Ready | Start focus | Start the configured duration. |
| Working or resting | Pause | Settle elapsed time, then stop counting. |
| Paused | Resume | Continue the same duration and remaining time. |
| Rest finished | Start next focus | Wait without accruing time until the user starts. |
| Daily goal reached | Continue when ready | Keep the achievement feedback; the daily target does not limit future sessions. |
| Unfinished focus | End through the secondary menu | Explain that this does not add a completed session; preserve existing completed statistics. |
| Interrupted or restarted | Resume recovered phase | Preserve the first-stage recovery rules. A waiting phase remains waiting. |

Automatically starting the next focus is an explicit, default-off setting. It applies to a naturally completed running break. Manually ending a break always waits, even when automation is enabled. Switching automation on does not start a waiting timer. Sleep, restart and paused skips cannot start an unattended timer.

The daily goal is now only a progress target. The internal batch counter is retained for compatibility and statistics, but it no longer stops the timer at that target. Goal feedback is emitted once per completion day, when a completed focus reaches the daily target. Skips cannot earn it.

Changing a duration applies to future phases, including a not-yet-started waiting focus. Running and paused phases retain their original duration. The app still stores completion counts rather than individual focus intervals, so ending early does **not** claim to save partial focus minutes or offer session undo.

## Compatibility

The snapshot remains version 1. Two optional fields extend it: `autoStartNextSession` and `isWaitingForNextSession`. Missing values from the first-stage format mean false; existing required fields still decode strictly. Waiting is represented by a full-duration, non-running work checkpoint. Invalid waiting checkpoints are rejected without overwriting the original data.

Lifetime totals, dated completion counts, achievements, settings, current checkpoints, the legacy migration backup and the existing onboarding-completion preference remain supported. There is no reset of production preferences. See [reliability.md](reliability.md) for migration and timing guarantees.

## Notification and Mac integration

The notification preference and macOS permission are separate. Settings displays the current system authorization and whether alerts are enabled, offers authorization when it has not yet been requested, and opens System Settings for recovery. A test reminder reports whether it was submitted; this is not proof that macOS displayed a banner. Focus modes and system delivery policies can still suppress delivery.

Settings has its own window. The main panel has explicit settings and quit entries, a primary action with a Space shortcut while the panel has focus, and standard Command-comma / Command-Q actions. These are app shortcuts, not system-wide hotkeys. No Accessibility permission is requested for global key monitoring.

Interface surfaces use semantic system colors. A light illustration plate protects the existing dark line artwork in dark appearance. Progress includes a text count; achievement descriptions are readable without two-line truncation. Dog animation stops while paused or waiting. Dog, trophy and menu bar effects respect the animation preference and Reduce Motion.

## Validation

The implementation passed 76 isolated automated tests and native view rendering checks for English/Chinese, light/dark appearance, and ready, paused, rest, waiting, welcome, settings and achievement layouts. The checked view renders do not exercise production window routing or real OS permissions. Selected previews are stored in `docs/screenshots/phase-two-*.png`.

Automated coverage extends the isolated first-stage tests with old-v1 compatibility, waiting and restart, opt-in automation, manual rest endings, daily targets, and notification authorization/delivery behavior using a fake notification client. No test requests real system notification permission or changes the real app's preferences.

Before a public release, validate these native interactions in an isolated app environment:

- A clean launch presents the welcome screen; later launches do not repeat it after completion. Starting closes welcome and leaves the menu bar timer discoverable.
- Start, pause, resume, early end, rest end and next focus work with mouse and keyboard; settings and quit are reachable. Closing settings returns naturally to the menu bar workflow.
- Chinese and English layouts work in light/dark appearance, with VoiceOver, keyboard navigation and Reduce Motion.
- Permission states update after returning from System Settings. Denied permission does not block focus. Test reminders and phase notifications respect app sound and notification preferences.
- Actual sleep/wake, quit/relaunch and midnight behavior still pass the first-stage manual checklist.

Unsigned Debug/Release compilation and model tests do not certify native window routing, VoiceOver speech, OS notification delivery, signing or notarization. The historical 1.0 download is unchanged until a separate release is built and published.
