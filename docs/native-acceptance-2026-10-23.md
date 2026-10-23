# Native acceptance — 2026-10-23

This is a partial acceptance record, not release certification. The tests ran on an Apple Silicon Mac with macOS 15.7.3 and Xcode 16.4. Model checks, native rendering, real window interaction and OS delivery are reported separately.

## Isolation and reproduction

The native app uses the production sources with a separate identity:

| Item | Acceptance value |
| --- | --- |
| Bundle identifier | `com.pomodoropup.acceptance` |
| Product / display name | `PomodoroPupQA` / `PomodoroPup QA` |
| Build | Debug, local ad-hoc signing, App Sandbox enabled |
| App location | `/tmp/PomodoroPup-Acceptance/Build/Products/Debug/PomodoroPupQA.app` |
| Preferences | The separate `com.pomodoropup.acceptance` sandbox container |

Quit any running QA app, then run from the repository root:

```bash
Scripts/build-acceptance-app.sh
```

The script verifies the identity, names, signature and sandbox entitlements before returning the app path. It refuses build-setting overrides or a running QA executable, and does not launch the app, clear preferences or change notification authorization. Xcode may register the built app with LaunchServices. Rebuilding does not update a previously loaded process; quit and relaunch for each new build.

The production identifier remains `Yvette.PomodoroPup`. Neither production application preference file was modified: both the container and non-container files matched their pre-acceptance byte counts and SHA-256 hashes. No production preference values were copied into QA or committed. QA changes were made through the UI; no test fixture replaced its saved state in this run.

## Observed results

| Check | Result and evidence |
| --- | --- |
| Clean launch | A native welcome window appeared automatically; all three presets, optional notifications, Start and Later were available. |
| Preset and first start | Selecting 10 minutes changed the Start text; starting closed welcome and saved a running 600-second focus checkpoint. |
| Permission failure | The real authorization action displayed “Notifications are not allowed for this application.” Focus could still start. This verifies graceful failure, not successful authorization or banner delivery. |
| Settings routing | Command-comma opened an independent native Settings window. Closing with Escape and reopening worked in the initial build. |
| Duration validation | Invalid rest value 999 reverted with a 1–60 range error. Correcting to 1, stepping to 2 while focused, stepping back and reopening preserved 1. |
| Active duration preservation | Changing the future focus duration to one minute kept the existing session’s 600-second phase duration. |
| Normal quit | Command-Q exited the QA process. Before/after checkpoints showed the active work fragment settled and `wasRunning` changed to false, with completed work still zero. |
| Real focus/rest completion | A subsequent QA run persisted exactly one completed focus for 2026-10-23 and 60 seconds of rest. It then saved a full 60-second, non-running work checkpoint with `isWaitingForNextSession = true` and automation off. It did not continue unattended. |
| Production-data comparison | Both known production preference files were byte-for-byte unchanged by hash/size comparison. |

## Defects corrected

- **Duplicate Settings menu entries:** the Settings scene already supplies the native Settings command. Removed the redundant custom command; the independent scene and panel settings action remain.
- **Statistics accessibility grouping:** the native accessibility tree merged five statistics under the first label. Each statistic now has its own label and value, inside a containing group.
- **Misleading feedback at a manual stop boundary:** controlled-clock tests reproduced Pause/Reset announcing a transition that the same action immediately stopped. Those actions now settle silently while persisting completed work, achievements and the daily-goal marker. Four new tests failed before the fix and pass afterward, including rest completion with automation both on and off.

All **80 isolated tests** pass (34 timer-model, 23 storage, 14 notification-service, 9 notification-feedback). Both unsigned Debug and Release app builds pass. The QA build additionally passed local signature and sandbox-entitlement checks. These results do not establish Developer ID signing or notarization.

## Checks still open

- Recheck the corrected native menu and statistics accessibility tree in the rebuilt app; verify Space and clicks inside the main panel, early-end cancellation/confirmation, achievement dismissal and manual rest ending. The automation tool changes focus when binding a windowless menu-bar app, which dismisses its transient panel. A user-opened independent Settings window is needed to resume this tool-driven pass. This limitation does not prove that ordinary in-panel interaction is defective.
- Retry authorization and test reminders after registration. The initial `usernoted` log reported `LSApplicationRecord failed to find com.pomodoropup.acceptance` and failure to validate the QA bundle. Explicit registration later succeeded and the bundle appears in the LaunchServices registry; successful notification delivery has not yet been demonstrated. No conclusion about required signing identity follows from this failure alone.
- Complete quit/relaunch and forced-termination recovery for both work and rest, with direct UI observation before any user resume. The normal-quit checkpoint above alone does not certify this matrix.
- Physical sleep/wake, real midnight/time-zone events, VoiceOver speech, OS Reduce Motion, actual sound, authorized/denied notification recovery, Focus-mode behavior, and clean-Mac installation remain release checks. Controlled-clock tests and prior bilingual/light-dark renders cover related logic/layout, not those physical OS interactions.

Private local evidence (QA checkpoints, production-file hashes and build logs) stays in `/tmp/pomodoropup-acceptance-evidence` and the acceptance DerivedData directory. No new public archive was published. The changes remain in the phase-two draft PR, stacked on the phase-one reliability PR.
