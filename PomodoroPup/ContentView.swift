import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var vm: DogViewModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAchievements = false
    @State private var showEndConfirmation = false
    @State private var trophyShake = false

    private var goalReached: Bool { vm.todayPomodoros >= vm.dailyGoal }
    private var animationsAllowed: Bool { vm.animationEnabled && !reduceMotion }
    private var shouldAnimateAchievement: Bool { animationsAllowed && vm.shouldFlashMenuBar }
    private var hasActivePhase: Bool { vm.timerState != .stopped && !vm.isWaitingForNextSession }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Text(statusText).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { showAchievements = true } label: { Image(systemName: "trophy") }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("achievements.title", comment: ""))
                    .accessibilityLabel(NSLocalizedString("achievements.title", comment: ""))
                    .rotationEffect(.degrees(trophyShake ? -10 : 0))
                    .animation(animationsAllowed ? .easeInOut(duration: 0.08) : nil, value: trophyShake)
                    .task(id: shouldAnimateAchievement) {
                        trophyShake = false
                        guard shouldAnimateAchievement else { return }
                        defer { trophyShake = false }
                        for _ in 0..<6 {
                            guard !Task.isCancelled else { return }
                            trophyShake.toggle()
                            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                        }
                    }
                Menu {
                    if hasActivePhase {
                        Button(NSLocalizedString("button.end_reset", comment: ""), role: .destructive) {
                            showEndConfirmation = true
                        }.disabled(vm.storageError != nil)
                        Divider()
                    }
                    Button(NSLocalizedString("settings.title", comment: "")) { openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                        .disabled(vm.storageError != nil)
                    Divider()
                    Button(NSLocalizedString("button.quit", comment: "")) { NSApp.terminate(nil) }
                        .keyboardShortcut("q", modifiers: .command)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(NSLocalizedString("button.more", comment: ""))
                    .accessibilityLabel(NSLocalizedString("button.more", comment: ""))
            }

            DogView()
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08)))
                .accessibilityHidden(true)

            Text(vm.timeString)
                .font(.system(size: 48, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .accessibilityLabel(NSLocalizedString("timer.remaining", comment: ""))
                .accessibilityValue(vm.timeString)

            if let error = vm.storageError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if vm.restoredSession && hasActivePhase && !vm.isTimerRunning {
                Text(NSLocalizedString("status.recovery", comment: ""))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if vm.isWaitingForNextSession {
                Text(NSLocalizedString("status.waiting_detail", comment: ""))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button(primaryActionTitle) {
                    if vm.isTimerRunning { vm.pauseTimer() } else { vm.startTimer() }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(" ", modifiers: [])
                .help(NSLocalizedString("timer.space_shortcut", comment: ""))
                if vm.timerState == .onBreak {
                    Button(NSLocalizedString("button.end_break", comment: "")) { vm.skipPhase() }
                        .buttonStyle(.bordered).controlSize(.large)
                } else if vm.isWaitingForNextSession {
                    Button(NSLocalizedString("button.done_for_now", comment: "")) { vm.resetTimer() }
                        .buttonStyle(.bordered).controlSize(.large)
                }
            }.disabled(vm.storageError != nil)

            Divider()
            VStack(spacing: 8) {
                HStack {
                    Text(NSLocalizedString("stats.today", comment: ""))
                    Spacer()
                    Text(String(format: NSLocalizedString("stats.today_fraction", comment: ""), vm.todayPomodoros, vm.dailyGoal))
                        .monospacedDigit()
                }
                .font(.callout)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: NSLocalizedString("stats.today_progress", comment: ""), vm.todayPomodoros, vm.dailyGoal))
                ProgressView(value: Double(min(vm.todayPomodoros, vm.dailyGoal)), total: Double(vm.dailyGoal))
                    .accessibilityHidden(true)
                if goalReached {
                    Label(NSLocalizedString("goal.continue", comment: ""), systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20).frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { vm.refresh() }
        .onChange(of: vm.timerState) { _, _ in showEndConfirmation = false }
        .onChange(of: vm.storageError) { _, error in if error != nil { showEndConfirmation = false } }
        .onExitCommand {
            if showAchievements { showAchievements = false }
            else { NSApp.keyWindow?.orderOut(nil) }
        }
        .popover(isPresented: $showAchievements) { AchievementView() }
        .confirmationDialog(NSLocalizedString("timer.end_title", comment: ""), isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button(NSLocalizedString("button.end_reset", comment: ""), role: .destructive) { vm.resetTimer() }
            Button(NSLocalizedString("button.cancel", comment: ""), role: .cancel) {}
        } message: { Text(NSLocalizedString("timer.end_detail", comment: "")) }
    }

    private var statusText: String {
        if vm.isWaitingForNextSession { return NSLocalizedString("status.waiting_working", comment: "") }
        if !vm.isTimerRunning {
            if vm.timerState == .working { return NSLocalizedString("status.paused_working", comment: "") }
            if vm.timerState == .onBreak { return NSLocalizedString("status.paused_break", comment: "") }
        }
        switch vm.timerState {
        case .stopped: return NSLocalizedString(goalReached ? "goal.completed" : "status.ready", comment: "")
        case .working: return NSLocalizedString("status.working", comment: "")
        case .onBreak: return NSLocalizedString("status.break", comment: "")
        }
    }

    private var primaryActionTitle: String {
        if vm.isTimerRunning { return NSLocalizedString(vm.timerState == .onBreak ? "button.pause_break" : "button.pause", comment: "") }
        if vm.isWaitingForNextSession { return NSLocalizedString(goalReached ? "button.start_again" : "button.start_next", comment: "") }
        if vm.timerState == .onBreak { return NSLocalizedString("button.resume_break", comment: "") }
        if vm.timerState == .working { return NSLocalizedString("button.resume", comment: "") }
        if goalReached { return NSLocalizedString("button.start_again", comment: "") }
        return String(format: NSLocalizedString("button.start_minutes", comment: ""), Int(vm.workDuration / 60))
    }
}

struct AchievementView: View {
    @EnvironmentObject var vm: DogViewModel
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("achievements.title", comment: "")).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
                    .accessibilityLabel(NSLocalizedString("button.close", comment: ""))
                    .help(NSLocalizedString("button.close", comment: ""))
            }
            if let next = nextMilestone {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: NSLocalizedString("achievements.until", comment: ""), next.displayName)).font(.callout)
                    ProgressView(value: Double(min(vm.completedPomodoros, next.threshold)), total: Double(next.threshold))
                    Text(String(format: NSLocalizedString("achievements.progress", comment: ""), vm.completedPomodoros, next.threshold))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(AchievementType.allCases, id: \.self) { achievement in
                        achievementCard(achievement)
                    }
                }.padding(.vertical, 4)
            }
        }
        .padding(20).frame(width: 380, height: 470)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { dismiss() }
    }

    private var nextMilestone: AchievementType? {
        [.novice, .efficient, .master].first { !vm.unlockedAchievements.contains($0.rawValue) }
    }

    private func achievementCard(_ achievement: AchievementType) -> some View {
        let isUnlocked = vm.unlockedAchievements.contains(achievement.rawValue)
        return VStack(spacing: 8) {
            ZStack {
                Circle().fill(.white).frame(width: 52, height: 52)
                if isUnlocked {
                    Image(achievement.rawValue).resizable().renderingMode(.template)
                        .foregroundStyle(.black).scaledToFit().frame(width: 30, height: 30)
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(Color(nsColor: .darkGray))
                }
            }
            Text(achievement.displayName).font(.callout.weight(.semibold))
            Text(achievement.description).font(.system(size: 12))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString(isUnlocked ? "achievements.unlocked" : "achievements.locked", comment: ""))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}
