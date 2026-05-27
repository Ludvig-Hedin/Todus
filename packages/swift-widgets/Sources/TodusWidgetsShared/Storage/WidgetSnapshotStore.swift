import Foundation

public final class WidgetSnapshotStore: @unchecked Sendable {
    public static let shared = WidgetSnapshotStore()

    private let appGroupID = "group.com.ludvighedin.todus"
    private let fileName = "widget_snapshot.json"
    private let lock = NSLock()

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private var snapshotFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(fileName)
    }

    private init() {}

    // MARK: - Pending task completions (widget → main app)

    private let pendingCompletionsKey = "pendingTaskCompletions"
    private var appGroupDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Queues a task id completed from a widget so the main app can apply it to
    /// SwiftData + sync on next launch/foreground. The AppIntent extension can't
    /// touch the main app's SwiftData store directly, so it hands off here.
    public func addPendingCompletion(_ taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let defaults = appGroupDefaults else { return }
        var ids = defaults.stringArray(forKey: pendingCompletionsKey) ?? []
        if !ids.contains(taskId) { ids.append(taskId) }
        defaults.set(ids, forKey: pendingCompletionsKey)
    }

    /// Returns and clears the queued completions (called by the main app).
    public func consumePendingCompletions() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let defaults = appGroupDefaults else { return [] }
        let ids = defaults.stringArray(forKey: pendingCompletionsKey) ?? []
        if !ids.isEmpty { defaults.removeObject(forKey: pendingCompletionsKey) }
        return ids
    }

    /// Reads the current snapshot from the App Group container
    public func readSnapshot() -> WidgetDataStore? {
        lock.lock()
        defer { lock.unlock() }
        return readSnapshotLocked()
    }

    /// Writes a new snapshot to the App Group container
    public func writeSnapshot(_ store: WidgetDataStore) {
        lock.lock()
        defer { lock.unlock() }
        writeSnapshotLocked(store)
    }

    /// Atomically reads, transforms, and writes the snapshot under a single lock,
    /// closing the TOCTOU window between concurrent read/modify/write callers.
    public func updateSnapshot(_ transform: (inout WidgetDataStore) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var store = readSnapshotLocked() ?? WidgetDataStore()
        transform(&store)
        writeSnapshotLocked(store)
    }

    private func readSnapshotLocked() -> WidgetDataStore? {
        guard let url = snapshotFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetDataStore.self, from: data)
        } catch {
            print("[WidgetSnapshotStore] Error reading snapshot: \(error)")
            return nil
        }
    }

    private func writeSnapshotLocked(_ store: WidgetDataStore) {
        guard let url = snapshotFileURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(store)
            try data.write(to: url, options: .atomic)
            print("[WidgetSnapshotStore] Successfully wrote snapshot.")
        } catch {
            print("[WidgetSnapshotStore] Error writing snapshot: \(error)")
        }
    }
}
