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
    @State private var flashOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 6) {
            // 1. 状态图标逻辑
            if vm.timerState == .stopped {
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
        .onChange(of: vm.shouldFlashMenuBar) { _, shouldFlash in
            if shouldFlash {
                // 闪烁3次
                flashMenuBar()
            }
        }
    }

    private func flashMenuBar() {
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
            withAnimation(.easeInOut(duration: 0.15)) {
                flashOpacity = flashOpacity == 1.0 ? 0.3 : 1.0
            }
            count += 1
            if count >= 6 { // 3次闪烁 = 6次切换
                timer.invalidate()
                flashOpacity = 1.0
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
