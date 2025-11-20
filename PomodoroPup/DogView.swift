import SwiftUI

struct DogView: View {
    @EnvironmentObject var vm: DogViewModel
    @State private var isBreathing = false
    @State private var isDancing = false
    @State private var jumpScale: CGFloat = 1.0
    @State private var collarAdjust: CGFloat = 0

    var body: some View {
        ZStack {
            // 状态判断
            if vm.timerState == .shortBreak || vm.timerState == .longBreak {
                // 休息状态：跳舞狗
                Image("dog_dance")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .offset(x: isDancing ? -8 : 8)
                    .rotationEffect(.degrees(isDancing ? -3 : 3))
                    .scaleEffect(jumpScale)
                    .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: isDancing)
                    .onAppear {
                        isDancing = true
                    }
                    .onChange(of: vm.timerState) { _, newState in
                        isDancing = (newState == .shortBreak || newState == .longBreak)
                    }
                    .onChange(of: vm.shouldTriggerJumpAnimation) { _, shouldJump in
                        if shouldJump {
                            // 跳跃动画：快速拉伸
                            withAnimation(.easeOut(duration: 0.1)) {
                                jumpScale = 1.15
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    jumpScale = 1.0
                                }
                            }
                        }
                    }
            } else {
                // 工作/停止状态：专注狗 + 装备
                ZStack {
                    Image("dog_focus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .offset(y: collarAdjust)

                    // --- 装备层 (环绕式布局) ---
                    // 眼镜：必须在脸上（最重要，保持原位）
                    if vm.unlockedAchievements.contains("icon_glasses") {
                        overlayImage("icon_glasses", w: 70, x: 0, y: -12 + collarAdjust)
                    }

                    // 皇冠：正上方（第二重要）
                    if vm.unlockedAchievements.contains("icon_crown") {
                        overlayImage("icon_crown", w: 50, x: 0, y: -115 + collarAdjust)
                    }

                    // 以下3个成就环绕分布
                    // 灯泡：右上方（1点钟方向）
                    if vm.unlockedAchievements.contains("icon_bulb") {
                        overlayImage("icon_bulb", w: 24, x: 100, y: -75 + collarAdjust)
                    }

                    // 骨头：左下方（7点钟方向）
                    if vm.unlockedAchievements.contains("icon_bone") {
                        overlayImage("icon_bone", w: 30, x: -95, y: 75 + collarAdjust, rotate: -20)
                    }

                    // 派对帽：左上方（11点钟方向）
                    if vm.unlockedAchievements.contains("icon_party") {
                         overlayImage("icon_party", w: 32, x: -100, y: -75 + collarAdjust, rotate: -10)
                    }

                    // 脚印徽章：右下方（5点钟方向）
                    if vm.unlockedAchievements.contains("icon_paw") {
                        overlayImage("icon_paw", w: 26, x: 95, y: 75 + collarAdjust, rotate: 15)
                    }

                    // 闪光动画（成就解锁）
                    if vm.shouldTriggerSparkleAnimation {
                        SparkleEffect()
                    }
                }
                .scaleEffect(vm.timerState == .working && vm.animationEnabled ? (isBreathing ? 1.02 : 0.98) : 1.0)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)
                .onAppear {
                    if vm.timerState == .working {
                        isBreathing = true
                    }
                }
                .onChange(of: vm.timerState) { _, newState in
                    isBreathing = (newState == .working)
                }
                .onChange(of: vm.shouldTriggerCollarAnimation) { _, shouldAdjust in
                    if shouldAdjust {
                        // 整理衣领动画：下压然后恢复
                        withAnimation(.easeIn(duration: 0.15)) {
                            collarAdjust = -8
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                collarAdjust = 0
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 260)
    }

    // 辅助函数：简化图标叠加代码
    func overlayImage(_ name: String, w: CGFloat, x: CGFloat, y: CGFloat, rotate: Double = 0) -> some View {
        Image(name)
            .resizable()
            .renderingMode(.template)
            .foregroundColor(.black)
            .scaledToFit()
            .frame(width: w)
            .rotationEffect(.degrees(rotate))
            .offset(x: x, y: y)
    }
}

// 闪光特效
struct SparkleEffect: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                Circle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .offset(x: isAnimating ? cos(Double(i) * .pi / 4) * 100 : 0,
                            y: isAnimating ? sin(Double(i) * .pi / 4) * 100 : 0)
                    .opacity(isAnimating ? 0 : 1)
            }

            // 中心闪光
            Circle()
                .stroke(Color.yellow, lineWidth: 3)
                .frame(width: isAnimating ? 120 : 40, height: isAnimating ? 120 : 40)
                .opacity(isAnimating ? 0 : 1)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) {
                isAnimating = true
            }
        }
    }
}
