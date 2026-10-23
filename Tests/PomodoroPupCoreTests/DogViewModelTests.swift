import Foundation
import AppKit
import XCTest
@testable import PomodoroPupCore

@MainActor
final class DogViewModelTests: XCTestCase {
    func testLegacyStatisticsSettingsAndAchievementsSurviveInitialization() async {
        let fixture = Fixture(legacy: [
            "timerState": "stopped",
            "completedPomodoros": 52,
            "unlockedAchievements": ["icon_bone", "icon_glasses"],
            "currentStreakPomodoros": 2,
            "totalBreakTime": 900,
            "pomodorosInCycle": 2,
            "todayPomodoros": 3,
            "lastActiveDate": "2026-10-22",
            "workDuration": 1800.0,
            "breakDuration": 600.0,
            "dailyGoal": 6,
            "soundEnabled": false,
            "animationEnabled": false,
            "notificationEnabled": false
        ])
        let model = fixture.model

        XCTAssertEqual(model.completedPomodoros, 52)
        XCTAssertEqual(model.unlockedAchievements, ["icon_bone", "icon_glasses"])
        XCTAssertEqual(model.currentStreakPomodoros, 2)
        XCTAssertEqual(model.totalBreakTime, 900)
        XCTAssertEqual(model.todayPomodoros, 3)
        XCTAssertEqual(model.workDuration, 1800)
        XCTAssertEqual(model.breakDuration, 600)
        XCTAssertEqual(model.dailyGoal, 6)
        XCTAssertFalse(model.soundEnabled)
        XCTAssertFalse(model.animationEnabled)
        XCTAssertFalse(model.notificationEnabled)

        let restored = fixture.reopen()
        XCTAssertEqual(restored.completedPomodoros, 52)
        XCTAssertEqual(restored.todayPomodoros, 3)
        XCTAssertEqual(restored.unlockedAchievements, model.unlockedAchievements)
        XCTAssertEqual(restored.workDuration, 1800)
        XCTAssertFalse(restored.notificationEnabled)
    }

    func testRestartRestoresRemainingWorkPausedWithoutCountingOfflineTime() async {
        let fixture = Fixture()
        fixture.model.workDuration = 60
        fixture.model.startTimer()
        fixture.clock.advance(12.25)
        fixture.model.prepareForTermination()
        fixture.clock.advance(86_400)

        let restored = fixture.reopen()
        XCTAssertEqual(restored.timerState, .working)
        XCTAssertFalse(restored.isTimerRunning)
        XCTAssertEqual(restored.remainingTime, 47.75, accuracy: 0.0001)
        XCTAssertEqual(restored.completedPomodoros, 0)
        fixture.clock.advance(100)
        restored.refresh()
        XCTAssertEqual(restored.remainingTime, 47.75, accuracy: 0.0001)
        restored.startTimer()
        fixture.clock.advance(47.75)
        restored.refresh()
        XCTAssertEqual(restored.completedPomodoros, 1)
        XCTAssertEqual(restored.timerState, .onBreak)
    }

    func testPreviouslyRunningSnapshotRecoversPausedAfterUnexpectedExit() async throws {
        let fixture = Fixture()
        var state = PersistedState()
        state.timeZoneIdentifier = fixture.calendar.timeZone.identifier
        state.completedPomodoros = 23
        state.dailyCounts = ["2026-10-22": 2]
        state.unlockedAchievements = [AchievementType.novice.rawValue]
        state.timer = PersistedTimer(
            phase: .working,
            remainingTime: 100.25,
            phaseDuration: 1500,
            wasRunning: true,
            savedAt: fixture.clock.now
        )
        try StateStore(defaults: fixture.defaults).save(state)
        fixture.clock.advance(3600)

        let restored = fixture.reopen()
        XCTAssertEqual(restored.timerState, .working)
        XCTAssertFalse(restored.isTimerRunning)
        XCTAssertEqual(restored.remainingTime, 100.25, accuracy: 0.0001)
        XCTAssertEqual(restored.completedPomodoros, 23)
        XCTAssertEqual(restored.todayPomodoros, 2)
        XCTAssertTrue(restored.unlockedAchievements.contains(AchievementType.novice.rawValue))
    }

