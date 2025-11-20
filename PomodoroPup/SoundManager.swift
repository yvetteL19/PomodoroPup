import AVFoundation

class SoundManager {
    static let shared = SoundManager()
    private var audioPlayer: AVAudioPlayer?
    
    enum SoundEffect: String {
        case bark, sigh, achievement
    }
    
    func play(_ effect: SoundEffect) {
        // 支持 mp3 或 wav
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "mp3") ??
                        Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Play error: \(error)")
        }
    }
}
