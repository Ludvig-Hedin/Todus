import Foundation
import SwiftData

@MainActor
protocol SyncService: AnyObject {
    func enqueue(_ mutations: [SyncMutation], in context: ModelContext) async
    func upgradeAnonymousUserIfNeeded(email: String, in context: ModelContext) async
}
