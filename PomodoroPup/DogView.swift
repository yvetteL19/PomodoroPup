import SwiftUI
import AppKit

struct DogView: View {
    @EnvironmentObject var vm: DogViewModel
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            if vm.timerState == .onBreak {
                if vm.animationEnabled {
                    // 休息状态且动画开启：播放 GIF
                    GifImageView(gifName: "dog_rest", size: CGSize(width: 150, height: 150))
                } else {
                    // 休息状态但动画关闭：显示休息静态图
                    Image("dog_rest_static")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                }
            } else {
                // 工作/停止状态：静态图片
                Image("dog_work")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    // 工作时呼吸动画
                    .scaleEffect(vm.timerState == .working && vm.animationEnabled && isBreathing ? 1.02 : 0.98)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)
            }
        }
        .frame(height: 260)
        .onAppear {
            if vm.timerState == .working {
                isBreathing = true
            }
        }
        .onChange(of: vm.timerState) { _, newState in
            isBreathing = (newState == .working)
        }
    }

}

// GIF 播放视图
struct GifImageView: NSViewRepresentable {
    let gifName: String
    var size: CGSize = CGSize(width: 100, height: 100)

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.autoresizingMask = [.width, .height]

        if let asset = NSDataAsset(name: gifName) {
            imageView.image = NSImage(data: asset.data)
        }

        containerView.addSubview(imageView)
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 更新尺寸
        nsView.frame.size = size
        if let imageView = nsView.subviews.first as? NSImageView {
            imageView.frame.size = size
        }
    }
}
