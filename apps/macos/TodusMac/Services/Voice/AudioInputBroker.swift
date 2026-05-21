@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioInputBroker

/// Single-tap fan-out for the microphone input. AVAudioEngine crashes if a
/// second tap is installed on the same input node, so when the wake-word
/// detector AND the live voice session both want frames, we install ONE tap
/// here and dispatch the converted PCM16 16kHz buffer to every registered
/// consumer.
///
/// Phase-1 consumers: Gemini Live audio sender (always), Porcupine wake
/// detector (only when always-listening is enabled). Adding a third (e.g.
/// a clap detector) is a no-op — register it and it gets the same frames.
@MainActor
final class AudioInputBroker {

    // MARK: - State

    private var engine: AVAudioEngine?
    /// Shared with the CoreAudio tap thread — this is where consumer lookups
    /// happen on every audio buffer. Lock-protected so add/remove from the
    /// main actor doesn't race the render thread.
    private let consumerStore = ConsumerStore()

    private var startCount: Int = 0

    // MARK: - Public API

    /// Add a consumer. The first add starts the engine; subsequent adds reuse
    /// the existing tap. Returns a token to pass to `removeConsumer`.
    @discardableResult
    func addConsumer(_ onAudio: @escaping @Sendable (Data) -> Void) async throws -> UUID {
        let id = consumerStore.add(onAudio)
        startCount += 1
        if startCount == 1 {
            do {
                try await startEngine()
            } catch {
                // Roll back the consumer add so the count stays consistent
                // with the engine state — otherwise a second addConsumer
                // wouldn't try to start again.
                consumerStore.remove(id)
                startCount = max(0, startCount - 1)
                throw error
            }
        }
        return id
    }

    /// Remove a previously-added consumer. The last removal stops the engine.
    func removeConsumer(_ id: UUID) {
        guard consumerStore.remove(id) else { return }
        startCount = max(0, startCount - 1)
        if startCount == 0 {
            stopEngine()
        }
    }

    /// True while the underlying engine is running.
    var isRunning: Bool { engine?.isRunning ?? false }

    // MARK: - Engine lifecycle

    private func startEngine() async throws {
        // AVAudioEngine.start() can block for hundreds of ms — run off-main
        // so the caller (e.g. session connect) doesn't freeze the panel.
        let store = consumerStore
        let engine: AVAudioEngine = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let engine = try Self.makeAndStartEngine(store: store)
                    cont.resume(returning: engine)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        self.engine = engine
    }

    nonisolated private static func makeAndStartEngine(store: ConsumerStore) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioBrokerError.noInputDevice
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioBrokerError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioBrokerError.converterCreationFailed
        }

        // The tap closure runs on a CoreAudio render thread. It must NOT use
        // Swift concurrency or main-actor hops. Snapshot the consumer list
        // under a tiny lock and dispatch.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(
                      pcmFormat: targetFormat,
                      frameCapacity: frameCount
                  )
            else { return }

            var error: NSError?
            let suppliedInput = _MutableBoolBox()
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if suppliedInput.value {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput.value = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard error == nil, convertedBuffer.frameLength > 0,
                  let channelData = convertedBuffer.int16ChannelData?[0]
            else { return }
            let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: channelData, count: byteCount)

            for handler in store.snapshot() {
                handler(data)
            }
        }

        engine.prepare()
        try engine.start()
        return engine
    }

    private func stopEngine() {
        let engineToStop = engine
        engine = nil
        DispatchQueue.global(qos: .userInitiated).async {
            engineToStop?.stop()
            engineToStop?.inputNode.removeTap(onBus: 0)
        }
    }
}

// MARK: - ConsumerStore

/// Lock-protected fan-out target shared between the main actor (mutators)
/// and the CoreAudio render thread (reader). Generic over the handler type
/// so callers don't need to expose the broker's internals.
final class ConsumerStore: @unchecked Sendable {
    private struct Entry {
        let id: UUID
        let handler: @Sendable (Data) -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func add(_ handler: @escaping @Sendable (Data) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        entries.append(Entry(id: id, handler: handler))
        lock.unlock()
        return id
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        lock.lock()
        let before = entries.count
        entries.removeAll { $0.id == id }
        let removed = entries.count != before
        lock.unlock()
        return removed
    }

    /// Snapshot the current handlers. Cheap (small array of closures) and
    /// safe to call from the audio render thread.
    func snapshot() -> [@Sendable (Data) -> Void] {
        lock.lock()
        let out = entries.map(\.handler)
        lock.unlock()
        return out
    }
}

// MARK: - Errors

enum AudioBrokerError: Error, LocalizedError {
    case noInputDevice
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone input is available"
        case .formatCreationFailed: return "Failed to create target audio format"
        case .converterCreationFailed: return "Failed to create audio format converter"
        }
    }
}

// MARK: - Internal helpers

private final class _MutableBoolBox: @unchecked Sendable {
    var value: Bool = false
}
