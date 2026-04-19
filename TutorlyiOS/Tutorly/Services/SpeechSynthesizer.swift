import Foundation
import AVFoundation

@Observable
final class SpeechSynthesizer: NSObject {
    var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        guard !text.isEmpty else { onFinish?(); return }
        self.onFinish = onFinish

        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
        }

        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }

        let utter = AVSpeechUtterance(string: text)
        utter.voice = pickVoice()
        utter.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utter.pitchMultiplier = 1.0
        utter.volume = 1.0
        synth.speak(utter)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    private func pickVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        // Prefer premium/enhanced English voices
        let preferences: [(AVSpeechSynthesisVoice) -> Bool] = [
            { $0.language.hasPrefix("en") && $0.quality == .premium },
            { $0.language.hasPrefix("en") && $0.quality == .enhanced },
            { $0.language == "en-GB" },
            { $0.language == "en-US" },
            { $0.language.hasPrefix("en") }
        ]
        for pred in preferences {
            if let v = voices.first(where: pred) { return v }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = true }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let cb = onFinish
        onFinish = nil
        Task { @MainActor in
            isSpeaking = false
            cb?()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish = nil
        Task { @MainActor in isSpeaking = false }
    }
}
