import Foundation
import OSLog

// MARK: - OllamaInferenceService
//
// macOS-only `LocalAIService` that streams chat from a locally-running Ollama
// daemon at `localhost:11434/api/chat`. Talks to the daemon directly from the
// Mac app — never via the Cloudflare backend — for two reasons:
//
//   1. The backend is a Cloudflare Worker and can't reach the user's
//      localhost. Routing through it would just fail.
//   2. Bypassing the backend is what makes the "no plan credits" guarantee
//      architectural rather than a billing flag.
//
// The daemon's response shape is a stream of newline-delimited JSON objects;
// each one carries a partial `message.content`. We accumulate per chunk, emit
// `.token` events with the delta, and finally a `.done` event with usage
// numbers parsed from the final object's `prompt_eval_count` /
// `eval_count` fields.

final class OllamaInferenceService: LocalAIService {
    private let connector: OllamaConnector
    private let log = Logger(subsystem: "com.todus.macos", category: "OllamaInferenceService")

    init(connector: OllamaConnector) {
        self.connector = connector
    }

    @MainActor
    func isReady(for model: LocalModel) -> Bool {
        guard model.runtime == .ollama else { return false }
        guard connector.isReachable else { return false }
        guard let tag = model.ollamaTag else { return false }
        return connector.installedModels.contains { $0.id == tag }
    }

    func unloadAll() {
        // Ollama manages its own memory; we have no in-process state to evict.
        // The daemon will swap models on its own based on its `keep_alive`.
    }

    func stream(_ request: LocalChatRequest) -> AsyncThrowingStream<LocalStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: LocalAIError.runtimeUnavailable(reason: "Service deallocated."))
                    return
                }
                do {
                    try await self.runStream(request, continuation: continuation)
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
        guard let tag = request.model.ollamaTag else {
            continuation.finish(throwing: LocalAIError.runtimeUnavailable(
                reason: "\(request.model.displayName) has no Ollama tag configured."
            ))
            return
        }

        let baseURL = await MainActor.run { connector.baseURL }
        let endpoint = baseURL.appendingPathComponent("api/chat")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600 // generation can take a while

        let payload = ChatRequestPayload(
            model: tag,
            messages: request.messages.map { ChatRequestPayload.Message(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            options: .init(
                temperature: request.temperature,
                num_predict: request.maxOutputTokens
            )
        )
        req.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LocalAIError.generationFailed(underlying: nil)
        }
        guard http.statusCode == 200 else {
            throw LocalAIError.generationFailed(underlying: NSError(
                domain: "Ollama", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Ollama returned HTTP \(http.statusCode)"]
            ))
        }

        let decoder = JSONDecoder()
        var promptTokens = 0
        var evalTokens = 0

        // Each line from `bytes.lines` is one JSON object.
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8), !data.isEmpty else { continue }

            // Tolerate decode failures on individual chunks — we'd rather drop
            // a single malformed line than abort a long generation.
            guard let chunk = try? decoder.decode(StreamChunk.self, from: data) else {
                log.warning("[Ollama] Failed to decode stream chunk: \(line, privacy: .public)")
                continue
            }

            if let content = chunk.message?.content, !content.isEmpty {
                continuation.yield(.token(content))
            }

            if chunk.done == true {
                promptTokens = chunk.prompt_eval_count ?? 0
                evalTokens = chunk.eval_count ?? 0
                break
            }
        }

        continuation.yield(.done(usage: LocalTokenUsage(
            inputTokens: promptTokens,
            outputTokens: evalTokens
        )))
        continuation.finish()
    }

    // MARK: - Wire types

    private struct ChatRequestPayload: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Options: Encodable {
            let temperature: Double
            let num_predict: Int
        }
    }

    private struct StreamChunk: Decodable {
        let message: Message?
        let done: Bool?
        let prompt_eval_count: Int?
        let eval_count: Int?

        struct Message: Decodable {
            let role: String?
            let content: String
        }
    }
}
