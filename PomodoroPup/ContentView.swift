import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: DogViewModel
    @State private var showAchievements = false
    @State private var showSettings = false

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

                // 调试：一键解锁
                Button(action: { vm.debugUnlockAll() }) {
                    Image(systemName: "hammer.fill")
                }.buttonStyle(.plain)

                // 成就墙按钮
                Button(action: { showAchievements.toggle() }) {
                    Image(systemName: "trophy")
                }.buttonStyle(.plain)
            }
            .padding([.top, .horizontal])

            // 小狗视图
            DogView()

            // 倒计时
            Text(vm.timeString)
                .font(.system(size: 48, weight: .bold, design: .monospaced))

            // 按钮区
            HStack(spacing: 12) {
                if vm.timerState == .stopped {
                    Button("开始专注") { vm.startTimer() }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("暂停") { vm.pauseTimer() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("跳过") { vm.skipPhase() }
                        .buttonStyle(SecondaryButtonStyle())
                    if vm.timerState == .working {
                        Button("重置") { vm.resetTimer() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(.bottom)

            Text("累计完成: \(vm.completedPomodoros) 🍅")
                .font(.caption).foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
        .frame(width: 320)
        .background(Color.white)
        .popover(isPresented: $showAchievements) {
            AchievementView()
        }
        .popover(isPresented: $showSettings) {
            SettingsView()
        }
    }

    var statusText: String {
        switch vm.timerState {
        case .stopped: return "准备好了吗？"
        case .working: return "专注于工作中..."
        case .shortBreak, .longBreak: return "休息一下吧！"
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
            Text("成就墙").font(.headline).padding(.top)

            // 进度条 - 显示到下一个里程碑的进度
            if let nextMilestone = getNextMilestone() {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("距离 \(nextMilestone.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(vm.completedPomodoros)/\(nextMilestone.threshold)")
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
