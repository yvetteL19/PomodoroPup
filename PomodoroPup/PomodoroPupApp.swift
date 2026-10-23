import SwiftUI
import UserNotifications

@main
struct PomodoroPupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appDelegate.dogViewModel)
                .environmentObject(appDelegate.notificationService)
        } label: {
            MenuBarLabel(vm: appDelegate.dogViewModel)
        }
        .menuBarExtraStyle(.window)
        .commands {
            ApplicationCommands()
        }

        Settings {
            SettingsWindowContent(vm: appDelegate.dogViewModel, notifications: appDelegate.notificationService)
        }
        .windowResizability(.contentSize)
    }
}

private struct ApplicationCommands: Commands {
    var body: some Commands {
        // These are ordinary application commands, active only when this app
        // has focus. No global keyboard monitor takes keys from another app.
        // The Settings scene supplies the standard Settings… / Command-comma item.
        // Adding another SettingsLink here duplicates it in the native app menu.
        CommandGroup(replacing: .appTermination) {
            Button(NSLocalizedString("button.quit", comment: "")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

private struct SettingsWindowContent: View {
    @ObservedObject var vm: DogViewModel
    @ObservedObject var notifications: NotificationService

    var body: some View {
        SettingsView()
            .environmentObject(vm)
            .environmentObject(notifications)
    }
}

// 菜单栏标签（支持闪烁效果）
struct MenuBarLabel: View {
    @ObservedObject var vm: DogViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashOpacity: Double = 1.0

    private var isPaused: Bool {
        vm.timerState != .stopped && !vm.isTimerRunning && !vm.isWaitingForNextSession
    }

    private var animationsAllowed: Bool {
        vm.animationEnabled && !reduceMotion
    }

    private var shouldAnimateAchievement: Bool {
        animationsAllowed && vm.shouldFlashMenuBar
    }

    private var statusText: String {
        if let error = vm.storageError { return error }
        if vm.isWaitingForNextSession {
            return NSLocalizedString("status.waiting_working", comment: "")
        }
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
            if vm.storageError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
            } else if vm.isWaitingForNextSession {
                Image(systemName: "play.circle")
                    .font(.system(size: 14))
            } else if isPaused {
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let notificationService = NotificationService()
    lazy var dogViewModel: DogViewModel = {
        let notifications = notificationService
        return DogViewModel(notificationSender: { title, body, sound in
            Task { @MainActor in
                await notifications.send(title: title, body: body, soundEnabled: sound)
            }
        })
    }()
    private var onboardingWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { await notificationService.refresh() }
        if dogViewModel.storageError == nil,
           dogViewModel.timerState == .stopped,
           !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            // A menu-bar-only app has no initial WindowGroup. Present this window
            // explicitly instead of waiting for the user to discover the menu icon.
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        dogViewModel.refresh()
        Task { await notificationService.refresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dogViewModel.prepareForTermination()
    }

    private func showOnboarding() {
        // A user may start from the menu before this deferred presentation runs.
        // A recovered or already active phase must keep its own duration and UI.
        guard dogViewModel.timerState == .stopped, dogViewModel.storageError == nil else { return }
        guard onboardingWindowController == nil else {
            onboardingWindowController?.showWindow(nil)
            return
        }
        let content = OnboardingView(showOnboarding: .constant(true), isWindow: true, onComplete: { [weak self] in
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil
        })
        .environmentObject(dogViewModel)
        .environmentObject(notificationService)
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = [.minSize, .intrinsicContentSize]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("onboarding.welcome.title", comment: "")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
}
