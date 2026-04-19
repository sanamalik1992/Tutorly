import Foundation
import AVFoundation

enum VoiceGender: String, CaseIterable {
    case female, male
    var label: String { self == .female ? "Girl" : "Boy" }
}

@Observable
final class SpeechSynthesizer: NSObject {
    var isSpeaking = false
    var gender: VoiceGender {
        didSet { UserDefaults.standard.set(gender.rawValue, forKey: "tutorly.voiceGender") }
    }

    private let synth = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?

    override init() {
        let saved = UserDefaults.standard.string(forKey: "tutorly.voiceGender") ?? ""
        gender = VoiceGender(rawValue: saved) ?? .female
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        guard !text.isEmpty else { onFinish?(); return }
        self.onFinish = onFinish

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
        }

        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }

        let utter = AVSpeechUtterance(string: text)
        utter.voice = pickVoice()
        utter.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
        utter.pitchMultiplier = gender == .male ? 0.82 : 1.12
        utter.volume = 1.0
        synth.speak(utter)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    private func pickVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let femaleNames = ["Samantha", "Ava", "Allison", "Zoe", "Nicky", "Karen", "Moira", "Tessa", "Serena", "Susan"]
        let maleNames   = ["Aaron", "Tom", "Daniel", "Gordon", "Rishi", "Oliver", "Arthur", "Fred"]
        let targets = gender == .female ? femaleNames : maleNames

        for quality: AVSpeechSynthesisVoiceQuality in [.premium, .enhanced, .default] {
            if let v = voices.first(where: { v in
                (quality == .default || v.quality == quality) &&
                targets.contains(where: { v.name.contains($0) })
            }) { return v }
        }
        return AVSpeechSynthesisVoice(language: gender == .female ? "en-US" : "en-GB")
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = true }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let cb = onFinish; onFinish = nil
        Task { @MainActor in isSpeaking = false; cb?() }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish = nil
        Task { @MainActor in isSpeaking = false }
    }
}
