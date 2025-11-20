import SwiftUI

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
                            HStack {
                                Text("工作时长")
                                Spacer()
                                Text("\(Int(vm.workDuration / 60)) 分钟")
                                    .foregroundColor(.secondary)
                                Stepper("", value: Binding(
                                    get: { vm.workDuration / 60 },
                                    set: { vm.workDuration = $0 * 60 }
                                ), in: 1...60)
                                .labelsHidden()
                            }

                            HStack {
                                Text("短休息时长")
                                Spacer()
                                Text("\(Int(vm.shortBreakDuration / 60)) 分钟")
                                    .foregroundColor(.secondary)
                                Stepper("", value: Binding(
                                    get: { vm.shortBreakDuration / 60 },
                                    set: { vm.shortBreakDuration = $0 * 60 }
                                ), in: 1...30)
                                .labelsHidden()
                            }

                            HStack {
                                Text("长休息时长")
                                Spacer()
                                Text("\(Int(vm.longBreakDuration / 60)) 分钟")
                                    .foregroundColor(.secondary)
                                Stepper("", value: Binding(
                                    get: { vm.longBreakDuration / 60 },
                                    set: { vm.longBreakDuration = $0 * 60 }
                                ), in: 5...60)
                                .labelsHidden()
                            }

                            HStack {
                                Text("长休息周期")
                                Spacer()
                                Text("每 \(vm.longBreakInterval) 个番茄")
                                    .foregroundColor(.secondary)
                                Stepper("", value: $vm.longBreakInterval, in: 2...10)
                                    .labelsHidden()
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
