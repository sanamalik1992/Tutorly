import Foundation
import Speech
import AVFoundation

@Observable
final class SpeechRecognizer {
    var isListening = false
    var interim: String = ""
    var isAuthorized = false
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinal: ((String) -> Void)?

    init() {
        Task { await requestAuthorization() }
    }

    func requestAuthorization() async {
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let micStatus = await AVAudioApplication.requestRecordPermission()
        await MainActor.run {
            isAuthorized = (speechStatus == .authorized) && micStatus
        }
    }

    func start(onFinal: @escaping (String) -> Void) {
        guard !isListening else { return }
        self.onFinal = onFinal
        interim = ""
        errorMessage = nil

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition unavailable."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = false // cloud is fine; better accuracy
            request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in self.interim = text }
                    if result.isFinal {
                        self.finish(with: text)
                    }
                }
                if let error {
                    // Silence benign "no speech detected" errors
                    let ns = error as NSError
                    if ns.domain != "kAFAssistantErrorDomain" {
                        Task { @MainActor in self.errorMessage = error.localizedDescription }
                    }
                    self.stop()
                }
            }
        } catch {
            errorMessage = "Couldn't start mic: \(error.localizedDescription)"
            stop()
        }
    }

    /// Stop recording; if we have interim text, treat it as the final answer.
    func stop() {
        let pending = interim
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        Task { @MainActor in
            if isListening {
                isListening = false
                // If user tapped stop but we had a partial transcript, use it
                if !pending.isEmpty {
                    finish(with: pending)
                }
            }
        }
    }

    private func finish(with text: String) {
        let cb = onFinal
        Task { @MainActor in
            isListening = false
            interim = ""
            cb?(text.trimmingCharacters(in: .whitespaces))
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        onFinal = nil
    }
}
