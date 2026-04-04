import AVFoundation
import Speech
import SwiftUI

// MARK: - AudioEngineHolder

/// Holds AVAudioEngine + SFSpeechRecognizer in an @unchecked Sendable container
/// so heavy audio operations (inputNode, prepare, start) can run off the main
/// actor without Swift 6 Sendable conformance issues.
private final class AudioEngineHolder: @unchecked Sendable {
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false
    private let lock = NSLock()

    /// Configures the audio session and starts the engine entirely off the main thread.
    /// AVAudioSession.setActive, audioEngine.inputNode, prepare(), and start() can
    /// collectively block for several seconds while hardware initializes — running
    /// them off-main prevents a visible UI freeze.
    func setupAndStartEngine() async throws {
        let session = AVAudioSession.sharedInstance()
        var engine: AVAudioEngine?
        var request: SFSpeechAudioBufferRecognitionRequest?
        var didInstallTap = false

        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Small delay for the audio session to fully propagate —
            // inputNode.outputFormat can crash if queried immediately.
            try await Task.sleep(for: .milliseconds(50))

            let newEngine = AVAudioEngine()
            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.shouldReportPartialResults = true
            engine = newEngine
            request = newRequest

            let inputNode = newEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw NSError(
                    domain: "VoiceInput",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid audio input format"]
                )
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                newRequest.append(buffer)
            }
            didInstallTap = true

            newEngine.prepare()
            try newEngine.start()

