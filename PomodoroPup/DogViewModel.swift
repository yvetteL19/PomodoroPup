import SwiftUI
import Combine

// 状态定义
enum TimerState: String, Codable {
    case stopped, working, shortBreak, longBreak
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
        case .novice: return "萌新小狗"
        case .efficient: return "高效搭档"
        case .master: return "专注大师"
        case .habit: return "连续出勤"
        case .deepWork: return "深度黑客"
        case .partyKing: return "舞蹈之王"
        }
    }

    var description: String {
        switch self {
        case .novice: return "累计完成 10 个番茄"
        case .efficient: return "累计完成 50 个番茄"
        case .master: return "累计完成 200 个番茄"
        case .habit: return "连续 3 天每天至少完成 4 个番茄"
        case .deepWork: return "连续 3 个番茄未跳过"
        case .partyKing: return "休息时间累计 300 分钟"
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

class DogViewModel: ObservableObject {
    // UI 监听变量
    @Published var timerState: TimerState = .stopped {
        didSet { saveState() }
    }
    @Published var remainingTime: TimeInterval = 25 * 60
    @Published var completedPomodoros: Int = 0 {
        didSet { saveState() }
    }
    @Published var unlockedAchievements: Set<String> = [] {
        didSet { saveState() }
    }

    // 新增追踪变量
    @Published var consecutiveDays: Int = 0 {
        didSet { saveState() }
    }
    @Published var currentStreakPomodoros: Int = 0 {
        didSet { saveState() }
    }
    @Published var totalBreakTime: Int = 0 {
        didSet { saveState() }
    }
    @Published var pomodorosInCycle: Int = 0 {
        didSet { saveState() }
    }
    @Published var todayPomodoros: Int = 0 {
        didSet { saveState() }
    }
    @Published var lastActiveDate: String = "" {
        didSet { saveState() }
    }

    // 设置项
    @Published var workDuration: TimeInterval = 25 * 60 {
        didSet { saveState() }
    }
    @Published var shortBreakDuration: TimeInterval = 5 * 60 {
        didSet { saveState() }
    }
    @Published var longBreakDuration: TimeInterval = 15 * 60 {
        didSet { saveState() }
    }
    @Published var longBreakInterval: Int = 4 {
        didSet { saveState() }
    }
    @Published var soundEnabled: Bool = true {
        didSet { saveState() }
    }
    @Published var animationEnabled: Bool = true {
        didSet { saveState() }
    }

    // 动画触发
    @Published var shouldTriggerJumpAnimation: Bool = false
    @Published var shouldTriggerCollarAnimation: Bool = false
    @Published var shouldTriggerSparkleAnimation: Bool = false
    @Published var shouldFlashMenuBar: Bool = false

    private var timer: AnyCancellable?
    private var breakTimeTimer: AnyCancellable?

    // UserDefaults Keys
    private let kTimerState = "timerState"
    private let kCompletedPomodoros = "completedPomodoros"
    private let kUnlockedAchievements = "unlockedAchievements"
    private let kConsecutiveDays = "consecutiveDays"
    private let kCurrentStreakPomodoros = "currentStreakPomodoros"
    private let kTotalBreakTime = "totalBreakTime"
    private let kPomodorosInCycle = "pomodorosInCycle"
    private let kTodayPomodoros = "todayPomodoros"
    private let kLastActiveDate = "lastActiveDate"
    private let kWorkDuration = "workDuration"
    private let kShortBreakDuration = "shortBreakDuration"
    private let kLongBreakDuration = "longBreakDuration"
    private let kLongBreakInterval = "longBreakInterval"
    private let kSoundEnabled = "soundEnabled"
    private let kAnimationEnabled = "animationEnabled"

    init() {
        loadState()
        checkDailyReset()
    }

    // 格式化时间字符串
    var timeString: String {
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // --- 持久化 ---

    private func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(timerState.rawValue, forKey: kTimerState)
        defaults.set(completedPomodoros, forKey: kCompletedPomodoros)
        defaults.set(Array(unlockedAchievements), forKey: kUnlockedAchievements)
        defaults.set(consecutiveDays, forKey: kConsecutiveDays)
        defaults.set(currentStreakPomodoros, forKey: kCurrentStreakPomodoros)
        defaults.set(totalBreakTime, forKey: kTotalBreakTime)
        defaults.set(pomodorosInCycle, forKey: kPomodorosInCycle)
        defaults.set(todayPomodoros, forKey: kTodayPomodoros)
        defaults.set(lastActiveDate, forKey: kLastActiveDate)
        defaults.set(workDuration, forKey: kWorkDuration)
        defaults.set(shortBreakDuration, forKey: kShortBreakDuration)
        defaults.set(longBreakDuration, forKey: kLongBreakDuration)
        defaults.set(longBreakInterval, forKey: kLongBreakInterval)
        defaults.set(soundEnabled, forKey: kSoundEnabled)
        defaults.set(animationEnabled, forKey: kAnimationEnabled)
    }

    private func loadState() {
        let defaults = UserDefaults.standard

        if let stateRaw = defaults.string(forKey: kTimerState),
           let state = TimerState(rawValue: stateRaw) {
            timerState = state
        }

        completedPomodoros = defaults.integer(forKey: kCompletedPomodoros)

        if let achievements = defaults.array(forKey: kUnlockedAchievements) as? [String] {
            unlockedAchievements = Set(achievements)
        }

        consecutiveDays = defaults.integer(forKey: kConsecutiveDays)
        currentStreakPomodoros = defaults.integer(forKey: kCurrentStreakPomodoros)
        totalBreakTime = defaults.integer(forKey: kTotalBreakTime)
        pomodorosInCycle = defaults.integer(forKey: kPomodorosInCycle)
        todayPomodoros = defaults.integer(forKey: kTodayPomodoros)
        lastActiveDate = defaults.string(forKey: kLastActiveDate) ?? ""

        // 设置项（带默认值）
        let savedWorkDuration = defaults.double(forKey: kWorkDuration)
        if savedWorkDuration > 0 { workDuration = savedWorkDuration }

        let savedShortBreak = defaults.double(forKey: kShortBreakDuration)
        if savedShortBreak > 0 { shortBreakDuration = savedShortBreak }

        let savedLongBreak = defaults.double(forKey: kLongBreakDuration)
        if savedLongBreak > 0 { longBreakDuration = savedLongBreak }

        let savedInterval = defaults.integer(forKey: kLongBreakInterval)
        if savedInterval > 0 { longBreakInterval = savedInterval }

        if defaults.object(forKey: kSoundEnabled) != nil {
            soundEnabled = defaults.bool(forKey: kSoundEnabled)
        }

        if defaults.object(forKey: kAnimationEnabled) != nil {
            animationEnabled = defaults.bool(forKey: kAnimationEnabled)
        }

        // 恢复剩余时间
        remainingTime = workDuration
    }

    // 检查日期重置
    private func checkDailyReset() {
        let today = getTodayString()

        if lastActiveDate.isEmpty {
            // 首次启动
            lastActiveDate = today
            return
        }

        if lastActiveDate != today {
            // 新的一天
            if todayPomodoros >= 4 {
                // 昨天达成目标
                if isConsecutiveDay(from: lastActiveDate, to: today) {
                    consecutiveDays += 1
                } else {
                    consecutiveDays = 0
                }
            } else {
                // 昨天未达成
                consecutiveDays = 0
            }

            todayPomodoros = 0
            lastActiveDate = today
        }
    }

    private func getTodayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func isConsecutiveDay(from: String, to: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let fromDate = formatter.date(from: from),
              let toDate = formatter.date(from: to) else {
            return false
        }
        let days = Calendar.current.dateComponents([.day], from: fromDate, to: toDate).day ?? 0
        return days == 1
    }

    // --- 核心控制 ---

    func startTimer() {
        if timerState == .stopped {
            timerState = .working
            remainingTime = workDuration
        }
        if timer == nil {
            timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.tick() }
        }

        // 如果是休息状态，开始计时休息时长
        if timerState == .shortBreak || timerState == .longBreak {
            startBreakTimeTracking()
        }
    }

    func pauseTimer() {
        timer?.cancel()
        timer = nil
        breakTimeTimer?.cancel()
        breakTimeTimer = nil
    }

    func skipPhase() {
        // 跳过会重置连续番茄计数
        if timerState == .working {
            currentStreakPomodoros = 0
        }
        completePhase(wasSkipped: true)
    }

    func resetTimer() {
        pauseTimer()
        timerState = .stopped
        remainingTime = workDuration
    }

    private func tick() {
        if remainingTime > 0 {
            remainingTime -= 1
        } else {
            completePhase(wasSkipped: false)
        }
    }

    private func startBreakTimeTracking() {
        breakTimeTimer?.cancel()
        breakTimeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                self?.totalBreakTime += 1
            }
    }

    private func completePhase(wasSkipped: Bool) {
        if timerState == .working {
            // 工作结束 -> 休息
            if !wasSkipped {
                completedPomodoros += 1
                todayPomodoros += 1
                currentStreakPomodoros += 1
                pomodorosInCycle += 1
                checkAchievements()
            }

            // 触发跳跃动画
            if animationEnabled {
                shouldTriggerJumpAnimation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.shouldTriggerJumpAnimation = false
                }
            }

            // 判断长休息还是短休息
            if pomodorosInCycle >= longBreakInterval {
                timerState = .longBreak
                remainingTime = longBreakDuration
                pomodorosInCycle = 0
            } else {
                timerState = .shortBreak
                remainingTime = shortBreakDuration
            }

            // 播放音效：汪！
            if soundEnabled {
                SoundManager.shared.play(.bark)
            }

            // 开始计时休息时长
            startBreakTimeTracking()

        } else {
            // 休息结束 -> 停止
            breakTimeTimer?.cancel()
            breakTimeTimer = nil

            // 触发整理衣领动画
            if animationEnabled {
                shouldTriggerCollarAnimation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.shouldTriggerCollarAnimation = false
                }
            }

            timerState = .stopped
            remainingTime = workDuration

            // 播放音效：吁~
            if soundEnabled {
                SoundManager.shared.play(.sigh)
            }
        }
    }

    private func checkAchievements() {
        // 里程碑成就
        if completedPomodoros >= AchievementType.novice.threshold {
            unlock(.novice)
        }
        if completedPomodoros >= AchievementType.efficient.threshold {
            unlock(.efficient)
        }
        if completedPomodoros >= AchievementType.master.threshold {
            unlock(.master)
        }

        // 连续出勤
        checkDailyReset()
        if consecutiveDays >= AchievementType.habit.threshold {
            unlock(.habit)
        }

        // 深度黑客
        if currentStreakPomodoros >= AchievementType.deepWork.threshold {
            unlock(.deepWork)
        }

        // 舞蹈之王
        if totalBreakTime >= AchievementType.partyKing.threshold {
            unlock(.partyKing)
        }
    }

    private func unlock(_ type: AchievementType) {
        if !unlockedAchievements.contains(type.rawValue) {
            unlockedAchievements.insert(type.rawValue)

            // 播放音效：成就解锁
            if soundEnabled {
                SoundManager.shared.play(.achievement)
            }

            // 触发闪光动画
            if animationEnabled {
                shouldTriggerSparkleAnimation = true
                shouldFlashMenuBar = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.shouldTriggerSparkleAnimation = false
                    self.shouldFlashMenuBar = false
                }
            }
        }
    }

    func debugUnlockAll() {
        AchievementType.allCases.forEach { unlock($0) }
    }
}
