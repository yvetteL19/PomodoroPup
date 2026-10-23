import Foundation

struct PersistedTimer: Codable, Equatable {
    var phase: TimerState
    var remainingTime: Double
    var phaseDuration: Double
    var wasRunning: Bool
    var savedAt: Date
}

struct PersistedState: Codable, Equatable {
    var schemaVersion: Int = 1
    var completedPomodoros: Int = 0
    var unlockedAchievements: Set<String> = []
    var currentStreakPomodoros: Int = 0
    var totalBreakTime: Double = 0
    var pomodorosInCycle: Int = 0
    var dailyCounts: [String: Int] = [:]
    var legacyStreakCount: Int = 0
    var legacyStreakEndDay: String?
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var lastGoalNotificationDay: String?
    var workDuration: Double = 25 * 60
    var breakDuration: Double = 5 * 60
    var dailyGoal: Int = 4
    var soundEnabled: Bool = true
    var animationEnabled: Bool = true
    var notificationEnabled: Bool = true
    // Additive v1 fields: absent values from earlier snapshots mean false.
    var autoStartNextSession: Bool? = false
    var isWaitingForNextSession: Bool? = false
    var timer: PersistedTimer?
}

enum StateStoreError: Error, LocalizedError, Equatable {
    case invalidSnapshot
    case unsupportedVersion(Int)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .invalidSnapshot:
            return "Saved data could not be read. The original data has been preserved."
        case .unsupportedVersion(let version):
            return "Saved data uses an unsupported version (\(version)). The original data has been preserved."
        case .invalidState(let field):
            return "Saved data contains an invalid value for \(field). The original data has been preserved."
        }
    }
}

/// Owns one versioned snapshot. Legacy keys are read-only and are backed up before migration.
final class StateStore {
    static let snapshotKey = "PomodoroPup.state.v1"
    static let legacyBackupKey = "PomodoroPup.legacyBackup.v1"
    // Technical bounds leave headroom for additions and Double-to-Int conversion.
    // They are not product limits or a reason to truncate historical records.
    static let maximumCounter = Int.max / 4
    static let maximumBreakTime = Double(maximumCounter)

