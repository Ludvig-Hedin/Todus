import AVFoundation
import Speech
import SwiftUI

// MARK: - VoiceController

/// Owns AVAudioEngine + SFSpeechRecognizer lifecycle so the objects remain alive
/// across SwiftUI re-renders. Stored as @State in VoiceInputButton.
@MainActor
@Observable
private final class VoiceController {

    enum RecordingState: Equatable { case idle, recording, transcribing }

    var recordingState: RecordingState = .idle

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Best partial transcript accumulated while recording — used as fallback on timeout.
    private var latestTranscript = ""
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()

    // MARK: Public API

    /// Request permissions (if needed) then start the audio session.
    func startRecording(onFinished: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.beginAudioSession(onFinished: onFinished)
                }
            }
        }
    }

    /// Stop the audio engine; transcription finalises asynchronously via the recognition task.
    /// Falls back to the best partial transcript after a 3-second timeout if no final result arrives.
    func stopRecording(onFinished: @escaping (String) -> Void) {
        recordingState = .transcribing
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        audioEngine = nil
        recognitionRequest = nil

        // Capture current state for the timeout closure — avoids retain cycles and stale reads
        let capturedTranscript = latestTranscript
        let capturedTask = recognitionTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.recordingState == .transcribing else { return }
            // Recognition task didn't return isFinal within 3s — surface best partial
            capturedTask?.cancel()
            self.recognitionTask = nil
            self.latestTranscript = ""
            self.recordingState = .idle
            if !capturedTranscript.isEmpty { onFinished(capturedTranscript) }
        }
    }

    // MARK: Private

    private func beginAudioSession(onFinished: @escaping (String) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        // Report partials so latestTranscript stays fresh even before isFinal
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // .duckOthers lowers background audio while recording
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            engine.prepare()
            try engine.start()
        } catch {
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                // Keep accumulating; on stop we'll use whatever we have
                self.latestTranscript = result.bestTranscription.formattedString
            }
            if result?.isFinal == true || error != nil {
                DispatchQueue.main.async {
                    let text = self.latestTranscript
                    self.latestTranscript = ""
                    self.recognitionTask = nil
                    self.recordingState = .idle
                    if !text.isEmpty { onFinished(text) }
                }
            }
        }

        audioEngine = engine
        recognitionRequest = request
        recordingState = .recording
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