            withLock {
                audioEngine = newEngine
                recognitionRequest = newRequest
                hasInstalledTap = true
            }
        } catch {
            if didInstallTap {
                engine?.inputNode.removeTap(onBus: 0)
            }
            if let engine, engine.isRunning {
                engine.stop()
            }
            request?.endAudio()
            withLock {
                audioEngine = nil
                recognitionRequest = nil
                recognitionTask = nil
                hasInstalledTap = false
            }
            try? session.setActive(false, options: [])
            throw error
        }
    }

    func cleanup() {
        withLock {
            recognitionTask?.cancel()
            recognitionTask = nil
            stopCaptureLocked()
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [])
            } catch {
                AppLogger.shared.log("Voice cleanup deactivation failed: \(error.localizedDescription)")
            }
            audioEngine = nil
            recognitionRequest = nil
        }
    }

    func stopCapture() {
        withLock {
            stopCaptureLocked()
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [])
            } catch {
                AppLogger.shared.log("Voice stop deactivation failed: \(error.localizedDescription)")
            }
            audioEngine = nil
            recognitionRequest = nil
        }
    }

    func currentRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest? {
        withLock { recognitionRequest }
    }

    func currentRecognitionTask() -> SFSpeechRecognitionTask? {
        withLock { recognitionTask }
    }

    func setRecognitionTask(_ task: SFSpeechRecognitionTask?) {
        withLock {
            recognitionTask = task
        }
    }

    func clearRecognitionTask() {
        withLock {
            recognitionTask = nil
        }
    }

    private func stopCaptureLocked() {
        recognitionRequest?.endAudio()
        guard let engine = audioEngine else { return }
        if engine.isRunning {
            engine.stop()
        }
        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

// MARK: - VoiceController

/// Owns the audio lifecycle so objects remain alive across SwiftUI re-renders.
/// Stored as @State in VoiceInputButton. Delegates heavy audio work to
/// AudioEngineHolder which runs off the main actor.
@MainActor
@Observable
private final class VoiceController {

    enum RecordingState: Equatable { case idle, recording, transcribing }

    var recordingState: RecordingState = .idle

    private let holder = AudioEngineHolder()
    /// Best partial transcript accumulated while recording — used as fallback on timeout.
    private var latestTranscript = ""
    /// Completion stored on the main actor so sendable GCD closures do not need to capture it.
    private var onFinished: ((String) -> Void)?
    private var didFinishTranscription = false

    // MARK: Public API

    /// Request permissions (if needed) then start the audio session.
    func startRecording(onFinished: @escaping (String) -> Void) {
        guard recordingState == .idle else { return }
        latestTranscript = ""
        didFinishTranscription = false
        self.onFinished = onFinished
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            // Min deployment is iOS 18 — AVAudioApplication API is always available.
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                guard granted else { return }
                Task { @MainActor [weak self] in
                    await self?.beginAudioSession()
                }
            }
        }
    }

    /// Stop the audio engine; transcription finalises asynchronously via the recognition task.
    /// Falls back to the best partial transcript after a 3-second timeout if no final result arrives.
    func stopRecording(onFinished: @escaping (String) -> Void) {
        guard recordingState == .recording else { return }
        self.onFinished = onFinished
        recordingState = .transcribing
        holder.stopCapture()

        // Capture current state for the timeout closure — avoids retain cycles and stale reads
        let capturedTranscript = latestTranscript
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.recordingState == .transcribing else { return }
            // Recognition task didn't return isFinal within 3s — surface best partial.
            // Full cleanup stops engine & releases mic to avoid stale audio state.
            self.holder.cleanup()
            self.latestTranscript = ""
            self.recordingState = .idle
            if !capturedTranscript.isEmpty { self.finishTranscription(capturedTranscript) }
        }
    }

    // MARK: Private

    private func beginAudioSession() async {
        guard holder.speechRecognizer?.isAvailable == true else { return }

        do {
            // All audio session + engine setup runs off-main via the holder.
            try await holder.setupAndStartEngine()
        } catch {
            holder.cleanup()
            return
        }

        guard let request = holder.currentRecognitionRequest(),
              let recognizer = holder.speechRecognizer else {
            holder.cleanup()
            return
        }

        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Recognition callback fires on an arbitrary queue — dispatch ALL
            // property access back to the main actor to avoid cross-actor
            // mutations that can deadlock in Swift 6 strict concurrency.
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal == true || error != nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !text.isEmpty {
                    self.latestTranscript = text
                }
                if isFinal {
                    let finalText = self.latestTranscript
                    self.latestTranscript = ""
                    // Full cleanup — stops engine, releases mic, deactivates audio session.
                    // Without this, a dangling engine keeps the mic active and causes
                    // audio session conflicts on the next recording attempt.
                    self.holder.cleanup()
                    self.recordingState = .idle
                    if !finalText.isEmpty { self.finishTranscription(finalText) }
                }
            }
        }
        holder.setRecognitionTask(recognitionTask)

        recordingState = .recording
    }

    private func finishTranscription(_ text: String) {
        guard !didFinishTranscription else { return }
        guard !text.isEmpty else { return }
        didFinishTranscription = true
        let completion = onFinished
        onFinished = nil
        completion?(text)
    }
}

// MARK: - VoiceInputButton

/// A self-contained mic/stop/spinner control for voice-to-text.
///
/// States:
/// - **Idle**: muted mic icon, no background
/// - **Recording**: red stop icon (tap to stop)
/// - **Transcribing**: spinner while waiting for final result
///
/// When transcription completes, `onTranscribed` is called with the recognized text.
struct VoiceInputButton: View {

    let onTranscribed: (String) -> Void

    @State private var controller = VoiceController()

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                switch controller.recordingState {
                case .idle:
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .transition(.scale.combined(with: .opacity))
                case .recording:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                        .transition(.scale.combined(with: .opacity))
                case .transcribing:
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(AppTheme.mutedText)
                        .transition(.opacity)
                }
            }
            .frame(width: 30, height: 30)
            .animation(.snappy(duration: 0.18), value: controller.recordingState)
        }
        .buttonStyle(.plain)
        .minTouchTarget()
        // Disable taps while transcribing — spinner is purely informational
        .disabled(controller.recordingState == .transcribing)
    }

    private func handleTap() {
        switch controller.recordingState {
        case .idle:
            controller.startRecording(onFinished: onTranscribed)
        case .recording:
            controller.stopRecording(onFinished: onTranscribed)
        case .transcribing:
            break
        }
    }
}
