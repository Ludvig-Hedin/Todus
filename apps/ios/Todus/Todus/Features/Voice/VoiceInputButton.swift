import AVFoundation
@preconcurrency import Speech
import SwiftUI

// MARK: - Diagnostic helpers

private func voiceLog(_ msg: String) {
    let thread = Thread.isMainThread ? "MAIN" : "bg"
    AppLogger.shared.log("[VoiceInput] \(msg) (\(thread))")
}

// MARK: - WeakRef

/// Sendable weak-reference box so we can safely capture a @MainActor object
/// in a Task.detached / @Sendable closure without triggering Swift 6's
/// "sending parameter risks data race" error.
/// Access `value` only from within `Task { @MainActor in }`.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - AudioEngineHolder

/// Holds AVAudioEngine + SFSpeechRecognizer in an @unchecked Sendable container.
/// All mutating calls are protected by `lock`.
private final class AudioEngineHolder: @unchecked Sendable {
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false
    private let lock = NSLock()

    /// Synchronous setup. MUST be called off the main thread — caller is
    /// always inside a Task.detached or a background queue.
    nonisolated func setupAndStartEngine() throws {
        voiceLog("setupAndStartEngine: start")
        assert(!Thread.isMainThread, "setupAndStartEngine must NOT run on main")

        let session = AVAudioSession.sharedInstance()
        var engine: AVAudioEngine?
        var request: SFSpeechAudioBufferRecognitionRequest?
        var didInstallTap = false

        do {
            voiceLog("setupAndStartEngine: setCategory + setActive")
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            voiceLog("setupAndStartEngine: session active ✓")

            // Brief pause: inputNode.outputFormat can return 0-channel immediately
            // after setActive on some devices.
            Thread.sleep(forTimeInterval: 0.05)

            let newEngine = AVAudioEngine()
            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.shouldReportPartialResults = true
            engine = newEngine
            request = newRequest

            let inputNode = newEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw NSError(
                    domain: "VoiceInput", code: -1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Invalid audio format (ch=\(format.channelCount) rate=\(format.sampleRate)). " +
                        "The microphone may be in use by another app."]
                )
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
                newRequest.append(buf)
            }
            didInstallTap = true

            voiceLog("setupAndStartEngine: prepare + start")
            newEngine.prepare()
            try newEngine.start()
            voiceLog("setupAndStartEngine: engine running ✓")

            withLock {
                audioEngine = newEngine
                recognitionRequest = newRequest
                hasInstalledTap = true
            }
        } catch {
            voiceLog("setupAndStartEngine: FAILED — \(error.localizedDescription)")
            if didInstallTap { engine?.inputNode.removeTap(onBus: 0) }
            if let engine, engine.isRunning { engine.stop() }
            request?.endAudio()
            withLock {
                audioEngine = nil; recognitionRequest = nil
                recognitionTask = nil; hasInstalledTap = false
            }
            try? session.setActive(false, options: [])
            throw error
        }
    }

    nonisolated func cleanup() {
        var engineToStop: AVAudioEngine?
        var hadTap = false
        withLock {
            recognitionTask?.cancel(); recognitionTask = nil
            recognitionRequest?.endAudio()
            engineToStop = audioEngine; hadTap = hasInstalledTap
            audioEngine = nil; recognitionRequest = nil; hasInstalledTap = false
        }
        Task.detached(priority: .utility) {
            if hadTap { engineToStop?.inputNode.removeTap(onBus: 0) }
            engineToStop?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [])
            voiceLog("cleanup: session deactivated")
        }
    }

    nonisolated func stopCapture() {
        var engineToStop: AVAudioEngine?
        var hadTap = false
        withLock {
            recognitionRequest?.endAudio()
            engineToStop = audioEngine; hadTap = hasInstalledTap
            audioEngine = nil; recognitionRequest = nil; hasInstalledTap = false
        }
        Task.detached(priority: .utility) {
            if hadTap { engineToStop?.inputNode.removeTap(onBus: 0) }
            engineToStop?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [])
            voiceLog("stopCapture: session deactivated")
        }
    }

    nonisolated func currentRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest? {
        withLock { recognitionRequest }
    }
    nonisolated func setRecognitionTask(_ task: SFSpeechRecognitionTask?) {
        withLock { recognitionTask = task }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}

// MARK: - VoiceController

@MainActor
@Observable
private final class VoiceController {

    enum RecordingState: Equatable { case idle, starting, recording, transcribing }

    var recordingState: RecordingState = .idle
    var permissionDenied = false
    var errorMessage: String?

    private let holder = AudioEngineHolder()
    private var latestTranscript = ""
    private var onFinished: ((String) -> Void)?
    private var didFinishTranscription = false
    private var startupWatchdog: Task<Void, Never>?

    // MARK: - Public API

