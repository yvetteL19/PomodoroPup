import SwiftUI
import UserNotifications

@main
struct PomodoroPupApp: App {
    // 初始化 ViewModel
    @StateObject var dogViewModel = DogViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // macOS 菜单栏应用核心配置
        MenuBarExtra {
            // 点击菜单栏图标弹出的主视图
            ContentView()
                .environmentObject(dogViewModel)
        } label: {
            // --- 菜单栏常驻显示区域 ---
            MenuBarLabel(vm: dogViewModel)
        }
        .menuBarExtraStyle(.window) // 下拉窗口样式

        // 独立的 Onboarding 窗口
        Window("Welcome", id: "onboarding") {
            OnboardingView(showOnboarding: .constant(true), isWindow: true)
                .environmentObject(dogViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// 菜单栏标签（支持闪烁效果）
struct MenuBarLabel: View {
    @ObservedObject var vm: DogViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashOpacity: Double = 1.0

    private var isPaused: Bool {
        vm.timerState != .stopped && !vm.isTimerRunning
    }

    private var animationsAllowed: Bool {
        vm.animationEnabled && !reduceMotion
    }

    private var shouldAnimateAchievement: Bool {
        animationsAllowed && vm.shouldFlashMenuBar
    }

    private var statusText: String {
        if isPaused {
            return NSLocalizedString(vm.timerState == .working ? "status.paused_working" : "status.paused_break", comment: "")
        }
        switch vm.timerState {
        case .stopped: return NSLocalizedString("status.ready", comment: "")
        case .working: return NSLocalizedString("status.working", comment: "")
        case .onBreak: return NSLocalizedString("status.break", comment: "")
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // 1. 状态图标逻辑
            if isPaused {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 14))
            } else if vm.timerState == .stopped {
                // 停止状态：使用系统图标 timer
                Image(systemName: "timer")
                    .font(.system(size: 14))

            } else if vm.timerState == .working {
                // 工作状态：使用系统的小脚印
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 14))

            } else {
                // 休息状态：使用系统图标 cup.and.saucer
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 13))
            }

            // 2. 倒计时文本
            Text(vm.timeString)
                .monospacedDigit() // 数字等宽，防止倒计时左右跳动
        }
        .opacity(flashOpacity)
        .animation(animationsAllowed ? .easeInOut(duration: 0.15) : nil, value: flashOpacity)
        .help(statusText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusText), \(vm.timeString)")
        .task(id: shouldAnimateAchievement) {
            flashOpacity = 1.0
            guard shouldAnimateAchievement else { return }
            defer { flashOpacity = 1.0 }
            for _ in 0..<6 {
                guard !Task.isCancelled else { return }
                flashOpacity = flashOpacity == 1.0 ? 0.3 : 1.0
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch { return }
            }
        }
    }
}

// AppDelegate - 处理前台通知显示
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // 允许在前台显示通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 即使 app 在前台也显示通知横幅和声音
        completionHandler([.banner, .sound])
    }
}
