import SwiftUI
import AppKit
import Combine

// 状态定义
enum TimerState: String, Codable {
    case stopped, working, onBreak
}

// 成就定义
enum AchievementType: String, CaseIterable {
    case novice = "icon_bone"
    case efficient = "icon_glasses"
    case master = "icon_crown"
    case habit = "icon_paw"
    case deepWork = "icon_bulb"
    case partyKing = "icon_party"

    var displayName: String {
        switch self {
        case .novice: return NSLocalizedString("achievement.novice.name", comment: "")
        case .efficient: return NSLocalizedString("achievement.efficient.name", comment: "")
        case .master: return NSLocalizedString("achievement.master.name", comment: "")
        case .habit: return NSLocalizedString("achievement.habit.name", comment: "")
        case .deepWork: return NSLocalizedString("achievement.deepWork.name", comment: "")
        case .partyKing: return NSLocalizedString("achievement.partyKing.name", comment: "")
        }
    }

    var description: String {
        switch self {
        case .novice: return NSLocalizedString("achievement.novice.desc", comment: "")
        case .efficient: return NSLocalizedString("achievement.efficient.desc", comment: "")
        case .master: return NSLocalizedString("achievement.master.desc", comment: "")
        case .habit: return NSLocalizedString("achievement.habit.desc", comment: "")
        case .deepWork: return NSLocalizedString("achievement.deepWork.desc", comment: "")
        case .partyKing: return NSLocalizedString("achievement.partyKing.desc", comment: "")
        }
    }

    var threshold: Int {
        switch self {
        case .novice: return 10
        case .efficient: return 50
        case .master: return 200
        case .habit: return 3 // 连续天数
        case .deepWork: return 3 // 连续番茄数
        case .partyKing: return 300 * 60 // 秒数
        }
    }
}

/// All mutations are driven by the main run loop. Tests supply a clock and disable
/// subscriptions and effects, so they never touch the real app's preferences.
final class DogViewModel: ObservableObject {
    @Published private(set) var timerState: TimerState = .stopped
    @Published private(set) var remainingTime: TimeInterval = 25 * 60
    @Published private(set) var completedPomodoros = 0
    @Published private(set) var unlockedAchievements: Set<String> = []
    @Published private(set) var consecutiveDays = 0
    @Published private(set) var currentStreakPomodoros = 0
    @Published private(set) var totalBreakTime = 0
    @Published private(set) var pomodorosInCycle = 0
    @Published private(set) var todayPomodoros = 0
    @Published private(set) var lastActiveDate = ""
    @Published private(set) var isTimerRunning = false
    @Published private(set) var isWaitingForNextSession = false
    @Published private(set) var restoredSession = false
    @Published private(set) var storageError: String?
    @Published var shouldFlashMenuBar = false

    @Published var workDuration: TimeInterval = 25 * 60 {
        didSet {
            let clamped = workDuration.isFinite ? min(7200, max(60, workDuration)) : 1500
            if workDuration != clamped { workDuration = clamped; return }
            settingsChanged()
        }
    }
    @Published var breakDuration: TimeInterval = 5 * 60 {
        didSet {
            let clamped = breakDuration.isFinite ? min(3600, max(60, breakDuration)) : 300
            if breakDuration != clamped { breakDuration = clamped; return }
            settingsChanged()
        }
    }
    @Published var dailyGoal = 4 {
        didSet {
            let clamped = min(20, max(1, dailyGoal))
            if dailyGoal != clamped { dailyGoal = clamped; return }
            settingsChanged()
        }
    }
    @Published var soundEnabled = true { didSet { settingsChanged() } }
    @Published var animationEnabled = true { didSet { settingsChanged() } }
    @Published var notificationEnabled = true { didSet { settingsChanged() } }
    @Published var autoStartNextSession = false { didSet { settingsChanged() } }

    private let store: StateStore
    private let clock: TimerClock
    private var calendar: Calendar
    private let automaticTicks: Bool
    private let effectsEnabled: Bool
    private let notificationSender: ((String, String, Bool) -> Void)?
    private var savedState = PersistedState()
    private var phaseDuration: TimeInterval = 1500
    private var breakSeconds: TimeInterval = 0
    private var lastTickUptime: TimeInterval?
    private var timer: AnyCancellable?
    private var lifecycleSubscriptions: [AnyCancellable] = []
    private var loaded = false
    private var updating = false
    private var feedbackAllowed = false
    private var feedback: [() -> Void] = []

