import XCTest
@testable import PomodoroPupCore

final class StateStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: StateStore!
    private var calendar: Calendar!
    private let now = Date(timeIntervalSince1970: 1_792_620_000)

    override func setUp() {
        super.setUp()
        suiteName = "PomodoroPup.StateStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = StateStore(defaults: defaults)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testFirstLaunchCreatesOnlyCurrentSnapshot() throws {
        let state = try store.load(now: now, calendar: calendar)

        XCTAssertEqual(state, PersistedState(timeZoneIdentifier: "Asia/Shanghai"))
        XCTAssertNotNil(defaults.data(forKey: StateStore.snapshotKey))
        XCTAssertNil(defaults.object(forKey: StateStore.legacyBackupKey))
        XCTAssertNil(defaults.object(forKey: "completedPomodoros"))
        XCTAssertNil(defaults.object(forKey: "hasCompletedOnboarding"))
        XCTAssertEqual(try store.load(now: now, calendar: calendar), state)
    }

    func testMigrationPreservesStatisticsPreferencesAndUnknownAchievementsWithoutWritingLegacyKeys() throws {
        let legacy: [String: Any] = [
            "timerState": "working", "completedPomodoros": 42,
            "unlockedAchievements": ["icon_bone", "future-achievement"],
            "consecutiveDays": 7, "currentStreakPomodoros": 5,
            "totalBreakTime": 1_234.75, "pomodorosInCycle": 6,
            "todayPomodoros": 3, "lastActiveDate": "2026-10-21",
            "workDuration": 3_000.0, "breakDuration": 600.0, "dailyGoal": 8,
            "soundEnabled": false, "animationEnabled": false,
            "notificationEnabled": false, "hasCompletedOnboarding": true
        ]
        seed(legacy)

        var expected = PersistedState()
        expected.completedPomodoros = 42
        expected.unlockedAchievements = ["icon_bone", "future-achievement"]
        expected.currentStreakPomodoros = 5
        expected.totalBreakTime = 1_234.75
        expected.dailyCounts = ["2026-10-21": 3]
        expected.legacyStreakCount = 7
        expected.legacyStreakEndDay = "2026-10-20"
        expected.timeZoneIdentifier = "Asia/Shanghai"
        expected.workDuration = 3_000
        expected.breakDuration = 600
        expected.dailyGoal = 8
        expected.soundEnabled = false
        expected.animationEnabled = false
        expected.notificationEnabled = false

        XCTAssertEqual(try store.load(now: now, calendar: calendar), expected)
        XCTAssertEqual(try store.load(now: now, calendar: calendar), expected)
        XCTAssertEqual(defaults.dictionary(forKey: StateStore.legacyBackupKey)! as NSDictionary, legacy as NSDictionary)
        for (key, value) in legacy {
            XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject, key)
        }
        XCTAssertEqual(defaults.integer(forKey: "pomodorosInCycle"), 6)
    }

    func testBackupIsWrittenOnceAndNeverReplaced() throws {
        defaults.set(42, forKey: "completedPomodoros")
        _ = try store.load(now: now, calendar: calendar)
        let originalBackup = defaults.dictionary(forKey: StateStore.legacyBackupKey)!

        defaults.removeObject(forKey: StateStore.snapshotKey)
        defaults.set(99, forKey: "completedPomodoros")
        _ = try store.load(now: now, calendar: calendar)

        XCTAssertEqual(defaults.dictionary(forKey: StateStore.legacyBackupKey)! as NSDictionary, originalBackup as NSDictionary)
    }

    func testCurrentSnapshotTakesPriorityOverLegacyAndRoundTripsFractionalTimer() throws {
        var state = PersistedState(timeZoneIdentifier: "America/Los_Angeles")
        state.completedPomodoros = 52
        state.unlockedAchievements = ["unknown-achievement"]
        state.totalBreakTime = 123.625
        state.dailyCounts = ["2026-10-21": 5]
        state.lastGoalNotificationDay = "2026-10-21"
        state.timer = PersistedTimer(phase: .onBreak, remainingTime: 201.125,
                                    phaseDuration: 600, wasRunning: true, savedAt: now)
        try store.save(state)
        defaults.set(0, forKey: "completedPomodoros")
        defaults.set(false, forKey: "soundEnabled")

        XCTAssertEqual(try store.load(now: now.addingTimeInterval(10_000), calendar: calendar), state)
        XCTAssertNil(defaults.object(forKey: StateStore.legacyBackupKey))
    }

    func testMalformedSnapshotIsPreservedAndCannotBeOverwrittenBySave() throws {
        let raw = Data("not JSON".utf8)
        defaults.set(raw, forKey: StateStore.snapshotKey)
        defaults.set(42, forKey: "completedPomodoros")

        XCTAssertThrowsError(try store.load(now: now, calendar: calendar)) {
            XCTAssertEqual($0 as? StateStoreError, .invalidSnapshot)
        }
        XCTAssertThrowsError(try store.save(PersistedState()))
        XCTAssertEqual(defaults.data(forKey: StateStore.snapshotKey), raw)
        XCTAssertEqual(defaults.integer(forKey: "completedPomodoros"), 42)
        XCTAssertNil(defaults.object(forKey: StateStore.legacyBackupKey))
    }

    func testWrongStoredTypeIsPreserved() {
        defaults.set("unexpected-string", forKey: StateStore.snapshotKey)

        XCTAssertThrowsError(try store.load(now: now, calendar: calendar))
        XCTAssertThrowsError(try store.save(PersistedState()))
        XCTAssertEqual(defaults.string(forKey: StateStore.snapshotKey), "unexpected-string")
    }

    func testUnknownVersionIsRejectedBeforeDecodingItsSchema() {
        let raw = Data("{\"schemaVersion\":99,\"newData\":\"must survive\"}".utf8)
        defaults.set(raw, forKey: StateStore.snapshotKey)

        XCTAssertThrowsError(try store.load(now: now, calendar: calendar)) {
            XCTAssertEqual($0 as? StateStoreError, .unsupportedVersion(99))
        }
        XCTAssertThrowsError(try store.save(PersistedState()))
        XCTAssertEqual(defaults.data(forKey: StateStore.snapshotKey), raw)
    }

    func testIncompleteCurrentSnapshotDoesNotSilentlyDecodeDefaults() {
        let raw = Data("{\"schemaVersion\":1}".utf8)
        defaults.set(raw, forKey: StateStore.snapshotKey)

        XCTAssertThrowsError(try store.load(now: now, calendar: calendar))
        XCTAssertEqual(defaults.data(forKey: StateStore.snapshotKey), raw)
    }

    func testInvalidCurrentValuesAreRejectedWithoutChangingStoredData() throws {
        let invalidChanges: [(inout PersistedState) -> Void] = [
            { $0.completedPomodoros = -1 }, { $0.currentStreakPomodoros = -1 },
            { $0.totalBreakTime = -0.5 }, { $0.pomodorosInCycle = -1 },
            { $0.dailyCounts = ["2026-02-30": 1] },
            { $0.dailyCounts = ["2026-10-21": -1] },
            { $0.legacyStreakCount = -1 }, { $0.legacyStreakEndDay = "invalid" },
            { $0.timeZoneIdentifier = "Invalid/TimeZone" },
            { $0.lastGoalNotificationDay = "2026-2-1" },
            { $0.workDuration = 59 }, { $0.workDuration = 7_201 },
            { $0.breakDuration = 59 }, { $0.breakDuration = 3_601 },
            { $0.dailyGoal = 0 }, { $0.dailyGoal = 21 }
        ]
        for change in invalidChanges {
            var state = PersistedState()
            change(&state)
            let raw = try JSONEncoder().encode(state)
            defaults.set(raw, forKey: StateStore.snapshotKey)
            XCTAssertThrowsError(try store.load(now: now, calendar: calendar))
            XCTAssertEqual(defaults.data(forKey: StateStore.snapshotKey), raw)
        }
    }

    func testInvalidTimersAndNonFiniteValuesCannotReplaceGoodSnapshot() throws {
        let initial = try store.load(now: now, calendar: calendar)
        let originalData = defaults.data(forKey: StateStore.snapshotKey)
        let invalidTimers = [
            PersistedTimer(phase: .stopped, remainingTime: 60, phaseDuration: 60, wasRunning: false, savedAt: now),
            PersistedTimer(phase: .working, remainingTime: -1, phaseDuration: 60, wasRunning: true, savedAt: now),
            PersistedTimer(phase: .working, remainingTime: 61, phaseDuration: 60, wasRunning: true, savedAt: now),
            PersistedTimer(phase: .working, remainingTime: 30, phaseDuration: 59, wasRunning: true, savedAt: now),
            PersistedTimer(phase: .onBreak, remainingTime: 30, phaseDuration: 3_601, wasRunning: true, savedAt: now),
            PersistedTimer(phase: .onBreak, remainingTime: .infinity, phaseDuration: 60, wasRunning: true, savedAt: now),
            PersistedTimer(phase: .working, remainingTime: 30, phaseDuration: 60, wasRunning: false,
                           savedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        ]
        for timer in invalidTimers {
            var state = initial
            state.timer = timer
            XCTAssertThrowsError(try store.save(state))
            XCTAssertEqual(defaults.data(forKey: StateStore.snapshotKey), originalData)
        }
        for value in [Double.nan, .infinity, -.infinity] {
            var state = initial
            state.totalBreakTime = value
            XCTAssertThrowsError(try store.save(state))
            XCTAssertEqual(defaults.data(forKey: StateStore.snapshotKey), originalData)
        }
    }

    func testZeroRemainingPausedTimerAndDurationBoundariesAreValid() throws {
        var state = PersistedState()
        state.workDuration = 7_200
        state.breakDuration = 60
        state.dailyGoal = 20
        state.timer = PersistedTimer(phase: .working, remainingTime: 0, phaseDuration: 7_200,
                                    wasRunning: false, savedAt: now)

        try store.save(state)
        XCTAssertEqual(try store.load(now: now, calendar: calendar), state)
    }

    func testLegacySanitizationRetainsRawBackup() throws {
        let legacy: [String: Any] = [
            "completedPomodoros": -10, "currentStreakPomodoros": -2,
            "totalBreakTime": -12.5, "consecutiveDays": -3,
            "workDuration": 100_000.0, "breakDuration": 10.0, "dailyGoal": 100,
            "unlockedAchievements": ["future-item"], "hasCompletedOnboarding": true
        ]
        seed(legacy)

        let state = try store.load(now: now, calendar: calendar)

        XCTAssertEqual(state.completedPomodoros, 0)
        XCTAssertEqual(state.currentStreakPomodoros, 0)
        XCTAssertEqual(state.totalBreakTime, 0)
        XCTAssertEqual(state.legacyStreakCount, 0)
        XCTAssertEqual(state.workDuration, 7_200)
        XCTAssertEqual(state.breakDuration, 60)
        XCTAssertEqual(state.dailyGoal, 20)
        XCTAssertEqual(state.unlockedAchievements, ["future-item"])
        XCTAssertTrue(state.soundEnabled)
        XCTAssertEqual(defaults.dictionary(forKey: StateStore.legacyBackupKey)! as NSDictionary, legacy as NSDictionary)
    }

    func testUndatedLegacyCountsAreNotInventedAsTodaysWork() throws {
        seed(["lastActiveDate": "not-a-date", "todayPomodoros": 8,
              "completedPomodoros": 42, "consecutiveDays": 3])

        let state = try store.load(now: now, calendar: calendar)

        XCTAssertEqual(state.completedPomodoros, 42)
        XCTAssertTrue(state.dailyCounts.isEmpty)
        XCTAssertEqual(state.legacyStreakCount, 3)
        XCTAssertNil(state.legacyStreakEndDay)
        XCTAssertEqual(defaults.dictionary(forKey: StateStore.legacyBackupKey)?["todayPomodoros"] as? Int, 8)
    }

    func testLegacyStreakEndUsesPreviousCalendarDayAcrossLeapDay() throws {
        seed(["lastActiveDate": "2024-03-01", "todayPomodoros": 4, "consecutiveDays": 3])

        let state = try store.load(now: now, calendar: calendar)

        XCTAssertEqual(state.dailyCounts, ["2024-03-01": 4])
        XCTAssertEqual(state.legacyStreakEndDay, "2024-02-29")
    }

    func testLegacyStreakEndUsesPreviousCalendarDayAcrossDST() throws {
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        seed(["lastActiveDate": "2026-03-09", "consecutiveDays": 2])

        let state = try store.load(now: now, calendar: calendar)

        XCTAssertEqual(state.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(state.legacyStreakEndDay, "2026-03-08")
    }

    func testOversizedCurrentNumbersAreRejectedBeforeModelConversionOrArithmetic() throws {
        let invalidChanges: [(inout PersistedState) -> Void] = [
            { $0.completedPomodoros = Int.max },
            { $0.currentStreakPomodoros = Int.max },
            { $0.pomodorosInCycle = Int.max },
            { $0.legacyStreakCount = Int.max },
            { $0.dailyCounts = ["2026-10-21": Int.max] },
            { $0.totalBreakTime = 1e20 }
        ]
        for change in invalidChanges {
            var state = PersistedState()
            change(&state)
            let raw = try JSONEncoder().encode(state)
            defaults.set(raw, forKey: StateStore.snapshotKey)

            XCTAssertThrowsError(try store.load(now: now, calendar: calendar))
            XCTAssertThrowsError(try store.save(PersistedState()))
            XCTAssertEqual(defaults.data(forKey: StateStore.snapshotKey), raw)
        }
    }

    func testOversizedLegacyNumbersFailAfterBackupWithoutTruncatingHistory() {
        let invalidValues: [(String, Any)] = [
            ("completedPomodoros", Int.max),
            ("currentStreakPomodoros", Int.max),
            ("pomodorosInCycle", Int.max),
            ("consecutiveDays", Int.max),
            ("todayPomodoros", Int.max),
            ("totalBreakTime", 1e20),
            ("completedPomodoros", 1e100),
            ("completedPomodoros", -1e100),
            ("completedPomodoros", NSNumber(value: UInt64.max)),
            ("totalBreakTime", Double.infinity),
            ("currentStreakPomodoros", Double.infinity)
        ]
        for (key, value) in invalidValues {
            defaults.removePersistentDomain(forName: suiteName)
            let legacy: [String: Any] = [key: value, "hasCompletedOnboarding": true,
                                         "lastActiveDate": "2026-10-21"]
            seed(legacy)

            XCTAssertThrowsError(try store.load(now: now, calendar: calendar), key)
            XCTAssertNil(defaults.object(forKey: StateStore.snapshotKey), key)
            XCTAssertEqual(defaults.dictionary(forKey: StateStore.legacyBackupKey)! as NSDictionary,
                           legacy as NSDictionary, key)
            XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject, key)
        }
    }

    func testTechnicalUpperBoundsLeaveRoomForModelArithmeticAndIntegerConversion() throws {
        var state = PersistedState()
        state.completedPomodoros = StateStore.maximumCounter
        state.currentStreakPomodoros = StateStore.maximumCounter
        state.pomodorosInCycle = StateStore.maximumCounter
        state.legacyStreakCount = StateStore.maximumCounter
        state.dailyCounts = ["2026-10-21": StateStore.maximumCounter]
        state.totalBreakTime = StateStore.maximumBreakTime

        try store.save(state)
        let loaded = try store.load(now: now, calendar: calendar)

        XCTAssertEqual(loaded, state)
        XCTAssertGreaterThan(loaded.completedPomodoros + 1, loaded.completedPomodoros)
        XCTAssertLessThan(Int(loaded.totalBreakTime), Int.max)
    }

    private func seed(_ values: [String: Any]) {
        values.forEach { defaults.set($0.value, forKey: $0.key) }
    }
}
