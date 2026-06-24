import AVFoundation
import AppKit

class SoundManager {
    static let shared = SoundManager()
    private var audioPlayer: AVAudioPlayer?

    enum SoundEffect: String {
        case ding, sigh, achievement  // bark 改为 ding
    }

    func play(_ effect: SoundEffect) {
        // ding 使用系统音效
        if effect == .ding {
            // 使用 macOS 系统提示音 "Glass"（轻柔的叮咚声）
            if let sound = NSSound(named: "Glass") {
                sound.play()
            } else {
                NSSound.beep()  // 备用
            }
            return
        }

        // 其他音效使用自定义文件
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "MP3") ??
                        Bundle.main.url(forResource: effect.rawValue, withExtension: "mp3") ??
                        Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else {
            print("❌ Sound file not found: \(effect.rawValue)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("❌ Play error: \(error)")
        }
    }
}