    private static let legacyKeys = [
        "timerState", "completedPomodoros", "unlockedAchievements", "consecutiveDays",
        "currentStreakPomodoros", "totalBreakTime", "pomodorosInCycle", "todayPomodoros",
        "lastActiveDate", "workDuration", "breakDuration", "dailyGoal", "soundEnabled",
        "animationEnabled", "notificationEnabled", "hasCompletedOnboarding"
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(now: Date, calendar: Calendar) throws -> PersistedState {
        if let stored = defaults.object(forKey: Self.snapshotKey) {
            return try decodeSnapshot(stored)
        }

        // Capture raw values before interpreting them, including values a future migration
        // might understand better. Never replace this backup, even after a failed migration.
        let legacy = Self.legacyKeys.reduce(into: [String: Any]()) { result, key in
            if let value = defaults.object(forKey: key) {
                result[key] = value
            }
        }
        if !legacy.isEmpty && defaults.object(forKey: Self.legacyBackupKey) == nil {
            defaults.set(legacy, forKey: Self.legacyBackupKey)
        }

        var state = PersistedState()
        state.timeZoneIdentifier = calendar.timeZone.identifier
        state.completedPomodoros = try nonnegativeInt(legacy["completedPomodoros"], field: "completedPomodoros")
        state.unlockedAchievements = Set((legacy["unlockedAchievements"] as? [Any] ?? []).compactMap { $0 as? String })
        state.currentStreakPomodoros = try nonnegativeInt(legacy["currentStreakPomodoros"], field: "currentStreakPomodoros")
        if let number = legacy["totalBreakTime"] as? NSNumber {
            guard number.doubleValue.isFinite && (-Self.maximumBreakTime...Self.maximumBreakTime).contains(number.doubleValue) else {
                throw StateStoreError.invalidState("totalBreakTime")
            }
            state.totalBreakTime = max(0, number.doubleValue)
        }
        state.legacyStreakCount = try nonnegativeInt(legacy["consecutiveDays"], field: "consecutiveDays")
        let datedCompletions = try nonnegativeInt(legacy["todayPomodoros"], field: "todayPomodoros")

        // The old counter included skipped sessions. It is not a trustworthy count of
        // completed work, so retain its raw value only in the backup.
        _ = try nonnegativeInt(legacy["pomodorosInCycle"], field: "pomodorosInCycle")
        state.pomodorosInCycle = 0
        if let lastDay = legacy["lastActiveDate"] as? String,
           let lastDate = Self.date(from: lastDay, calendar: calendar) {
            state.dailyCounts[lastDay] = datedCompletions
            if state.legacyStreakCount > 0,
               let previousDate = calendar.date(byAdding: .day, value: -1, to: lastDate) {
                state.legacyStreakEndDay = Self.dayString(from: previousDate, calendar: calendar)
            }
        }

        state.workDuration = duration(legacy["workDuration"], default: state.workDuration, range: 60...7_200)
        state.breakDuration = duration(legacy["breakDuration"], default: state.breakDuration, range: 60...3_600)
        if let goal = finiteNumber(legacy["dailyGoal"]) {
            state.dailyGoal = Int(min(20, max(1, goal)))
        }
        state.soundEnabled = legacyBool(legacy["soundEnabled"], default: true)
        state.animationEnabled = legacyBool(legacy["animationEnabled"], default: true)
        state.notificationEnabled = legacyBool(legacy["notificationEnabled"], default: true)

        // No old key records remaining time. Never invent a recovered session or
        // attribute undated historical work to `now`.
        state.timer = nil
        try save(state)
        return state
    }

    func save(_ state: PersistedState) throws {
        // Also protect callers that accidentally attempt a save after a failed load.
        if let stored = defaults.object(forKey: Self.snapshotKey) {
            _ = try decodeSnapshot(stored)
        }
        try validate(state)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        defaults.set(data, forKey: Self.snapshotKey)
    }

    private func decodeSnapshot(_ stored: Any) throws -> PersistedState {
        guard let data = stored as? Data else { throw StateStoreError.invalidSnapshot }
        struct Version: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let version: Version
        do {
            version = try decoder.decode(Version.self, from: data)
        } catch {
            throw StateStoreError.invalidSnapshot
        }
        guard version.schemaVersion == 1 else {
            throw StateStoreError.unsupportedVersion(version.schemaVersion)
        }
        var state: PersistedState
        do {
            state = try decoder.decode(PersistedState.self, from: data)
        } catch {
            throw StateStoreError.invalidSnapshot
        }
        // Normalize only the new optional fields. Existing required v1 fields still
        // use synthesized strict decoding and must never fall back to defaults.
        state.autoStartNextSession = state.autoStartNextSession ?? false
        state.isWaitingForNextSession = state.isWaitingForNextSession ?? false
        try validate(state)
        return state
    }

    private func validate(_ state: PersistedState) throws {
        guard state.schemaVersion == 1 else { throw StateStoreError.unsupportedVersion(state.schemaVersion) }
        let counts = [
            ("completedPomodoros", state.completedPomodoros),
            ("currentStreakPomodoros", state.currentStreakPomodoros),
            ("pomodorosInCycle", state.pomodorosInCycle),
            ("legacyStreakCount", state.legacyStreakCount)
        ]
        for (field, value) in counts where !(0...Self.maximumCounter).contains(value) {
            throw StateStoreError.invalidState(field)
        }
        guard state.totalBreakTime.isFinite && (0...Self.maximumBreakTime).contains(state.totalBreakTime) else {
            throw StateStoreError.invalidState("totalBreakTime")
        }
        guard state.workDuration.isFinite && (60...7_200).contains(state.workDuration) else {
            throw StateStoreError.invalidState("workDuration")
        }
        guard state.breakDuration.isFinite && (60...3_600).contains(state.breakDuration) else {
            throw StateStoreError.invalidState("breakDuration")
        }
        guard (1...20).contains(state.dailyGoal) else { throw StateStoreError.invalidState("dailyGoal") }
        guard let zone = TimeZone(identifier: state.timeZoneIdentifier) else {
            throw StateStoreError.invalidState("timeZoneIdentifier")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        for (day, count) in state.dailyCounts {
            guard (0...Self.maximumCounter).contains(count) && Self.date(from: day, calendar: calendar) != nil else {
                throw StateStoreError.invalidState("dailyCounts")
            }
        }
        for (field, day) in [("legacyStreakEndDay", state.legacyStreakEndDay),
                             ("lastGoalNotificationDay", state.lastGoalNotificationDay)] {
            if let day, Self.date(from: day, calendar: calendar) == nil {
                throw StateStoreError.invalidState(field)
            }
        }
        if let timer = state.timer {
            let allowedDuration: ClosedRange<Double>
            switch timer.phase {
            case .working: allowedDuration = 60...7_200
            case .onBreak: allowedDuration = 60...3_600
            case .stopped: throw StateStoreError.invalidState("timer.phase")
            }
            guard timer.phaseDuration.isFinite && allowedDuration.contains(timer.phaseDuration) else {
                throw StateStoreError.invalidState("timer.phaseDuration")
            }
            guard timer.remainingTime.isFinite && (0...timer.phaseDuration).contains(timer.remainingTime) else {
                throw StateStoreError.invalidState("timer.remainingTime")
            }
            guard timer.savedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw StateStoreError.invalidState("timer.savedAt")
            }
        }
        if state.isWaitingForNextSession == true {
            guard let timer = state.timer, timer.phase == .working, !timer.wasRunning,
                  timer.remainingTime == timer.phaseDuration,
                  timer.phaseDuration == state.workDuration else {
                throw StateStoreError.invalidState("isWaitingForNextSession")
            }
        }
    }

    private func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private func nonnegativeInt(_ value: Any?, field: String) throws -> Int {
        guard let number = value as? NSNumber else { return 0 }
        guard number.doubleValue.isFinite,
              (-Self.maximumBreakTime...Self.maximumBreakTime).contains(number.doubleValue) else {
            throw StateStoreError.invalidState(field)
        }
        if let exactInteger = Int(number.stringValue) {
            guard exactInteger <= Self.maximumCounter else { throw StateStoreError.invalidState(field) }
            return max(0, exactInteger)
        }
        if number.doubleValue <= 0 { return 0 }
        guard let integer = Int(exactly: number.doubleValue.rounded(.towardZero)),
              integer <= Self.maximumCounter else { throw StateStoreError.invalidState(field) }
        return integer
    }

    private func duration(_ value: Any?, default fallback: Double, range: ClosedRange<Double>) -> Double {
        guard let value = finiteNumber(value) else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private func legacyBool(_ value: Any?, default fallback: Bool) -> Bool {
        (value as? NSNumber)?.boolValue ?? fallback
    }

    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    private static func date(from day: String, calendar: Calendar) -> Date? {
        guard day.count == 10 else { return nil }
        let formatter = dayFormatter(calendar: calendar)
        guard let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        return date
    }

    private static func dayString(from date: Date, calendar: Calendar) -> String {
        dayFormatter(calendar: calendar).string(from: date)
    }
}
