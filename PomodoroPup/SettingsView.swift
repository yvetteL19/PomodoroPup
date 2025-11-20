import SwiftUI

// 时间设置行组件
struct DurationRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .onChange(of: value) { _, newValue in
                    // 限制输入范围
                    if newValue < range.lowerBound {
                        value = range.lowerBound
                    } else if newValue > range.upperBound {
                        value = range.upperBound
                    }
                }
            Text("分钟")
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
            Text("设置").font(.headline).padding(.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 时间设置
                    GroupBox(label: Label("时间设置", systemImage: "clock")) {
                        VStack(spacing: 12) {
                            DurationRow(
                                label: "工作时长",
                                value: Binding(
                                    get: { Int(vm.workDuration / 60) },
                                    set: { vm.workDuration = TimeInterval($0) * 60 }
                                ),
                                range: 1...120
                            )

                            DurationRow(
                                label: "短休息时长",
                                value: Binding(
                                    get: { Int(vm.shortBreakDuration / 60) },
                                    set: { vm.shortBreakDuration = TimeInterval($0) * 60 }
                                ),
                                range: 1...60
                            )

                            DurationRow(
                                label: "长休息时长",
                                value: Binding(
                                    get: { Int(vm.longBreakDuration / 60) },
                                    set: { vm.longBreakDuration = TimeInterval($0) * 60 }
                                ),
                                range: 5...120
                            )

                            HStack {
                                Text("长休息周期")
                                Spacer()
                                TextField("", value: $vm.longBreakInterval, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.center)
                                    .onChange(of: vm.longBreakInterval) { _, newValue in
                                        // 限制输入范围 2-10
                                        if newValue < 2 {
                                            vm.longBreakInterval = 2
                                        } else if newValue > 10 {
                                            vm.longBreakInterval = 10
                                        }
                                    }
                                Text("个番茄")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 陪伴模式
                    GroupBox(label: Label("陪伴模式", systemImage: "heart")) {
                        VStack(spacing: 12) {
                            Toggle(isOn: $vm.soundEnabled) {
                                HStack {
                                    Text("音效")
                                    Spacer()
                                    Text(vm.soundEnabled ? "开启" : "关闭")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }

                            Toggle(isOn: $vm.animationEnabled) {
                                HStack {
                                    Text("动画效果")
                                    Spacer()
                                    Text(vm.animationEnabled ? "开启" : "关闭")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 统计信息
                    GroupBox(label: Label("统计", systemImage: "chart.bar")) {
                        VStack(spacing: 8) {
                            HStack {
                                Text("累计番茄")
                                Spacer()
                                Text("\(vm.completedPomodoros)")
                                    .bold()
                            }

                            HStack {
                                Text("今日番茄")
                                Spacer()
                                Text("\(vm.todayPomodoros)")
                                    .bold()
                            }

                            HStack {
                                Text("连续出勤")
                                Spacer()
                                Text("\(vm.consecutiveDays) 天")
                                    .bold()
                            }

                            HStack {
                                Text("连续专注")
                                Spacer()
                                Text("\(vm.currentStreakPomodoros) 次")
                                    .bold()
                            }

                            HStack {
                                Text("累计休息")
                                Spacer()
                                Text("\(vm.totalBreakTime / 60) 分钟")
                                    .bold()
                            }
                        }
                        .padding(.vertical, 4)
                        .font(.caption)
                    }
                }
                .padding()
            }

            Button("完成") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom)
        }
        .frame(width: 320, height: 480)
    }
}
