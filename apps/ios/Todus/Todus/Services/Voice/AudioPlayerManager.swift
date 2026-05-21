import AVFoundation
import Foundation

// MARK: - AudioPlayerManager

/// Plays PCM16 audio chunks received from a live voice provider.
///
/// Uses AVAudioEngine + AVAudioPlayerNode to play raw PCM data with minimal latency.
/// Thread-safe: `enqueue` can be called from any context; audio scheduling
/// happens on a private serial queue to avoid blocking the main thread.
final class AudioPlayerManager: @unchecked Sendable {

    /// True while audio is actively playing or buffered for playback.
    /// Thread-safe: reads are synchronized on audioQueue to match writes.
    var isPlaying: Bool {
        audioQueue.sync { _isPlaying }
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// Gemini Live returns PCM16 at 24kHz mono.
    private let outputFormat: AVAudioFormat
    /// Serial queue for thread-safe buffer scheduling and state access.
    private let audioQueue = DispatchQueue(label: "com.todus.audioPlayer", qos: .userInteractive)
    private var _isPlaying = false
    /// Tracks how many buffers are scheduled so we know when playback naturally finishes.
    private var scheduledBufferCount = 0
    private var isEngineRunning = false

    init?(sampleRate: Double = 24000, channels: AVAudioChannelCount = 1) {
        // PCM signed 16-bit integer, mono, at the provider's output sample rate.
        // Guard against invalid parameters — AVAudioFormat returns nil for unsupported configs.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else {
            print("[AudioPlayerManager] Invalid audio format: sampleRate=\(sampleRate), channels=\(channels)")
            return nil
        }
        self.outputFormat = format
    }

    /// Enqueue raw PCM16 data for playback. Starts the engine on first call.
    func enqueue(_ pcmData: Data) {
        guard !pcmData.isEmpty else { return }
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.ensureEngineRunning()
            self.schedulePCMBuffer(pcmData)
        }
    }

    /// Stop playback and clear any scheduled buffers.
    func stop() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.playerNode.stop()
            self._isPlaying = false
            self.scheduledBufferCount = 0
            self.stopEngine()
        }
    }

    // MARK: - Private

    private func ensureEngineRunning() {
        guard !isEngineRunning else { return }
        do {
            // Attach only if the node is not already wired to this engine — calling
            // `attach` twice on the same node raises an exception inside AVAudioEngine
            // (re-entry after a stop/start cycle that didn't detach is the common path).
            if playerNode.engine == nil {
                engine.attach(playerNode)
            }
            engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
            engine.prepare()
            try engine.start()
            playerNode.play()
            isEngineRunning = true
            _isPlaying = true
        } catch {
            print("[AudioPlayerManager] Failed to start engine: \(error)")
        }
    }

    private func stopEngine() {
        guard isEngineRunning else { return }
        playerNode.stop()
        engine.stop()
        // Detach to allow re-attaching cleanly on next session
        engine.detach(playerNode)
        isEngineRunning = false
        _isPlaying = false
    }

    private func schedulePCMBuffer(_ data: Data) {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount)
        else { return }

        buffer.frameLength = frameCount

        // Copy raw PCM16 bytes into the buffer's int16 channel data
        data.withUnsafeBytes { rawPtr in
            guard let srcPtr = rawPtr.baseAddress else { return }
            if let dst = buffer.int16ChannelData?[0] {
                memcpy(dst, srcPtr, data.count)
            }
        }

        scheduledBufferCount += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            // Callback fires on an internal AVAudioEngine thread — guard before dispatching
            // so `self` is a strong let constant when captured by the audioQueue closure.
            guard let self else { return }
            self.audioQueue.async {
                self.scheduledBufferCount -= 1
                if self.scheduledBufferCount <= 0 {
                    self.scheduledBufferCount = 0
                    self._isPlaying = false
                }
            }
        }
        _isPlaying = true
    }
}