    func testPausedBreakSurvivesRestartIncludingFractionalTime() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        completeWork(fixture)
        fixture.clock.advance(0.6)
        fixture.model.pauseTimer()
        fixture.model.prepareForTermination()
        fixture.clock.advance(3600)

        let restored = fixture.reopen()
        XCTAssertEqual(restored.timerState, .onBreak)
        XCTAssertFalse(restored.isTimerRunning)
        XCTAssertEqual(restored.remainingTime, 59.4, accuracy: 0.0001)
        XCTAssertEqual(restored.totalBreakTime, 0)

        restored.startTimer()
        fixture.clock.advance(0.5)
        restored.pauseTimer()
        XCTAssertEqual(restored.totalBreakTime, 1)
        XCTAssertEqual(restored.remainingTime, 58.9, accuracy: 0.0001)
        fixture.clock.advance(600)
        restored.refresh()
        XCTAssertEqual(restored.totalBreakTime, 1)
        XCTAssertEqual(restored.remainingTime, 58.9, accuracy: 0.0001)
    }

    func testSkippedWorkDoesNotCountAsCompletionOrBatchProgress() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(10)
        fixture.model.skipPhase()

        XCTAssertEqual(fixture.model.timerState, .onBreak)
        XCTAssertTrue(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.completedPomodoros, 0)
        XCTAssertEqual(fixture.model.todayPomodoros, 0)
        XCTAssertEqual(fixture.model.pomodorosInCycle, 0)
        XCTAssertEqual(fixture.model.currentStreakPomodoros, 0)
        XCTAssertEqual(fixture.model.remainingTime, 60)
    }

    func testSkipAtNaturalDeadlineCompletesOldPhaseWithoutSkippingNewPhase() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(60)
        fixture.model.skipPhase()

        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.pomodorosInCycle, 1)
        XCTAssertEqual(fixture.model.timerState, .onBreak)
        XCTAssertTrue(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertEqual(fixture.model.totalBreakTime, 0)
    }

    func testCorruptSnapshotPreventsTimerActionsAndPreservesOriginalData() async {
        let raw = Data("unreadable existing snapshot".utf8)
        let fixture = Fixture(legacy: [StateStore.snapshotKey: raw])
        XCTAssertNotNil(fixture.model.storageError)

        fixture.model.startTimer()
        fixture.clock.advance(3600)
        fixture.model.refresh()
        fixture.model.skipPhase()
        fixture.model.pauseTimer()
        fixture.model.resetTimer()
        fixture.model.workDuration = 60
        fixture.model.prepareForTermination()

        XCTAssertEqual(fixture.model.timerState, .stopped)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.completedPomodoros, 0)
        XCTAssertNotNil(fixture.model.storageError)
        XCTAssertEqual(fixture.defaults.data(forKey: StateStore.snapshotKey), raw)
    }

    func testSkippingPausedPhasesNeverStartsHiddenTimerOrBreakTracking() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.model.pauseTimer()
        fixture.model.skipPhase()
        XCTAssertEqual(fixture.model.timerState, .onBreak)
        XCTAssertFalse(fixture.model.isTimerRunning)

        fixture.clock.advance(600)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertEqual(fixture.model.totalBreakTime, 0)
        fixture.model.skipPhase()
        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertFalse(fixture.model.isTimerRunning)
        fixture.clock.advance(600)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertEqual(fixture.model.completedPomodoros, 0)
    }

    func testDelayedTickConsumesElapsedTimeAndAdvancesOnlyOnePhase() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(11.5)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 48.5, accuracy: 0.0001)

        fixture.clock.advance(1000)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.timerState, .onBreak)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertEqual(fixture.model.totalBreakTime, 0)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.remainingTime, 60)
    }

    func testReachingExactlyZeroCompletesWithoutAnExtraTick() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(60)
        fixture.model.refresh()

        XCTAssertEqual(fixture.model.timerState, .onBreak)
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        fixture.clock.advance(60)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertEqual(fixture.model.totalBreakTime, 60)
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
    }

    func testFirstCompletionAfterMidnightBelongsToNewDay() async {
        let fixture = Fixture(now: date("2026-10-21T23:59:30Z"))
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(60)
        fixture.model.refresh()

        XCTAssertEqual(fixture.model.todayPomodoros, 1)
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.lastActiveDate, "2026-10-22")
        XCTAssertEqual(fixture.model.pomodorosInCycle, 1)
    }

    func testDelayedCompletionUsesDeadlineDayRatherThanCallbackDay() async {
        let fixture = Fixture(now: date("2026-10-21T23:58:30Z"))
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(120)
        fixture.model.refresh()

        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.todayPomodoros, 0)
        XCTAssertEqual(fixture.model.lastActiveDate, "2026-10-22")
        fixture.model.skipPhase()
        fixture.model.startTimer()
        fixture.clock.advance(60)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.todayPomodoros, 1)
        XCTAssertEqual(fixture.model.completedPomodoros, 2)
    }

    func testIdleDateChangeClearsTodayWithoutResettingLifetimeOrBatch() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        completeWork(fixture)
        fixture.model.pauseTimer()
        fixture.clock.advance(86_400)
        fixture.model.refresh()

        XCTAssertEqual(fixture.model.todayPomodoros, 0)
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.pomodorosInCycle, 1)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertFalse(fixture.model.isTimerRunning)
    }

    func testHabitUnlocksOnFourthCompletionOfThirdConsecutiveDay() async {
        let fixture = Fixture(now: date("2026-10-20T12:00:00Z"))
        fixture.useShortDurations()
        for day in 20...22 {
            fixture.clock.move(to: date("2026-10-\(day)T12:00:00Z"))
            fixture.model.refresh()
            for round in 1...4 {
                completeWork(fixture)
                if day < 22 || round < 4 {
                    XCTAssertFalse(fixture.model.unlockedAchievements.contains(AchievementType.habit.rawValue))
                }
                if day == 22 && round == 4 {
                    XCTAssertEqual(fixture.model.consecutiveDays, 3)
                    XCTAssertTrue(fixture.model.unlockedAchievements.contains(AchievementType.habit.rawValue))
                }
                finishBreak(fixture)
            }
        }
        XCTAssertEqual(fixture.model.completedPomodoros, 12)
        XCTAssertEqual(fixture.model.todayPomodoros, 4)
    }

    func testMissedDayBreaksConsecutiveDayCount() async {
        let fixture = Fixture(now: date("2026-10-20T12:00:00Z"))
        fixture.useShortDurations()
        for _ in 0..<4 {
            completeWork(fixture)
            finishBreak(fixture)
        }
        XCTAssertEqual(fixture.model.consecutiveDays, 1)
        fixture.clock.move(to: date("2026-10-22T12:00:00Z"))
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.consecutiveDays, 0)
        for _ in 0..<4 {
            completeWork(fixture)
            finishBreak(fixture)
        }
        XCTAssertEqual(fixture.model.consecutiveDays, 1)
        XCTAssertFalse(fixture.model.unlockedAchievements.contains(AchievementType.habit.rawValue))
    }

    func testResetBreaksConsecutiveWorkStreak() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        for _ in 0..<2 {
            completeWork(fixture)
            finishBreak(fixture)
        }
        XCTAssertEqual(fixture.model.currentStreakPomodoros, 2)
        fixture.clock.advance(10)
        fixture.model.resetTimer()
        XCTAssertEqual(fixture.model.currentStreakPomodoros, 0)
        XCTAssertEqual(fixture.model.timerState, .stopped)
        XCTAssertFalse(fixture.model.isTimerRunning)
        completeWork(fixture)
        XCTAssertEqual(fixture.model.currentStreakPomodoros, 1)
        XCTAssertFalse(fixture.model.unlockedAchievements.contains(AchievementType.deepWork.rawValue))
        XCTAssertEqual(fixture.model.completedPomodoros, 3)
    }

    func testWallClockChangesDoNotChangeCountdown() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(10)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 50)

        fixture.clock.now.addTimeInterval(3600)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 50)
        fixture.clock.now.addTimeInterval(-7200)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 50)
        fixture.clock.advance(10)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 40)
        XCTAssertEqual(fixture.model.completedPomodoros, 0)
    }

    func testReachingDailyGoalKeepsNextSessionAvailableWithoutClearingProgress() async throws {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.dailyGoal = 1
        completeWork(fixture)
        let completed = try StateStore(defaults: fixture.defaults).load(now: fixture.clock.now, calendar: fixture.calendar)
        XCTAssertEqual(completed.lastGoalNotificationDay, "2026-10-22")
        XCTAssertEqual(fixture.model.timerState, .onBreak)
        finishBreak(fixture)
        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.pomodorosInCycle, 1)
        XCTAssertEqual(fixture.model.todayPomodoros, 1)

        fixture.model.startTimer()
        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertFalse(fixture.model.isWaitingForNextSession)
        XCTAssertEqual(fixture.model.pomodorosInCycle, 1)
        XCTAssertEqual(fixture.model.todayPomodoros, 1)
        fixture.clock.advance(60)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.pomodorosInCycle, 2)
        XCTAssertEqual(fixture.model.todayPomodoros, 2)
        let continued = try StateStore(defaults: fixture.defaults).load(now: fixture.clock.now, calendar: fixture.calendar)
        XCTAssertEqual(continued.lastGoalNotificationDay, "2026-10-22")
    }

    func testChangingDurationDoesNotReplacePausedSessionRemainingTime() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(10)
        fixture.model.pauseTimer()
        fixture.model.workDuration = 120
        XCTAssertEqual(fixture.model.remainingTime, 50)

        fixture.model.startTimer()
        fixture.clock.advance(50)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        fixture.model.skipPhase()
        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertEqual(fixture.model.remainingTime, 120)
    }

    func testInvalidDurationsAndDailyGoalAreClampedAndRemainPersistable() async throws {
        let fixture = Fixture()
        fixture.model.workDuration = -10
        XCTAssertEqual(fixture.model.workDuration, 60)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        fixture.model.workDuration = 10_000
        XCTAssertEqual(fixture.model.workDuration, 7200)
        fixture.model.workDuration = .nan
        XCTAssertEqual(fixture.model.workDuration, 1500)
        fixture.model.workDuration = .infinity
        XCTAssertEqual(fixture.model.workDuration, 1500)

        fixture.model.breakDuration = -10
        XCTAssertEqual(fixture.model.breakDuration, 60)
        fixture.model.breakDuration = 10_000
        XCTAssertEqual(fixture.model.breakDuration, 3600)
        fixture.model.breakDuration = .nan
        XCTAssertEqual(fixture.model.breakDuration, 300)
        fixture.model.breakDuration = -.infinity
        XCTAssertEqual(fixture.model.breakDuration, 300)
        fixture.model.dailyGoal = 0
        XCTAssertEqual(fixture.model.dailyGoal, 1)
        fixture.model.dailyGoal = 100
        XCTAssertEqual(fixture.model.dailyGoal, 20)
        XCTAssertNil(fixture.model.storageError)

        let saved = try StateStore(defaults: fixture.defaults).load(
            now: fixture.clock.now,
            calendar: fixture.calendar
        )
        XCTAssertEqual(saved.workDuration, 1500)
        XCTAssertEqual(saved.breakDuration, 300)
        XCTAssertEqual(saved.dailyGoal, 20)
    }

    func testSleepSettlesActiveFragmentAndWakeRemainsPaused() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        fixture.clock.advance(13.25)
        fixture.model.handleSleep()
        XCTAssertEqual(fixture.model.remainingTime, 46.75, accuracy: 0.0001)
        XCTAssertFalse(fixture.model.isTimerRunning)

        fixture.clock.advance(86_400)
        fixture.model.handleWake()
        XCTAssertEqual(fixture.model.remainingTime, 46.75, accuracy: 0.0001)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.completedPomodoros, 0)
        XCTAssertEqual(fixture.model.lastActiveDate, "2026-10-23")
    }

    func testSleepNotificationCheckpointsBeforeReturningToSystem() async throws {
        let fixture = Fixture()
        let model = DogViewModel(
            store: StateStore(defaults: fixture.defaults),
            clock: fixture.clock,
            calendar: fixture.calendar,
            automaticTicks: true,
            effectsEnabled: false
        )
        model.workDuration = 60
        model.startTimer()
        fixture.clock.advance(12.5)

        // This is an in-process notification only; it does not put the machine to sleep.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertFalse(model.isTimerRunning)
        XCTAssertEqual(model.remainingTime, 47.5, accuracy: 0.0001)
        let checkpoint = try StateStore(defaults: fixture.defaults).load(now: fixture.clock.now, calendar: fixture.calendar)
        XCTAssertEqual(checkpoint.timer?.wasRunning, false)
        XCTAssertEqual(checkpoint.timer?.remainingTime, 47.5)

        fixture.clock.advance(3600)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        model.refresh()
        XCTAssertFalse(model.isTimerRunning)
        XCTAssertEqual(model.remainingTime, 47.5, accuracy: 0.0001)
    }

    func testCorruptionDuringSessionStopsFurtherWritesAndRestoresNoPhantomCompletion() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.startTimer()
        let damaged = Data("damaged while app is running".utf8)
        fixture.defaults.set(damaged, forKey: StateStore.snapshotKey)
        fixture.clock.advance(12)
        fixture.model.refresh()
        XCTAssertNotNil(fixture.model.storageError)
        XCTAssertFalse(fixture.model.isTimerRunning)
        fixture.clock.advance(3600)
        fixture.model.startTimer()
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.completedPomodoros, 0)
        XCTAssertEqual(fixture.defaults.data(forKey: StateStore.snapshotKey), damaged)
    }

    func testDefaultRestCompletionWaitsForExplicitStartWithoutCountingIdleTime() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        XCTAssertFalse(fixture.model.autoStartNextSession)
        completeWork(fixture)
        finishBreak(fixture)

        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertFalse(fixture.model.restoredSession)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        fixture.clock.advance(3600)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.totalBreakTime, 60)

        let checkpoint = fixture.defaults.data(forKey: StateStore.snapshotKey)
        fixture.model.skipPhase()
        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertEqual(fixture.defaults.data(forKey: StateStore.snapshotKey), checkpoint)

        fixture.model.startTimer()
        XCTAssertFalse(fixture.model.isWaitingForNextSession)
        XCTAssertTrue(fixture.model.isTimerRunning)
        fixture.clock.advance(60)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.completedPomodoros, 2)
    }

    func testOptedInNaturalRestCompletionAutomaticallyStartsEvenAfterDailyGoal() async throws {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.dailyGoal = 1
        fixture.model.autoStartNextSession = true
        completeWork(fixture)
        finishBreak(fixture)

        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertTrue(fixture.model.isTimerRunning)
        XCTAssertFalse(fixture.model.isWaitingForNextSession)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        fixture.clock.advance(60)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.todayPomodoros, 2)
        let saved = try StateStore(defaults: fixture.defaults).load(now: fixture.clock.now, calendar: fixture.calendar)
        XCTAssertEqual(saved.autoStartNextSession, true)
        XCTAssertEqual(saved.lastGoalNotificationDay, "2026-10-22")

        let recovered = fixture.reopen()
        XCTAssertTrue(recovered.autoStartNextSession)
        XCTAssertFalse(recovered.isTimerRunning)
        XCTAssertFalse(recovered.isWaitingForNextSession)
        XCTAssertTrue(recovered.restoredSession)
    }

    func testEndingRunningBreakByUserAlwaysWaitsEvenWithAutoStart() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.autoStartNextSession = true
        completeWork(fixture)
        fixture.clock.advance(10)
        fixture.model.skipPhase()

        XCTAssertEqual(fixture.model.timerState, .working)
        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertEqual(fixture.model.totalBreakTime, 10)
        fixture.clock.advance(3600)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
        XCTAssertEqual(fixture.model.totalBreakTime, 10)
    }

    func testEndingBreakAtItsNaturalDeadlineStillWaitsWithAutoStart() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.autoStartNextSession = true
        completeWork(fixture)
        fixture.clock.advance(60)
        fixture.model.skipPhase()

        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.remainingTime, 60)
        XCTAssertEqual(fixture.model.totalBreakTime, 60)
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
    }

    func testPausedBreakSkipNeverAutoStartsNextSession() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.autoStartNextSession = true
        completeWork(fixture)
        fixture.model.pauseTimer()
        fixture.clock.advance(3600)
        fixture.model.skipPhase()

        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.totalBreakTime, 0)
        XCTAssertEqual(fixture.model.remainingTime, 60)
    }

    func testWaitingSurvivesRestartSleepWakeWithoutIncompleteSessionRecoveryMessage() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        completeWork(fixture)
        finishBreak(fixture)
        fixture.model.autoStartNextSession = true
        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertFalse(fixture.model.isTimerRunning)
        fixture.model.prepareForTermination()
        XCTAssertFalse(fixture.model.restoredSession)
        fixture.clock.advance(3600)

        let recovered = fixture.reopen()
        XCTAssertTrue(recovered.isWaitingForNextSession)
        XCTAssertTrue(recovered.autoStartNextSession)
        XCTAssertFalse(recovered.isTimerRunning)
        XCTAssertFalse(recovered.restoredSession)
        XCTAssertEqual(recovered.remainingTime, 60)
        recovered.handleSleep()
        fixture.clock.advance(3600)
        recovered.handleWake()
        XCTAssertTrue(recovered.isWaitingForNextSession)
        XCTAssertFalse(recovered.restoredSession)
        XCTAssertEqual(recovered.completedPomodoros, 1)
        XCTAssertEqual(recovered.totalBreakTime, 60)

        recovered.startTimer()
        XCTAssertFalse(recovered.isWaitingForNextSession)
        XCTAssertTrue(recovered.isTimerRunning)
    }

    func testDurationChangesUpdateWaitingWorkButNotRunningOrPausedWork() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        completeWork(fixture)
        finishBreak(fixture)
        fixture.model.workDuration = 120
        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertEqual(fixture.model.remainingTime, 120)
        let waiting = fixture.reopen()
        XCTAssertTrue(waiting.isWaitingForNextSession)
        XCTAssertEqual(waiting.remainingTime, 120)

        fixture.model.startTimer()
        fixture.clock.advance(10)
        fixture.model.refresh()
        fixture.model.workDuration = 180
        XCTAssertEqual(fixture.model.remainingTime, 110)
        fixture.model.pauseTimer()
        fixture.model.workDuration = 240
        XCTAssertEqual(fixture.model.remainingTime, 110)
        XCTAssertFalse(fixture.model.isWaitingForNextSession)
        XCTAssertNil(fixture.model.storageError)
    }

    func testExistingV1WithoutNewOptionsRestoresAnActualSessionPaused() async throws {
        let fixture = Fixture()
        var oldState = PersistedState()
        oldState.autoStartNextSession = nil
        oldState.isWaitingForNextSession = nil
        oldState.workDuration = 60
        oldState.timer = PersistedTimer(phase: .working, remainingTime: 45, phaseDuration: 60,
                                        wasRunning: true, savedAt: fixture.clock.now)
        try StateStore(defaults: fixture.defaults).save(oldState)

        let recovered = fixture.reopen()

        XCTAssertFalse(recovered.autoStartNextSession)
        XCTAssertFalse(recovered.isWaitingForNextSession)
        XCTAssertFalse(recovered.isTimerRunning)
        XCTAssertTrue(recovered.restoredSession)
        XCTAssertEqual(recovered.remainingTime, 45)
        XCTAssertNil(recovered.storageError)
    }

    func testGoalMarkerRequiresCompletedWorkAndCanAdvanceOnNextDay() async throws {
        let fixture = Fixture()
        fixture.useShortDurations()
        fixture.model.dailyGoal = 2
        for _ in 0..<2 {
            fixture.model.startTimer()
            fixture.model.skipPhase()
            fixture.model.skipPhase()
        }
        func goalDay() throws -> String? {
            try StateStore(defaults: fixture.defaults).load(now: fixture.clock.now, calendar: fixture.calendar).lastGoalNotificationDay
        }
        XCTAssertNil(try goalDay())
        completeWork(fixture)
        XCTAssertNil(try goalDay())
        finishBreak(fixture)
        completeWork(fixture)
        XCTAssertEqual(try goalDay(), "2026-10-22")
        finishBreak(fixture)
        completeWork(fixture)
        XCTAssertEqual(try goalDay(), "2026-10-22")
        finishBreak(fixture)

        fixture.clock.move(to: date("2026-10-23T12:00:00Z"))
        fixture.model.refresh()
        completeWork(fixture)
        XCTAssertEqual(try goalDay(), "2026-10-22")
        finishBreak(fixture)
        completeWork(fixture)
        XCTAssertEqual(try goalDay(), "2026-10-23")
    }

    func testGoalMarkerUsesActualCompletionDayForDelayedCallback() async throws {
        let fixture = Fixture(now: date("2026-10-21T23:58:30Z"))
        fixture.useShortDurations()
        fixture.model.dailyGoal = 1
        fixture.model.startTimer()
        fixture.clock.advance(120)
        fixture.model.refresh()

        let state = try StateStore(defaults: fixture.defaults).load(now: fixture.clock.now, calendar: fixture.calendar)
        XCTAssertEqual(state.lastGoalNotificationDay, "2026-10-21")
        XCTAssertEqual(fixture.model.todayPomodoros, 0)
    }

    func testResetFromWaitingReturnsReadyWithoutDeletingCompletedWork() async {
        let fixture = Fixture()
        fixture.useShortDurations()
        completeWork(fixture)
        finishBreak(fixture)
        fixture.model.resetTimer()

        XCTAssertEqual(fixture.model.timerState, .stopped)
        XCTAssertFalse(fixture.model.isWaitingForNextSession)
        XCTAssertFalse(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.todayPomodoros, 1)
        XCTAssertEqual(fixture.model.pomodorosInCycle, 0)
        fixture.model.startTimer()
        XCTAssertTrue(fixture.model.isTimerRunning)
        XCTAssertEqual(fixture.model.todayPomodoros, 1)
    }

    private func completeWork(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        fixture.model.startTimer()
        XCTAssertEqual(fixture.model.timerState, .working, file: file, line: line)
        fixture.clock.advance(fixture.model.remainingTime)
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.timerState, .onBreak, file: file, line: line)
    }

    private func finishBreak(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fixture.model.timerState, .onBreak, file: file, line: line)
        fixture.model.startTimer()
        fixture.clock.advance(fixture.model.remainingTime)
        fixture.model.refresh()
    }
}

