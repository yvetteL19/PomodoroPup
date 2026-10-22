import SwiftUI
import AppKit

struct DogView: View {
    @EnvironmentObject var vm: DogViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        vm.animationEnabled && !reduceMotion && vm.isTimerRunning
    }

    var body: some View {
        ZStack {
            if vm.timerState == .onBreak {
                if shouldAnimate {
                    // 休息状态且动画开启：播放 GIF
                    GifImageView(gifName: "dog_rest", size: CGSize(width: 150, height: 150))
                        .frame(width: 150, height: 150)
                } else {
                    // 休息状态但动画关闭：显示休息静态图
                    Image("dog_rest_static")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                }
            } else if vm.timerState == .working && shouldAnimate {
                BreathingDogImage()
            } else {
                // 工作/停止状态：静态图片
                Image("dog_work")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
            }
        }
        .frame(width: 150, height: 160)
    }
}

// Removing this view when paused also removes its repeating animation.
private struct BreathingDogImage: View {
    @State private var isBreathing = false

    var body: some View {
        Image("dog_work")
            .resizable()
            .scaledToFit()
            .frame(width: 150, height: 150)
            .scaleEffect(isBreathing ? 1.02 : 0.98)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

// GIF 播放视图
struct GifImageView: NSViewRepresentable {
    let gifName: String
    var size: CGSize = CGSize(width: 100, height: 100)

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        containerView.wantsLayer = true

        let imageView = NSImageView(frame: containerView.bounds)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.animates = true

        if let asset = NSDataAsset(name: gifName) {
            let image = NSImage(data: asset.data)
            image?.size = size  // 强制设置图片尺寸
            imageView.image = image
        }

        containerView.addSubview(imageView)
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.frame.size = size
        if let imageView = nsView.subviews.first as? NSImageView {
            imageView.frame = nsView.bounds
        }
    }
}
