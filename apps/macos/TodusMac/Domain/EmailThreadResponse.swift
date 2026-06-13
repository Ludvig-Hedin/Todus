import Foundation

/// Full thread detail with messages, returned by `mail.get`.
///
/// Lives in `Domain/` (Foundation-only, no MLX/service deps) so the decode-tolerance
/// unit tests can compile it directly into a standalone test bundle without rebuilding
/// the MLX-linked host app under `@testable`. See MAC-1.
struct GetThreadResponse: Decodable {
    let messages: [EmailMessage]
    let latest: EmailMessage?
    let hasUnread: Bool?
    let totalReplies: Int?
    let labels: [ThreadLabel]?

    struct ThreadLabel: Decodable {
        let id: String
        let name: String
    }

    private enum CodingKeys: String, CodingKey {
        case messages, latest, hasUnread, totalReplies, labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode messages element-by-element so a single malformed message (e.g.
        // missing `id`) is dropped instead of aborting the entire thread decode and
        // surfacing as a hard "couldn't load thread" error screen.
        self.messages = (try? container.decode([FailableDecodable<EmailMessage>].self, forKey: .messages))?
            .compactMap(\.value) ?? []
        self.latest = (try? container.decodeIfPresent(EmailMessage.self, forKey: .latest)) ?? nil
        self.hasUnread = try container.decodeIfPresent(Bool.self, forKey: .hasUnread)
        self.totalReplies = try container.decodeIfPresent(Int.self, forKey: .totalReplies)
        self.labels = try container.decodeIfPresent([ThreadLabel].self, forKey: .labels)
    }

    /// Synthesised initializer for tests / cache assembly that build a response directly.
    init(messages: [EmailMessage], latest: EmailMessage? = nil, hasUnread: Bool? = nil,
         totalReplies: Int? = nil, labels: [ThreadLabel]? = nil) {
        self.messages = messages
        self.latest = latest
        self.hasUnread = hasUnread
        self.totalReplies = totalReplies
        self.labels = labels
    }
}

/// Wraps a `Decodable` element so a decode failure yields `nil` instead of
/// throwing — lets an array decode survive individual malformed elements.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
    }
}

/// Alias for readability in thread detail views.
typealias EmailThreadDetail = GetThreadResponse
