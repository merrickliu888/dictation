import AVFoundation
import Combine
import Foundation
import Speech

/// Streaming speech-to-text via Apple's Speech framework, on-device when the
/// language supports it. Publishes the full hypothesis (replace semantics —
/// Apple re-emits the whole string on each partial) plus a normalized audio
/// level for the waveform.
@MainActor
final class Transcriber: NSObject, ObservableObject {

    @Published private(set) var partialText: String = ""
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Identifies the current session so results from a task that was
    /// already torn down (sessions cycle fast on a double tap) are dropped.
    private var generation = 0
    private var pendingFinish: ((String) -> Void)?
    private var finishTimeout: DispatchWorkItem?

    // Adaptive level normalization: track a slow-moving floor/ceiling in dB
    // so the waveform reads well at any mic gain.
    private var floorDB: Float = -55
    private var ceilingDB: Float = -30

    func start() {
        // A session still waiting on its final pass gets settled with what
        // it has; the microphone is needed now.
        resolvePendingFinish()
        guard !isActive else { return }
        lastError = nil
        partialText = ""
        generation += 1
        let generation = self.generation

        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        guard let recognizer else {
            lastError = "Speech recognition is unavailable for this language."
            NSLog("Transcriber: no recognizer for locale \(Locale.current.identifier)")
            return
        }
        guard recognizer.isAvailable else {
            lastError = recognizer.supportsOnDeviceRecognition
                ? "Speech recognition is temporarily unavailable."
                : "Speech recognition is unavailable — enable Dictation in System Settings → Keyboard, or check your network."
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        // On-device recognition works offline and doesn't depend on
        // Siri/Dictation server availability.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            lastError = "No usable microphone input."
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.rmsLevel(buffer: buffer)
            Task { @MainActor [weak self] in self?.updateLevel(rms: level) }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                    if result.isFinal { self.resolvePendingFinish() }
                }
                if let error {
                    let ns = error as NSError
                    NSLog("Transcriber: recognition error domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
                    // After endAudio an error ("no speech detected" and the
                    // like) is the end of the session; deliver the partial.
                    if self.pendingFinish != nil {
                        self.resolvePendingFinish()
                        return
                    }
                    guard self.isActive else { return }
                    if ns.domain != "kAFAssistantErrorDomain" || ns.code != 216 { // 216 = canceled
                        self.lastError = ns.localizedDescription
                    }
                    self.teardownRecognition()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isActive = true
        } catch {
            lastError = "Could not start audio capture: \(error.localizedDescription)"
            input.removeTap(onBus: 0)
            teardownRecognition()
        }
    }

    /// Stop listening and hand back the text once Apple's final pass is in —
    /// it revises the last words and the punctuation — or after `timeout`
    /// if it never comes.
    func finish(timeout: TimeInterval = 1.5, completion: @escaping (String) -> Void) {
        resolvePendingFinish()
        guard task != nil else {
            let text = partialText
            teardownRecognition()
            completion(text)
            return
        }
        pendingFinish = completion
        stopEngineOnly()
        request?.endAudio()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.resolvePendingFinish() }
        }
        finishTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    /// Stop listening and drop whatever was heard.
    func cancel() {
        pendingFinish = nil
        finishTimeout?.cancel()
        finishTimeout = nil
        teardownRecognition()
        partialText = ""
    }

    private func resolvePendingFinish() {
        finishTimeout?.cancel()
        finishTimeout = nil
        guard let completion = pendingFinish else { return }
        pendingFinish = nil
        let text = partialText
        teardownRecognition()
        completion(text)
    }

    private func teardownRecognition() {
        stopEngineOnly()
        task?.cancel()
        task = nil
        request = nil
        // Orphan any callback still in flight from this task.
        generation += 1
    }

    private func stopEngineOnly() {
        guard isActive || audioEngine.isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isActive = false
        audioLevel = 0
    }

    // MARK: - Metering

    private nonisolated static func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += channelData[i] * channelData[i] }
        return sqrt(sum / Float(frames))
    }

    private func updateLevel(rms: Float) {
        guard isActive else { return }
        let db = 20 * log10(max(rms, 1e-6))
        // Slow-adapting floor and ceiling.
        floorDB = db < floorDB ? floorDB * 0.88 + db * 0.12 : floorDB * 0.98 + db * 0.02
        ceilingDB = db > ceilingDB ? ceilingDB * 0.45 + db * 0.55 : ceilingDB * 0.96 + db * 0.04
        let span = max(ceilingDB - floorDB, 18)
        let normalized = max(0, min(1, (db - floorDB) / span))
        // Attack fast, release slow, and keep a small floor while speaking so
        // the bars never fully collapse mid-utterance.
        let smoothed = normalized > audioLevel
            ? audioLevel * 0.55 + normalized * 0.45
            : audioLevel * 0.88 + normalized * 0.12
        audioLevel = smoothed < 0.05 ? 0 : max(smoothed, 0.12)
    }
}
