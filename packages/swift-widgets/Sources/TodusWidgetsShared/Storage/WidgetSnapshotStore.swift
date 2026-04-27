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
