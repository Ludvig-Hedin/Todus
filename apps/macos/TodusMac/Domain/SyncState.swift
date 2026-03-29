import Foundation

enum SyncState: String, Codable, CaseIterable, Sendable {
    case localOnly
    case pendingUpload
    case synced
    case failed
}
