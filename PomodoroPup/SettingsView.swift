import SwiftUI

// 时间设置行组件
struct DurationRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .onAppear {
                    textValue = String(value)
                }
                .onChange(of: value) { _, newValue in
                    if !isFocused {
                        textValue = String(newValue)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        // 失去焦点时验证
                        if let num = Int(textValue), range.contains(num) {
                            value = num
                        } else {
                            // 无效输入，恢复原值
                            textValue = String(value)
                        }
                    }
                }
                .onSubmit {
                    // 按回车时验证
                    if let num = Int(textValue), range.contains(num) {
                        value = num
                    } else {
                        textValue = String(value)
                    }
                }
            Text(NSLocalizedString("settings.minutes", comment: ""))
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

// 番茄钟周期设置行组件
struct DurationRowGoal: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .onAppear {
                    textValue = String(value)
                }
                .onChange(of: value) { _, newValue in
                    if !isFocused {
                        textValue = String(newValue)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        if let num = Int(textValue), range.contains(num) {
                            value = num
                        } else {
                            textValue = String(value)
                        }
                    }
                }
                .onSubmit {
                    if let num = Int(textValue), range.contains(num) {
                        value = num
                    } else {
                        textValue = String(value)
                    }
                }
            Text(NSLocalizedString("settings.rounds", comment: ""))
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var vm: DogViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("settings.title", comment: "")).font(.headline).padding(.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 时间设置
                    GroupBox(label: Label(NSLocalizedString("settings.time", comment: ""), systemImage: "clock")) {
                        VStack(spacing: 12) {
                            DurationRow(
                                label: NSLocalizedString("settings.focus_duration", comment: ""),
                                value: Binding(
                                    get: { Int(vm.workDuration / 60) },
                                    set: { vm.workDuration = TimeInterval($0) * 60 }
                                ),
                                range: 1...120
                            )

                            DurationRow(
                                label: NSLocalizedString("settings.break_duration", comment: ""),
                                value: Binding(
                                    get: { Int(vm.breakDuration / 60) },
                                    set: { vm.breakDuration = TimeInterval($0) * 60 }
                                ),
                                range: 1...60
                            )

                            DurationRowGoal(
                                label: NSLocalizedString("settings.cycles", comment: ""),
                                value: $vm.dailyGoal,
                                range: 1...20
                            )
                        }
                        .padding(.vertical, 4)
                    }

                    // 陪伴模式
                    GroupBox(label: Label(NSLocalizedString("settings.companion", comment: ""), systemImage: "heart")) {
                        VStack(spacing: 12) {
                            Toggle(isOn: $vm.soundEnabled) {
                                HStack {
                                    Text(NSLocalizedString("settings.sound", comment: ""))
                                    Spacer()
                                    Text(vm.soundEnabled ? NSLocalizedString("settings.on", comment: "") : NSLocalizedString("settings.off", comment: ""))
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }

                            Toggle(isOn: $vm.animationEnabled) {
                                HStack {
                                    Text(NSLocalizedString("settings.animations", comment: ""))
                                    Spacer()
                                    Text(vm.animationEnabled ? NSLocalizedString("settings.on", comment: "") : NSLocalizedString("settings.off", comment: ""))
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }

                            Toggle(isOn: $vm.notificationEnabled) {
                                HStack {
                                    Text(NSLocalizedString("settings.notifications", comment: ""))
                                    Spacer()
                                    Text(vm.notificationEnabled ? NSLocalizedString("settings.on", comment: "") : NSLocalizedString("settings.off", comment: ""))
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 统计信息
                    GroupBox(label: Label(NSLocalizedString("settings.statistics", comment: ""), systemImage: "chart.bar")) {
                        VStack(spacing: 8) {
                            HStack {
                                Text(NSLocalizedString("settings.total_pomodoros", comment: ""))
                                Spacer()
                                Text("\(vm.completedPomodoros)")
                                    .bold()
                            }

                            HStack {
                                Text(NSLocalizedString("settings.today", comment: ""))
                                Spacer()
                                Text("\(vm.todayPomodoros)")
                                    .bold()
                            }

                            HStack {
                                Text(NSLocalizedString("settings.streak_days", comment: ""))
                                Spacer()
                                Text("\(vm.consecutiveDays) \(NSLocalizedString("settings.days", comment: ""))")
                                    .bold()
                            }

                            HStack {
                                Text(NSLocalizedString("settings.streak_pomodoros", comment: ""))
                                Spacer()
                                Text("\(vm.currentStreakPomodoros) \(NSLocalizedString("settings.times", comment: ""))")
                                    .bold()
                            }

                            HStack {
                                Text(NSLocalizedString("settings.total_break", comment: ""))
                                Spacer()
                                Text("\(vm.totalBreakTime / 60) \(NSLocalizedString("settings.minutes_unit", comment: ""))")
                                    .bold()
                            }
                        }
                        .padding(.vertical, 4)
                        .font(.caption)
                    }
                }
                .padding()
            }

            Button(NSLocalizedString("settings.done", comment: "")) {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom)
        }
        .frame(width: 320, height: 480)
    }
}
