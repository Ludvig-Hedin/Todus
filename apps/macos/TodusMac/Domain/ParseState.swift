import Foundation

enum ParseState: String, Codable, CaseIterable, Sendable {
    case pending
    case parsed
    case failed
    case raw
}