    func startRecording(onFinished: @escaping (String) -> Void) {
        guard recordingState == .idle else {
            voiceLog("startRecording: ignored (state=\(recordingState))")
            return
        }
        voiceLog("startRecording: tap received")
        latestTranscript = ""
        didFinishTranscription = false
        permissionDenied = false
        errorMessage = nil
        self.onFinished = onFinished
        recordingState = .starting
        armWatchdog()

        // ─────────────────────────────────────────────────────────────────────
        // WHY Task.detached (not Task { @MainActor in }):
        //
        // `SFSpeechRecognizer.requestAuthorization` and
        // `AVAudioApplication.requestRecordPermission` are closure-based APIs
        // that internally can stall the *calling* thread while resolving system
        // state — especially on first call.  Running them from the main actor
        // (even inside `Task { @MainActor in }`) freezes the entire UI because
        // `Task { @MainActor in }` still executes on the main actor executor.
        // Only `Task.detached` truly leaves the main actor.
        // ─────────────────────────────────────────────────────────────────────
        let holder = self.holder
        let ref = WeakRef(self)   // Safe: only accessed inside Task { @MainActor in }

        Task.detached(priority: .userInitiated) {
            await VoiceController.setupOnBackground(ref: ref, holder: holder)
        }
    }

    /// Tears down any in-flight recording / watchdog. Safe to call from .onDisappear
    /// even when the controller is already idle.
    func tearDown() {
        cancelWatchdog()
        if recordingState != .idle {
            voiceLog("tearDown: cancelling state=\(recordingState)")
            holder.cleanup()
            latestTranscript = ""
            recordingState = .idle
            // Drop any pending callback — the host view is going away.
            onFinished = nil
            didFinishTranscription = false
        }
    }

    func stopRecording(onFinished: @escaping (String) -> Void) {
        guard recordingState == .recording else { return }
        voiceLog("stopRecording: user tapped stop")
        self.onFinished = onFinished
        recordingState = .transcribing
        holder.stopCapture()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.recordingState == .transcribing else { return }
            let finalTranscript = self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            voiceLog("stopRecording: 3 s timeout, partial='\(finalTranscript)'")
            self.holder.cleanup()
            self.latestTranscript = ""
            self.recordingState = .idle
            if !finalTranscript.isEmpty {
                self.finishTranscription(finalTranscript)
            } else {
                self.errorMessage = "No speech was detected. Please try again."
            }
        }
    }

    // MARK: - Background setup (static, nonisolated, takes only Sendable params)

    /// Pure background function. `static` so it cannot accidentally capture
    /// any MainActor-isolated state. All MainActor updates go through `ref`.
    private static nonisolated func setupOnBackground(
        ref: WeakRef<VoiceController>,
        holder: AudioEngineHolder
    ) async {
        voiceLog("setupOnBackground: start (must be bg)")

        // ── 1. Speech permission ──────────────────────────────────────────
        // Check status first (instant, non-blocking). Only call the dialog-
        // triggering API when status is truly undetermined.
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        voiceLog("setupOnBackground: speechStatus=\(speechStatus.rawValue)")

        if speechStatus == .notDetermined {
            voiceLog("setupOnBackground: requesting speech auth from bg thread")
            let resolved = await withCheckedContinuation {
                (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            voiceLog("setupOnBackground: speech auth resolved=\(resolved.rawValue)")
            guard resolved == .authorized else {
                await MainActor.run { ref.value?.fail(permission: true) }
                return
            }
        } else if speechStatus != .authorized {
            voiceLog("setupOnBackground: speech already denied")
            await MainActor.run { ref.value?.fail(permission: true) }
            return
        }

        // ── 2. Mic permission ─────────────────────────────────────────────
        let micStatus = AVAudioApplication.shared.recordPermission
        voiceLog("setupOnBackground: micStatus=\(micStatus.rawValue)")

        if micStatus == .undetermined {
            voiceLog("setupOnBackground: requesting mic permission from bg thread")
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            }
            voiceLog("setupOnBackground: mic granted=\(granted)")
            guard granted else {
                await MainActor.run { ref.value?.fail(permission: true) }
                return
            }
        } else if micStatus == .denied {
            voiceLog("setupOnBackground: mic already denied")
            await MainActor.run { ref.value?.fail(permission: true) }
            return
        }

        // ── 3. Recognizer availability ────────────────────────────────────
        guard let recognizer = holder.speechRecognizer else {
            voiceLog("setupOnBackground: SFSpeechRecognizer nil (unsupported locale)")
            await MainActor.run {
                ref.value?.fail(msg: "Speech recognition isn't supported for your device's language.")
            }
            return
        }
        guard recognizer.isAvailable else {
            voiceLog("setupOnBackground: recognizer unavailable (offline?)")
            await MainActor.run {
                ref.value?.fail(msg: "Speech recognition is unavailable. Check your connection and try again.")
            }
            return
        }

        // ── 4. Audio engine (synchronous, blocking — OK on bg) ───────────
        do {
            try holder.setupAndStartEngine()
        } catch {
            voiceLog("setupOnBackground: engine FAILED — \(error.localizedDescription)")
            await MainActor.run {
                ref.value?.fail(msg: "Couldn't start the microphone: \(error.localizedDescription)")
            }
            return
        }

        guard let request = holder.currentRecognitionRequest() else {
            voiceLog("setupOnBackground: request nil after engine start")
            await MainActor.run {
                ref.value?.fail(msg: "Couldn't initialize speech recognition. Please try again.")
            }
            return
        }

        // ── 5. Recognition task ───────────────────────────────────────────
        // The callback is @Sendable and must not capture any MainActor state
        // directly.  We pass `ref` (WeakRef, @unchecked Sendable) and access
        // `ref.value` only inside Task { @MainActor in }, which satisfies Swift 6.
        voiceLog("setupOnBackground: starting recognitionTask")
        let task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal == true || error != nil
            if let error { voiceLog("recognitionTask: error — \(error.localizedDescription)") }
            Task { @MainActor in
                guard let ctrl = ref.value else { return }
                if !text.isEmpty { ctrl.latestTranscript = text }
                if isFinal {
                    voiceLog("recognitionTask: isFinal, result='\(ctrl.latestTranscript)'")
                    let finalText = ctrl.latestTranscript
                    ctrl.latestTranscript = ""
                    ctrl.holder.cleanup()
                    ctrl.recordingState = .idle
                    if !finalText.isEmpty { ctrl.finishTranscription(finalText) }
                }
            }
        }
        holder.setRecognitionTask(task)

        voiceLog("setupOnBackground: transitioning to .recording on main")
        await MainActor.run {
            guard let ctrl = ref.value else { return }
            ctrl.recordingState = .recording
            ctrl.cancelWatchdog()
            voiceLog("setupOnBackground: state → .recording ✅")
        }
    }

    // MARK: - Private helpers (MainActor)

    fileprivate func fail(permission: Bool = false, msg: String? = nil) {
        if permission {
            voiceLog("fail: permission denied")
            permissionDenied = true
        } else if let msg {
            voiceLog("fail: \(msg)")
            errorMessage = msg
        }
        holder.cleanup()
        recordingState = .idle
        latestTranscript = ""
        cancelWatchdog()
    }

    private func finishTranscription(_ text: String) {
        guard !didFinishTranscription, !text.isEmpty else { return }
        didFinishTranscription = true
        let cb = onFinished; onFinished = nil; cb?(text)
    }

    private func armWatchdog() {
        cancelWatchdog()
        startupWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            if self.recordingState == .starting {
                voiceLog("watchdog: still .starting after 10 s — forcing reset")
                self.fail(msg:
                    "Voice input didn't start within 10 seconds. " +
                    "Check Microphone and Speech Recognition permissions in Settings."
                )
            }
        }
    }

    private func cancelWatchdog() {
        startupWatchdog?.cancel()
        startupWatchdog = nil
    }
}

