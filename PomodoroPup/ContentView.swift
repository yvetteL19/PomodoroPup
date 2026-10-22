import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: DogViewModel
    @Environment(\.openWindow) var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAchievements = false
    @State private var showSettings = false
    @State private var trophyShake = false

    var body: some View {
        VStack(spacing: 16) {
            // 顶部栏
            HStack {
                Text(statusText).foregroundColor(.gray)
                Spacer()

                // 设置按钮
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain)
                .disabled(vm.storageError != nil)

                // 成就墙按钮
                Button(action: { showAchievements.toggle() }) {
                    Image(systemName: "trophy")
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(trophyShake ? -10 : 0))
                .animation(animationsAllowed ? .easeInOut(duration: 0.08) : nil, value: trophyShake)
                .task(id: shouldAnimateAchievement) {
                    trophyShake = false
                    guard shouldAnimateAchievement else { return }
                    defer { trophyShake = false }
                    for _ in 0..<6 {
                        guard !Task.isCancelled else { return }
                        trophyShake.toggle()
                        do {
                            try await Task.sleep(for: .milliseconds(80))
                        } catch { return }
                    }
                }
            }
            .padding([.top, .horizontal])

            // 小狗视图
            DogView()

            // 倒计时
            Text(vm.timeString)
                .font(.system(size: 48, weight: .bold, design: .monospaced))

            if let storageError = vm.storageError {
                Text(storageError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if vm.restoredSession && vm.timerState != .stopped && !vm.isTimerRunning {
                Text(NSLocalizedString("status.recovery", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // 今日有效完成数，不包含跳过的阶段。
            HStack(spacing: 4) {
                ForEach(0..<vm.dailyGoal, id: \.self) { index in
                    Circle()
                        .fill(index < vm.todayPomodoros ? Color.black : Color.gray.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: NSLocalizedString("stats.today_progress", comment: ""), vm.todayPomodoros, vm.dailyGoal))

            // 按钮区
            HStack(spacing: 12) {
                if vm.timerState == .stopped {
                    Button(NSLocalizedString("button.start", comment: "")) { vm.startTimer() }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    if vm.isTimerRunning {
                        Button(NSLocalizedString("button.pause", comment: "")) { vm.pauseTimer() }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button(NSLocalizedString("button.resume", comment: "")) { vm.startTimer() }
                            .buttonStyle(PrimaryButtonStyle())
                    }

                    Button(NSLocalizedString("button.skip", comment: "")) { vm.skipPhase() }
                        .buttonStyle(SecondaryButtonStyle())

                    // 重置按钮 - 在工作和休息时都可用
                    Button(NSLocalizedString("button.reset", comment: "")) { vm.resetTimer() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .disabled(vm.storageError != nil)
            .padding(.bottom)

            Text(String(format: NSLocalizedString("stats.total", comment: ""), vm.completedPomodoros))
                .font(.caption).foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
        .frame(width: 320)
        .background(Color.white)
        .onAppear {
            vm.refresh()
            // 首次启动时打开独立的 Onboarding 窗口
            if vm.storageError == nil && !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                openWindow(id: "onboarding")
            }
        }
        .onChange(of: vm.storageError) { _, error in
            if error != nil { showSettings = false }
        }
        .popover(isPresented: $showAchievements) {
            AchievementView()
        }
        .popover(isPresented: $showSettings) {
            SettingsView()
                .disabled(vm.storageError != nil)
        }
    }

    private var animationsAllowed: Bool {
        vm.animationEnabled && !reduceMotion
    }

    private var shouldAnimateAchievement: Bool {
        animationsAllowed && vm.shouldFlashMenuBar
    }

    var statusText: String {
        if !vm.isTimerRunning {
            if vm.timerState == .working {
                return NSLocalizedString("status.paused_working", comment: "")
            }
            if vm.timerState == .onBreak {
                return NSLocalizedString("status.paused_break", comment: "")
            }
        }
        switch vm.timerState {
        case .stopped: return NSLocalizedString("status.ready", comment: "")
        case .working: return NSLocalizedString("status.working", comment: "")
        case .onBreak: return NSLocalizedString("status.break", comment: "")
        }
    }
}

// 简单的黑色按钮样式
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.black)
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// 次要按钮样式
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.black)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// --- 成就墙视图 ---
struct AchievementView: View {
    @EnvironmentObject var vm: DogViewModel
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("achievements.title", comment: "")).font(.headline).padding(.top)

            // 进度条 - 显示到下一个里程碑的进度
            if let nextMilestone = getNextMilestone() {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(format: NSLocalizedString("achievements.until", comment: ""), nextMilestone.displayName))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: NSLocalizedString("achievements.progress", comment: ""), vm.completedPomodoros, nextMilestone.threshold))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                                .cornerRadius(3)

                            Rectangle()
                                .fill(Color.black)
                                .frame(width: progressWidth(for: nextMilestone, in: geometry.size.width), height: 6)
                                .cornerRadius(3)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal)
            }

            // 成就网格
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(AchievementType.allCases, id: \.self) { achievement in
                    VStack(spacing: 6) {
                        let isUnlocked = vm.unlockedAchievements.contains(achievement.rawValue)
                        ZStack {
                            Circle().stroke(Color.black.opacity(0.1), lineWidth: 2).frame(width: 50, height: 50)
                            if isUnlocked {
                                Image(achievement.rawValue)
                                    .resizable().renderingMode(.template).foregroundColor(.black)
                                    .scaledToFit().frame(width: 30, height: 30)
                            } else {
                                Image(systemName: "lock.fill").foregroundColor(.gray.opacity(0.3))
                            }
                        }
                        Text(achievement.displayName)
                            .font(.caption)
                            .bold()
                            .opacity(isUnlocked ? 1 : 0.5)
                        Text(achievement.description)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
            }
            .padding()
        }
        .frame(width: 340, height: 380)
    }

    // 获取下一个未解锁的里程碑成就
    func getNextMilestone() -> AchievementType? {
        let milestones: [AchievementType] = [.novice, .efficient, .master]
        return milestones.first { !vm.unlockedAchievements.contains($0.rawValue) }
    }

    // 计算进度条宽度
    func progressWidth(for milestone: AchievementType, in totalWidth: CGFloat) -> CGFloat {
        let progress = Double(vm.completedPomodoros) / Double(milestone.threshold)
        return totalWidth * CGFloat(min(progress, 1.0))
    }
}
