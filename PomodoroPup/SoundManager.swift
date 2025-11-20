import AVFoundation

class SoundManager {
    static let shared = SoundManager()
    private var audioPlayer: AVAudioPlayer?
    
    enum SoundEffect: String {
        case bark, sigh, achievement
    }
    
    func play(_ effect: SoundEffect) {
        // 支持 MP3/mp3 或 wav
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
            print("🔊 Playing sound: \(effect.rawValue)")
        } catch {
            print("❌ Play error: \(error)")
        }
    }
}
