import SwiftUI

struct DogView: View {
    @EnvironmentObject var vm: DogViewModel
    @State private var isBreathing = false
    @State private var isDancing = false
    @State private var jumpScale: CGFloat = 1.0
    @State private var collarAdjust: CGFloat = 0

    var body: some View {
        ZStack {
            // 所有状态都使用同一个小狗图片
            ZStack {
                Image("dog_focus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)

                // 闪光动画（成就解锁）
                if vm.shouldTriggerSparkleAnimation {
                    SparkleEffect()
                }
            }
            // 呼吸动画：工作和休息时都有
            .scaleEffect((vm.timerState == .working || vm.timerState == .onBreak) && vm.animationEnabled ? (isBreathing ? 1.02 : 0.98) : 1.0)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)
            .onAppear {
                if vm.timerState == .working || vm.timerState == .onBreak {
                    isBreathing = true
                }
            }
            .onChange(of: vm.timerState) { _, newState in
                isBreathing = (newState == .working || newState == .onBreak)
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