// MARK: - VoiceInputButton

/// Self-contained mic/stop/spinner button for voice-to-text.
///
/// - **Idle**: mic icon (tap to start)
/// - **Starting**: spinner (permissions + audio session initializing — off-main)
/// - **Recording**: red stop icon (tap to stop)
/// - **Transcribing**: spinner (waiting for final transcript)
struct VoiceInputButton: View {

    let onTranscribed: (String) -> Void

    @State private var controller = VoiceController()
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var ctrl = controller
        Button(action: handleTap) {
            ZStack {
                switch controller.recordingState {
                case .idle:
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .transition(.scale.combined(with: .opacity))
                case .starting, .transcribing:
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(AppTheme.mutedText)
                        .transition(.opacity)
                case .recording:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 30, height: 30)
            .animation(.snappy(duration: 0.18), value: controller.recordingState)
        }
        .buttonStyle(.plain)
        .minTouchTarget()
        .disabled(controller.recordingState == .starting || controller.recordingState == .transcribing)
        .alert("Microphone Access Required", isPresented: $ctrl.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable Microphone and Speech Recognition access in Settings → Privacy & Security to use voice input.")
        }
        .alert(
            "Voice Input Error",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            ),
            presenting: controller.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        // Make sure the watchdog Task and audio engine are released if the host view
        // disappears mid-recording (e.g. user dismisses the chat sheet). Otherwise the
        // detached watchdog keeps the controller alive and can fire after dismissal.
        .onDisappear {
            controller.tearDown()
        }
    }

    private func handleTap() {
        switch controller.recordingState {
        case .idle:    controller.startRecording(onFinished: onTranscribed)
        case .recording: controller.stopRecording(onFinished: onTranscribed)
        case .starting, .transcribing: break
        }
    }
}
