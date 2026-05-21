@preconcurrency import AVFoundation
import Foundation

// MARK: - VoiceAudioCapture

/// Owns an AVAudioEngine that captures microphone input, downsamples it to
/// 16kHz PCM16 mono, and delivers chunks to a callback every ~100ms. Extracted
/// from `VoiceSessionCoordinator` so the coordinator stays under 500 lines and
/// the audio plumbing can be unit-tested or reused by other voice surfaces.
///
/// Mirrors the proven capture pipeline in `VoiceChatViewModel` (same buffer
/// size, target format, timer cadence) so behaviour is consistent across both
/// the in-app modal and the AppIntent-driven coordinator session.
final class VoiceAudioCapture: @unchecked Sendable {

    /// Called on a background queue when a fresh PCM16 chunk is ready.
    /// Callback owners must be thread-safe; the closure runs off-main.
    var onChunk: (@Sendable (Data) -> Void)?

    private var engine: AVAudioEngine?
    private var sendTimer: DispatchSourceTimer?
    private var pcmBuffer = Data()
    private let pcmBufferLock = NSLock()

    enum SetupResult {
        case success
        case failed(String)
    }

    /// Start the engine. Runs the heavy AVAudioSession.setActive + engine.start
    /// off-main so the caller's UI doesn't stall (the watchdog has terminated
    /// us during cold starts before — this is intentional).
    func start() async -> SetupResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    cont.resume(returning: .failed("Voice capture was cancelled"))
                    return
                }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .playAndRecord,
                        mode: .voiceChat,
                        options: [.defaultToSpeaker, .allowBluetoothHFP]
                    )
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                } catch {
                    cont.resume(returning: .failed(
                        "Audio session setup failed: \(error.localizedDescription)"
                    ))
                    return
                }

                let engine = AVAudioEngine()
                let input = engine.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0 else {
                    cont.resume(returning: .failed("No microphone input is available"))
                    return
                }
                guard let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: 16000,
                    channels: 1,
                    interleaved: true
                ) else {
                    cont.resume(returning: .failed("Failed to create target audio format"))
                    return
                }
                guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                    cont.resume(returning: .failed("Cannot create audio format converter"))
                    return
                }

                input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self else { return }
                    let frameCount = AVAudioFrameCount(
                        Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate
                    )
                    guard frameCount > 0,
                          let converted = AVAudioPCMBuffer(
                            pcmFormat: targetFormat,
                            frameCapacity: frameCount
                          )
                    else { return }
                    var err: NSError?
                    let supplied = _BoolBox()
                    converter.convert(to: converted, error: &err) { _, outStatus in
                        if supplied.value {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        supplied.value = true
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    if err == nil, converted.frameLength > 0,
                       let ch = converted.int16ChannelData?[0] {
                        let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
                        let data = Data(bytes: ch, count: byteCount)
                        self.pcmBufferLock.lock()
                        self.pcmBuffer.append(data)
                        self.pcmBufferLock.unlock()
                    }
                }

                do {
                    engine.prepare()
                    try engine.start()
                } catch {
                    input.removeTap(onBus: 0)
                    cont.resume(returning: .failed(
                        "Audio engine start failed: \(error.localizedDescription)"
                    ))
                    return
                }
                self.engine = engine
                self.startSendTimer()
                cont.resume(returning: .success)
            }
        }
    }

    func stop() {
        sendTimer?.cancel()
        sendTimer = nil
        let engineToStop = engine
        engine = nil
        pcmBufferLock.lock()
        pcmBuffer = Data()
        pcmBufferLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            engineToStop?.stop()
            engineToStop?.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    private func startSendTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.pcmBufferLock.lock()
            let chunk = self.pcmBuffer
            self.pcmBuffer = Data()
            self.pcmBufferLock.unlock()
            guard !chunk.isEmpty else { return }
            self.onChunk?(chunk)
        }
        timer.resume()
        sendTimer = timer
    }
}

/// Internal mutable Bool box used by @Sendable converter closures.
private final class _BoolBox: @unchecked Sendable {
    var value: Bool = false
}
