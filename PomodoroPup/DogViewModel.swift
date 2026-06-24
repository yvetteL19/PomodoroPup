import SwiftUI
import Combine
import UserNotifications

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
        didSet {
            // 验证工作时长在合理范围内 (1-120分钟)
            let clamped = max(60, min(workDuration, 120 * 60))
            if workDuration != clamped {
                workDuration = clamped
                return  // 避免重复执行
            }
            saveState()
            // 如果当前是停止状态或工作状态但未运行，同步更新显示时间
            if timerState == .stopped || (timerState == .working && !isTimerRunning) {
                remainingTime = workDuration
            }
        }
    }
    @Published var breakDuration: TimeInterval = 5 * 60 {
        didSet {
            // 验证休息时长在合理范围内 (1-60分钟)
            let clamped = max(60, min(breakDuration, 60 * 60))
            if breakDuration != clamped {
                breakDuration = clamped
                return  // 避免重复执行
            }
            saveState()
            // 如果当前是休息状态且未运行，同步更新显示时间
            if timerState == .onBreak && !isTimerRunning {
                remainingTime = breakDuration
            }
        }
    }
    @Published var dailyGoal: Int = 4 {
        didSet {
            // 验证每日目标在合理范围内 (1-20个)
            let clamped = max(1, min(dailyGoal, 20))
            if dailyGoal != clamped {
                dailyGoal = clamped
                return  // 避免重复执行
            }
            saveState()
        }
    }
    @Published var soundEnabled: Bool = true {
        didSet { saveState() }
    }
    @Published var animationEnabled: Bool = true {
        didSet { saveState() }
    }
    @Published var notificationEnabled: Bool = true {
        didSet { saveState() }
    }

    // 动画触发
    @Published var shouldFlashMenuBar: Bool = false

    // 计时器运行状态
    @Published var isTimerRunning: Bool = false

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
    private let kBreakDuration = "breakDuration"
    private let kDailyGoal = "dailyGoal"
    private let kSoundEnabled = "soundEnabled"
    private let kAnimationEnabled = "animationEnabled"
    private let kNotificationEnabled = "notificationEnabled"

    init() {
        loadState()
        checkDailyReset()

        // App启动时，如果计时器没有在运行，重置到stopped状态
        if !isTimerRunning {
            timerState = .stopped
            remainingTime = workDuration
        }
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
        defaults.set(breakDuration, forKey: kBreakDuration)
        defaults.set(dailyGoal, forKey: kDailyGoal)
        defaults.set(soundEnabled, forKey: kSoundEnabled)
        defaults.set(animationEnabled, forKey: kAnimationEnabled)
        defaults.set(notificationEnabled, forKey: kNotificationEnabled)
    }

    private func loadState() {
        let defaults = UserDefaults.standard

        if let stateRaw = defaults.string(forKey: kTimerState),
           let state = TimerState(rawValue: stateRaw) {
            timerState = state
        }

        // 加载统计数据（确保非负值）
        completedPomodoros = max(0, defaults.integer(forKey: kCompletedPomodoros))

        if let achievements = defaults.array(forKey: kUnlockedAchievements) as? [String] {
            unlockedAchievements = Set(achievements)
        }

        consecutiveDays = max(0, defaults.integer(forKey: kConsecutiveDays))
        currentStreakPomodoros = max(0, defaults.integer(forKey: kCurrentStreakPomodoros))
        totalBreakTime = max(0, defaults.integer(forKey: kTotalBreakTime))
        pomodorosInCycle = max(0, defaults.integer(forKey: kPomodorosInCycle))
        todayPomodoros = max(0, defaults.integer(forKey: kTodayPomodoros))
        lastActiveDate = defaults.string(forKey: kLastActiveDate) ?? ""

        // 设置项（带默认值和验证）
        let savedWorkDuration = defaults.double(forKey: kWorkDuration)
        if savedWorkDuration >= 60 && savedWorkDuration <= 120 * 60 {
            workDuration = savedWorkDuration
        }

        let savedBreakDuration = defaults.double(forKey: kBreakDuration)
        if savedBreakDuration >= 60 && savedBreakDuration <= 60 * 60 {
            breakDuration = savedBreakDuration
        }

        let savedDailyGoal = defaults.integer(forKey: kDailyGoal)
        if savedDailyGoal >= 1 && savedDailyGoal <= 20 {
            dailyGoal = savedDailyGoal
        }

        if defaults.object(forKey: kSoundEnabled) != nil {
            soundEnabled = defaults.bool(forKey: kSoundEnabled)
        }

        if defaults.object(forKey: kAnimationEnabled) != nil {
            animationEnabled = defaults.bool(forKey: kAnimationEnabled)
        }

        if defaults.object(forKey: kNotificationEnabled) != nil {
            notificationEnabled = defaults.bool(forKey: kNotificationEnabled)
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
            pomodorosInCycle = 0  // 新一天重置周期计数
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
            isTimerRunning = true
        }

        // 如果是休息状态，开始计时休息时长
        if timerState == .onBreak {
            startBreakTimeTracking()
        }
    }

    func pauseTimer() {
        timer?.cancel()
        timer = nil
        breakTimeTimer?.cancel()
        breakTimeTimer = nil
        isTimerRunning = false
    }

    func skipPhase() {
        completePhase(wasSkipped: true)
    }

    func resetTimer() {
        pauseTimer()
        timerState = .stopped
        remainingTime = workDuration
        isTimerRunning = false
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
            // 无论跳过与否，都计入周期
            pomodorosInCycle += 1

            if !wasSkipped {
                // 只有完成的才计入有效番茄数
                completedPomodoros += 1
                todayPomodoros += 1
                currentStreakPomodoros += 1
                checkAchievements()
            } else {
                // 跳过会重置连续番茄计数
                currentStreakPomodoros = 0
            }

            // 进入休息
            timerState = .onBreak
            remainingTime = breakDuration

            // 播放音效：汪！
            if soundEnabled {
                SoundManager.shared.play(.ding)
            }

            // 发送休息通知
            sendNotification(
                title: NSLocalizedString("notification.break_title", comment: ""),
                body: NSLocalizedString("notification.break_body", comment: "")
            )

            // 开始计时休息时长
            startBreakTimeTracking()

        } else {
            // 休息结束
            breakTimeTimer?.cancel()
            breakTimeTimer = nil

            // 检查是否完成番茄钟周期
            if pomodorosInCycle >= dailyGoal {
                // 达到周期目标，停止计时器（但不重置计数，让用户看到完成状态）
                timer?.cancel()
                timer = nil
                isTimerRunning = false
                timerState = .stopped
                remainingTime = workDuration
                // 保留 pomodorosInCycle 的值，让进度指示器显示完成状态

                // 发送目标完成通知
                sendNotification(
                    title: NSLocalizedString("notification.goal_title", comment: ""),
                    body: String(format: NSLocalizedString("notification.goal_body", comment: ""), dailyGoal)
                )

                print("🎉 完成\(dailyGoal)轮番茄钟周期！")
            } else {
                // 未完成周期，自动进入下一个工作番茄
                timerState = .working
                remainingTime = workDuration

                // 发送继续工作通知
                sendNotification(
                    title: NSLocalizedString("notification.continue_title", comment: ""),
                    body: String(format: NSLocalizedString("notification.continue_body", comment: ""), pomodorosInCycle + 1)
                )

                print("💪 开始第\(pomodorosInCycle + 1)个番茄")
            }

            // 播放音效：汪！
            if soundEnabled {
                SoundManager.shared.play(.ding)
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

            // 触发奖杯抖动动画
            shouldFlashMenuBar = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.shouldFlashMenuBar = false
            }
        }
    }

    func debugUnlockAll() {
        AchievementType.allCases.forEach { unlock($0) }
    }

    // --- 通知功能 ---

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ 通知权限请求失败: \(error.localizedDescription)")
            }
            if granted {
                print("✅ 通知权限已授予")
            } else {
                print("⚠️ 用户拒绝通知权限")
            }
        }
    }

    func sendNotification(title: String, body: String) {
        // 检查用户是否在设置中启用了通知
        guard notificationEnabled else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 通知发送失败: \(error.localizedDescription)")
            }
        }
    }
}