private final class FakeTimerClock: TimerClock {
    var now: Date
    var uptime: TimeInterval = 1000

    init(now: Date) { self.now = now }

    func advance(_ interval: TimeInterval) {
        now.addTimeInterval(interval)
        uptime += interval
    }

    func move(to date: Date) {
        uptime += max(0, date.timeIntervalSince(now))
        now = date
    }
}

@MainActor
private final class Fixture {
    let suiteName: String
    let defaults: UserDefaults
    let clock: FakeTimerClock
    let calendar: Calendar
    let model: DogViewModel

    init(now: Date = date("2026-10-22T12:00:00Z"), legacy: [String: Any] = [:]) {
        let suiteName = "PomodoroPupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        legacy.forEach { defaults.set($0.value, forKey: $0.key) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let clock = FakeTimerClock(now: now)
        self.suiteName = suiteName
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        self.model = DogViewModel(
            store: StateStore(defaults: defaults),
            clock: clock,
            calendar: calendar,
            automaticTicks: false,
            effectsEnabled: false
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func useShortDurations() {
        model.workDuration = 60
        model.breakDuration = 60
    }

    func reopen() -> DogViewModel {
        DogViewModel(
            store: StateStore(defaults: defaults),
            clock: clock,
            calendar: calendar,
            automaticTicks: false,
            effectsEnabled: false
        )
    }
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