    init(
        store: StateStore = StateStore(),
        clock: TimerClock = SystemTimerClock(),
        calendar: Calendar = .current,
        automaticTicks: Bool = true,
        effectsEnabled: Bool = true,
        notificationSender: ((String, String, Bool) -> Void)? = nil
    ) {
        self.store = store
        self.clock = clock
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
        self.automaticTicks = automaticTicks
        self.effectsEnabled = effectsEnabled
        self.notificationSender = notificationSender

        do {
            // Load into a value first. No property observer may save during hydration.
            let state = try store.load(now: clock.now, calendar: gregorian)
            savedState = state
            if let zone = TimeZone(identifier: state.timeZoneIdentifier) {
                self.calendar.timeZone = zone
            }
            completedPomodoros = state.completedPomodoros
            unlockedAchievements = state.unlockedAchievements
            currentStreakPomodoros = state.currentStreakPomodoros
            breakSeconds = state.totalBreakTime
            totalBreakTime = Int(breakSeconds)
            pomodorosInCycle = state.pomodorosInCycle
            workDuration = state.workDuration
            breakDuration = state.breakDuration
            dailyGoal = state.dailyGoal
            soundEnabled = state.soundEnabled
            animationEnabled = state.animationEnabled
            notificationEnabled = state.notificationEnabled
            autoStartNextSession = state.autoStartNextSession ?? false
            isWaitingForNextSession = state.isWaitingForNextSession ?? false
            if let session = state.timer {
                timerState = session.phase
                phaseDuration = session.phaseDuration
                remainingTime = session.remainingTime
                restoredSession = !isWaitingForNextSession
                // Always require an explicit resume. Time while the app was absent
                // must never turn into completed work or accumulated rest.
            } else {
                remainingTime = workDuration
                phaseDuration = workDuration
            }
            loaded = true
            update(emitFeedback: false) {}
        } catch {
            failSafely()
        }
        if automaticTicks { observeLifecycle() }
    }

