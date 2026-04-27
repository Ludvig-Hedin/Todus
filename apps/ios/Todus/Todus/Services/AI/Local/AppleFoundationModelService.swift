import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AppleFoundationModelService
//
// Wraps Apple's `FoundationModels` framework (iOS 26+ / macOS 26+) behind the
// `LocalAIService` protocol. The framework provides a small on-device LLM
// (~3B parameters) when Apple Intelligence is enabled — zero download, zero
// plan-credit cost, fastest possible "hello world" for local inference.
//
// Availability is gated three ways:
//   1. Compile-time: `#if canImport(FoundationModels)` (older Xcode)
//   2. OS version: `#available(iOS 26.0, macOS 26.0, *)`
//   3. Runtime: `SystemLanguageModel.default.availability == .available`
//      (Apple Intelligence may be off, downloading, or unsupported by chip)
//
// On any miss we throw `LocalAIError.runtimeUnavailable` so the chat service
// can fall back cleanly to either a different local runtime or the cloud.

@MainActor
final class AppleFoundationModelService: LocalAIService {
    private let log = Logger(subsystem: "com.todus.ios", category: "AppleFoundationModelService")

    func isReady(for model: LocalModel) -> Bool {
        guard model.runtime == .appleFM else { return false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    func unloadAll() {
        // Apple FM owns its own lifecycle; the framework reuses sessions
        // efficiently and we don't hold long-lived state. Nothing to evict.
    }

    func stream(_ request: LocalChatRequest) -> AsyncThrowingStream<LocalStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await runStream(request, continuation: continuation)
                } catch is CancellationError {
                    continuation.finish(throwing: LocalAIError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private func runStream(
        _ request: LocalChatRequest,
        continuation: AsyncThrowingStream<LocalStreamEvent, Error>.Continuation
    ) async throws {
        guard request.model.runtime == .appleFM else {
            continuation.finish(throwing: LocalAIError.runtimeUnavailable(
                reason: "Apple Foundation Models can't run \(request.model.displayName)."
            ))
            return
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            continuation.finish(throwing: LocalAIError.runtimeUnavailable(
                reason: "Apple Intelligence requires iOS 26 or macOS 26."
            ))
            return
        }

        let systemModel = SystemLanguageModel.default
        switch systemModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            continuation.finish(throwing: LocalAIError.runtimeUnavailable(
                reason: appleAvailabilityMessage(reason)
            ))
            return
        @unknown default:
            continuation.finish(throwing: LocalAIError.runtimeUnavailable(
                reason: "Apple Intelligence isn't available on this device."
            ))
            return
        }

        let (instructions, prompt) = splitMessages(request.messages)
        let session: LanguageModelSession
        if let instructions {
            session = LanguageModelSession(instructions: Instructions(instructions))
        } else {
            session = LanguageModelSession()
        }

        // Stream tokens. The framework yields cumulative `Snapshot<String>`
        // values; each `.content` is the running concatenation, so we diff
        // against `previous` to emit clean per-chunk deltas.
        var previous = ""
        let stream = session.streamResponse(to: prompt)
        for try await snapshot in stream {
            try Task.checkCancellation()
            let new = snapshot.content
            if new.count > previous.count {
                let delta = String(new.suffix(new.count - previous.count))
                continuation.yield(.token(delta))
                previous = new
            }
        }

        continuation.yield(.done(usage: .zero))
        continuation.finish()
        #else
        continuation.finish(throwing: LocalAIError.runtimeUnavailable(
            reason: "This build can't access Apple Intelligence (FoundationModels framework not available)."
        ))
        #endif
    }

    /// Converts a chat history into (system instructions, user prompt). Apple
    /// FM's `LanguageModelSession` separates "instructions" (system-level,
    /// stable across the conversation) from per-turn prompts. We collapse all
    /// `system` messages into instructions and concatenate everything else
    /// into a single prompt that includes the recent turns — close enough to
    /// chat semantics for v1.
    private func splitMessages(_ messages: [LocalChatMessage]) -> (instructions: String?, prompt: String) {
        var systemBlocks: [String] = []
        var transcript: [String] = []

        for m in messages {
            switch m.role {
            case .system:
                systemBlocks.append(m.content)
            case .user:
                transcript.append("User: \(m.content)")
            case .assistant:
                transcript.append("Assistant: \(m.content)")
            case .tool:
                if let name = m.toolName {
                    transcript.append("Tool (\(name)) result: \(m.content)")
                } else {
                    transcript.append("Tool result: \(m.content)")
                }
            }
        }

        let instructions = systemBlocks.isEmpty ? nil : systemBlocks.joined(separator: "\n\n")
        let prompt = transcript.joined(separator: "\n\n")
        return (instructions, prompt)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func appleAvailabilityMessage(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        // Map Apple's enum to user-actionable copy. Cases the framework uses
        // today: deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady.
        // Use a switch with a default so future cases don't break the build.
        switch reason {
        case .deviceNotEligible:
            return "Apple Intelligence isn't supported on this device."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use this model."
        case .modelNotReady:
            return "Apple Intelligence is still preparing on this device. Try again in a few minutes."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }
    #endif
}
