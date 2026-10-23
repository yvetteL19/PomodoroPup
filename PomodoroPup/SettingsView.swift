import SwiftUI
import AppKit

private struct NumberSettingRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    @State private var textValue = ""
    @State private var invalidInput = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                TextField(label, text: $textValue)
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .frame(width: 62).multilineTextAlignment(.trailing)
                    .focused($focused).accessibilityLabel(label)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                Text(unit).foregroundStyle(.secondary).frame(minWidth: 34, alignment: .leading)
                Stepper(label, value: $value, in: range).labelsHidden().fixedSize()
                    .accessibilityLabel(label)
            }
            if invalidInput {
                Text(String(format: NSLocalizedString("settings.valid_range", comment: ""), range.lowerBound, range.upperBound))
                    .font(.callout).foregroundStyle(.red)
            }
        }
        .onAppear { textValue = String(value) }
        .onChange(of: value) { _, newValue in
            // A stepper click may leave the text field focused. Keep its text in
            // sync so the next blur cannot write the old number back over the step.
            textValue = String(newValue)
            invalidInput = false
        }
    }

    private func commit() {
        guard let entered = Int(textValue), range.contains(entered) else {
            textValue = String(value)
            invalidInput = true
            return
        }
        invalidInput = false
        value = entered
    }
}

struct SettingsView: View {
    @EnvironmentObject var vm: DogViewModel
    @EnvironmentObject var notificationService: NotificationService

    var body: some View {
        VStack(spacing: 0) {
            if let error = vm.storageError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).padding()
            }
            Form {
                Section(NSLocalizedString("settings.time", comment: "")) {
                    NumberSettingRow(label: NSLocalizedString("settings.focus_duration", comment: ""),
                        value: Binding(get: { Int(vm.workDuration / 60) }, set: { vm.workDuration = Double($0) * 60 }),
                        range: 1...120, unit: NSLocalizedString("settings.minutes", comment: ""))
                    NumberSettingRow(label: NSLocalizedString("settings.break_duration", comment: ""),
                        value: Binding(get: { Int(vm.breakDuration / 60) }, set: { vm.breakDuration = Double($0) * 60 }),
                        range: 1...60, unit: NSLocalizedString("settings.minutes", comment: ""))
                    Text(NSLocalizedString("settings.duration_detail", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                    NumberSettingRow(label: NSLocalizedString("settings.daily_goal", comment: ""),
                        value: $vm.dailyGoal, range: 1...20,
                        unit: NSLocalizedString("settings.rounds", comment: ""))
                    Text(NSLocalizedString("settings.goal_detail", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle(NSLocalizedString("settings.auto_start", comment: ""), isOn: $vm.autoStartNextSession)
                    Text(NSLocalizedString("settings.auto_start_detail", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section(NSLocalizedString("settings.companion", comment: "")) {
                    Toggle(NSLocalizedString("settings.sound", comment: ""), isOn: $vm.soundEnabled)
                    Toggle(NSLocalizedString("settings.animations", comment: ""), isOn: $vm.animationEnabled)
                    Text(NSLocalizedString("settings.animations_detail", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section(NSLocalizedString("settings.notifications", comment: "")) {
                    Toggle(NSLocalizedString("settings.phase_reminders", comment: ""), isOn: $vm.notificationEnabled)
                    notificationControls
                }
                Section(NSLocalizedString("settings.statistics", comment: "")) {
                    LabeledContent(NSLocalizedString("settings.total_pomodoros", comment: ""), value: "\(vm.completedPomodoros)")
                    LabeledContent(NSLocalizedString("settings.today", comment: ""), value: "\(vm.todayPomodoros)")
                    LabeledContent(NSLocalizedString("settings.streak_days", comment: ""), value: "\(vm.consecutiveDays) \(NSLocalizedString("settings.days", comment: ""))")
                    LabeledContent(NSLocalizedString("settings.streak_pomodoros", comment: ""), value: "\(vm.currentStreakPomodoros)")
                    LabeledContent(NSLocalizedString("settings.total_break", comment: ""), value: "\(vm.totalBreakTime / 60) \(NSLocalizedString("settings.minutes_unit", comment: ""))")
                }
            }
            .formStyle(.grouped)
            .disabled(vm.storageError != nil)

            HStack {
                Spacer()
                Button(NSLocalizedString("button.close", comment: "")) { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(.cancelAction)
            }.padding()
        }
        .frame(width: 520, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await notificationService.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notificationService.refresh() }
        }
    }

    private var notificationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(notificationStatusText).font(.callout).foregroundStyle(.secondary)
            if notificationService.status == .notDetermined || notificationService.status == .error {
                Button(NSLocalizedString("onboarding.enable", comment: "")) {
                    Task { await notificationService.requestPermission() }
                }.disabled(!vm.notificationEnabled)
            } else if notificationService.status == .requesting {
                ProgressView().controlSize(.small)
            }
            if notificationService.status == .denied || notificationService.status == .alertsDisabled {
                Button(NSLocalizedString("notification.open_settings", comment: "")) {
                    notificationService.openSystemSettings()
                }
                Text(NSLocalizedString("notification.settings_path", comment: ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(NSLocalizedString("notification.test", comment: "")) {
                Task { await notificationService.sendTest(soundEnabled: vm.soundEnabled) }
            }
            .disabled(!vm.notificationEnabled || notificationService.status != .allowed)
            if let error = notificationService.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if let result = notificationService.testResult {
                Text(NSLocalizedString(testResultKey(result), comment: ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var notificationStatusText: String {
        let key: String
        switch notificationService.status {
        case .notDetermined: key = "notification.status_not_determined"
        case .allowed: key = vm.notificationEnabled ? "notification.status_allowed" : "notification.status_app_off"
        case .denied: key = "notification.status_denied"
        case .alertsDisabled: key = "notification.status_alerts_disabled"
        case .requesting: key = "notification.status_requesting"
        case .error: key = "notification.error_generic"
        }
        return NSLocalizedString(key, comment: "")
    }

    private func testResultKey(_ result: NotificationTestResult) -> String {
        switch result {
        case .sent: return "notification.test_sent"
        case .permissionRequired: return "notification.test_permission_required"
        case .failed: return "notification.test_failed"
        }
    }
}