    var timeString: String {
        let seconds = max(0, Int(ceil(remainingTime)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func startTimer() {
        guard !isTimerRunning else { return }
        update {
            if timerState == .stopped {
                pomodorosInCycle = 0
                timerState = .working
                phaseDuration = workDuration
                remainingTime = phaseDuration
            }
            isWaitingForNextSession = false
            restoredSession = false
            isTimerRunning = true
            lastTickUptime = clock.uptime
            // A zero checkpoint can occur after an interrupted write at a boundary.
            if remainingTime <= 0 { finishPhase(wasSkipped: false, at: clock.now) }
        }
        startHeartbeatIfNeeded()
    }

    func pauseTimer() {
        update {
            _ = consumeElapsedTime()
            stopRunning()
            restoredSession = false
        }
    }

    func skipPhase() {
        guard timerState != .stopped, !isWaitingForNextSession else { return }
        update {
            // If the old phase expired before this click, do not also skip the new one.
            if !consumeElapsedTime(allowAutomaticNextSession: timerState != .onBreak) {
                finishPhase(wasSkipped: true, at: clock.now)
            }
            restoredSession = false
        }
    }

    func resetTimer() {
        update {
            _ = consumeElapsedTime()
            stopRunning()
            timerState = .stopped
            phaseDuration = workDuration
            remainingTime = workDuration
            pomodorosInCycle = 0
            currentStreakPomodoros = 0
            isWaitingForNextSession = false
            restoredSession = false
        }
    }

    /// Public to the module for deterministic tests, UI activation and day changes.
    func refresh() {
        update { _ = consumeElapsedTime() }
    }

    func handleSleep() {
        update(emitFeedback: false) {
            _ = consumeElapsedTime()
            stopRunning()
            restoredSession = timerState != .stopped && !isWaitingForNextSession
        }
    }

    func handleWake() {
        // Also handles a missed sleep notification conservatively: never award the gap.
        update(emitFeedback: false) {
            stopRunning()
            restoredSession = timerState != .stopped && !isWaitingForNextSession
        }
    }

    func prepareForTermination() {
        handleSleep()
    }

    private func settingsChanged() {
        guard loaded, !updating else { return }
        update {
            _ = consumeElapsedTime()
            if timerState == .stopped || isWaitingForNextSession {
                remainingTime = workDuration
                phaseDuration = workDuration
            }
            // Waiting work has not begun. Only running/paused phases retain their
            // duration snapshot when future-session settings change.
        }
    }

    private func update(emitFeedback: Bool = true, _ operation: () -> Void) {
        guard loaded, !updating, storageError == nil else { return }
        updating = true
        feedbackAllowed = emitFeedback && effectsEnabled
        feedback.removeAll()
        operation()
        refreshDailyStatistics()
        checkAchievements()
        updating = false
        feedbackAllowed = false
        if persist() {
            let committedFeedback = feedback
            feedback.removeAll()
            committedFeedback.forEach { $0() }
        } else {
            feedback.removeAll()
        }
    }

    /// UI ticks are only refresh requests. Elapsed time comes from a monotonic clock,
    /// so a late callback or a wall-clock adjustment cannot change session length.
    @discardableResult
    private func consumeElapsedTime(allowAutomaticNextSession: Bool = true) -> Bool {
        guard isTimerRunning, let previous = lastTickUptime else { return false }
        let nowUptime = clock.uptime
        let elapsed = max(0, nowUptime - previous)
        lastTickUptime = nowUptime
        let credited = min(elapsed, remainingTime)
        if timerState == .onBreak {
            breakSeconds += credited
            totalBreakTime = Int(breakSeconds)
        }
        remainingTime = max(0, remainingTime - credited)
        guard remainingTime <= 0 else { return false }

        // Attribute a delayed completion to its actual boundary, including midnight.
        let completedAt = clock.now.addingTimeInterval(-(elapsed - credited))
        finishPhase(wasSkipped: false, at: completedAt, allowAutomaticNextSession: allowAutomaticNextSession)
        // At most one phase completes per observation. We never invent unattended
        // subsequent phases during a long run-loop stall.
        return true
    }

    private func finishPhase(wasSkipped: Bool, at date: Date, allowAutomaticNextSession: Bool = true) {
        guard timerState != .stopped else { return }
        if timerState == .working {
            var reachedDailyGoal = false
            if wasSkipped {
                currentStreakPomodoros = 0
            } else {
                completedPomodoros += 1
                pomodorosInCycle += 1
                currentStreakPomodoros += 1
                let completionDay = dayKey(date)
                savedState.dailyCounts[completionDay, default: 0] += 1
                let completedThatDay = savedState.dailyCounts[completionDay, default: 0]
                if completedThatDay >= dailyGoal, savedState.lastGoalNotificationDay != completionDay {
                    savedState.lastGoalNotificationDay = completionDay
                    reachedDailyGoal = true
                    queueNotification(
                        title: NSLocalizedString("notification.goal_title", comment: ""),
                        body: String(format: NSLocalizedString("notification.goal_body", comment: ""), completedThatDay)
                    )
                }
            }
            timerState = .onBreak
            isWaitingForNextSession = false
            phaseDuration = breakDuration
            remainingTime = phaseDuration
            if !wasSkipped && !reachedDailyGoal {
                queueNotification(
                    title: NSLocalizedString("notification.break_title", comment: ""),
                    body: String(format: NSLocalizedString("notification.break_body", comment: ""), Int(breakDuration / 60))
                )
            }
        } else {
            // Only natural completion of a running break may opt into auto-start.
            // Ending a break manually or skipping it while paused always waits.
            let startsAutomatically = autoStartNextSession && isTimerRunning && !wasSkipped && allowAutomaticNextSession
            timerState = .working
            phaseDuration = workDuration
            remainingTime = phaseDuration
            isWaitingForNextSession = !startsAutomatically
            restoredSession = false
            if !startsAutomatically {
                stopRunning()
            }
            if !wasSkipped {
                queueNotification(
                    title: NSLocalizedString(startsAutomatically ? "notification.continue_title" : "notification.ready_title", comment: ""),
                    body: startsAutomatically
                        ? String(format: NSLocalizedString("notification.continue_body", comment: ""), savedState.dailyCounts[dayKey(clock.now), default: 0] + 1)
                        : NSLocalizedString("notification.ready_body", comment: "")
                )
            }
        }
        // Preserve a paused state across skip; never start a second rest timer.
        lastTickUptime = isTimerRunning ? clock.uptime : nil
        if !wasSkipped, soundEnabled, feedbackAllowed {
            feedback.append { SoundManager.shared.play(.ding) }
        }
    }

    private func stopRunning() {
        isTimerRunning = false
        lastTickUptime = nil
        timer?.cancel()
        timer = nil
    }

    private func startHeartbeatIfNeeded() {
        guard automaticTicks, isTimerRunning, timer == nil else { return }
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refreshDailyStatistics() {
        let today = calendar.startOfDay(for: clock.now)
        lastActiveDate = dayKey(today)
        todayPomodoros = savedState.dailyCounts[lastActiveDate, default: 0]
        var day = today
        if todayPomodoros < 4 {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while true {
            let key = dayKey(day)
            if key == savedState.legacyStreakEndDay {
                streak += savedState.legacyStreakCount
                break
            }
            guard savedState.dailyCounts[key, default: 0] >= 4 else { break }
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        consecutiveDays = streak
    }

    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func checkAchievements() {
        let earned: [(AchievementType, Bool)] = [
            (.novice, completedPomodoros >= AchievementType.novice.threshold),
            (.efficient, completedPomodoros >= AchievementType.efficient.threshold),
            (.master, completedPomodoros >= AchievementType.master.threshold),
            (.habit, consecutiveDays >= AchievementType.habit.threshold),
            (.deepWork, currentStreakPomodoros >= AchievementType.deepWork.threshold),
            (.partyKing, totalBreakTime >= AchievementType.partyKing.threshold)
        ]
        for (achievement, isEarned) in earned where isEarned { unlock(achievement) }
    }

    private func unlock(_ type: AchievementType) {
        guard unlockedAchievements.insert(type.rawValue).inserted, feedbackAllowed else { return }
        if soundEnabled { feedback.append { SoundManager.shared.play(.achievement) } }
        if animationEnabled {
            feedback.append { [weak self] in
                self?.shouldFlashMenuBar = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.shouldFlashMenuBar = false
                }
            }
        }
    }

    #if DEBUG
    func debugUnlockAll() {
        update { AchievementType.allCases.forEach { unlock($0) } }
    }
    #endif

    private func snapshot() -> PersistedState {
        var state = savedState
        state.completedPomodoros = completedPomodoros
        state.unlockedAchievements = unlockedAchievements
        state.currentStreakPomodoros = currentStreakPomodoros
        state.totalBreakTime = breakSeconds
        state.pomodorosInCycle = pomodorosInCycle
        state.workDuration = workDuration
        state.breakDuration = breakDuration
        state.dailyGoal = dailyGoal
        state.soundEnabled = soundEnabled
        state.animationEnabled = animationEnabled
        state.notificationEnabled = notificationEnabled
        state.autoStartNextSession = autoStartNextSession
        state.isWaitingForNextSession = isWaitingForNextSession
        state.timer = timerState == .stopped ? nil : PersistedTimer(
            phase: timerState,
            remainingTime: remainingTime,
            phaseDuration: phaseDuration,
            wasRunning: isTimerRunning,
            savedAt: clock.now
        )
        return state
    }

    @discardableResult
    private func persist() -> Bool {
        let state = snapshot()
        // No idle disk churn on popover/day-change refreshes.
        guard state != savedState else { return true }
        do {
            try store.save(state)
            savedState = state
            return true
        } catch {
            failSafely()
            return false
        }
    }

    private func failSafely() {
        stopRunning()
        storageError = NSLocalizedString("storage.error", comment: "")
    }

    private func observeLifecycle() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.onMain { $0.handleSleep() } }
            .store(in: &lifecycleSubscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.onMain { $0.handleWake() } }
            .store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.onMain { $0.prepareForTermination() } }
            .store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &lifecycleSubscriptions)
    }

    private func onMain(_ action: (DogViewModel) -> Void) {
        // Finish the checkpoint before returning from sleep/termination notifications;
        // scheduling it for the next run-loop turn could defer it until after sleep.
        if Thread.isMainThread {
            action(self)
        } else {
            DispatchQueue.main.sync { action(self) }
        }
    }

    private func queueNotification(title: String, body: String) {
        guard feedbackAllowed, notificationEnabled else { return }
        feedback.append { [weak self] in self?.sendNotification(title: title, body: body) }
    }

    func sendNotification(title: String, body: String) {
        guard effectsEnabled, notificationEnabled, storageError == nil else { return }
        notificationSender?(title, body, soundEnabled)
    }
}
