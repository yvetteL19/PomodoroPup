import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: DogViewModel
    @State private var showAchievements = false
    @State private var showSettings = false
    @State private var trophyShake = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

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

                #if DEBUG
                // 调试：一键解锁
                Button(action: { vm.debugUnlockAll() }) {
                    Image(systemName: "hammer.fill")
                }.buttonStyle(.plain)
                #endif

                // 成就墙按钮
                Button(action: { showAchievements.toggle() }) {
                    Image(systemName: "trophy")
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(trophyShake ? -10 : 0))
                .animation(.default.repeatCount(6, autoreverses: true).speed(6), value: trophyShake)
                .onChange(of: vm.shouldFlashMenuBar) { _, shouldFlash in
                    if shouldFlash {
                        trophyShake = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            trophyShake = false
                        }
                    }
                }
            }
            .padding([.top, .horizontal])

            // 小狗视图
            DogView()

            // 倒计时
            Text(vm.timeString)
                .font(.system(size: 48, weight: .bold, design: .monospaced))

            // 周期进度指示器
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<vm.dailyGoal, id: \.self) { index in
                        Circle()
                            .fill(index < vm.pomodorosInCycle ? Color.black : Color.gray.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }

                // 目标完成提示
                if vm.pomodorosInCycle >= vm.dailyGoal {
                    Text("🎉 " + NSLocalizedString("goal.completed", comment: ""))
                        .font(.caption)
                        .foregroundColor(.green)
                        .bold()
                }
            }
            .padding(.top, 4)

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
            .padding(.bottom)

            Text(String(format: NSLocalizedString("stats.total", comment: ""), vm.completedPomodoros))
                .font(.caption).foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
        .frame(width: 320)
        .background(Color.white)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(showOnboarding: $showOnboarding)
                .environmentObject(vm)
        }
        .popover(isPresented: $showAchievements) {
            AchievementView()
        }
        .popover(isPresented: $showSettings) {
            SettingsView()
        }
    }

    var statusText: String {
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
