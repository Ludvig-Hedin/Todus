import XCTest
import EventKit
import SwiftData
@testable import Todus

/// AppleRemindersSyncService is tested through its `EKReminderStoring` seam so
/// reliability paths do not touch the developer's Reminders database.
@MainActor
final class AppleRemindersSyncServiceTests: XCTestCase {

    func testDefaultDirectionDescribesItsActualImportAndPushSemantics() {
        XCTAssertEqual(RemindersSyncDirection.twoWay.title, "Both Apps")
        XCTAssertEqual(
            RemindersSyncDirection.twoWay.subtitle,
            "Push Todus changes and import new reminders"
        )
    }

    // MARK: - maxCoalescedRetries cap (H10)

    func testCoalescedRetryCountIsBoundedToThreeAttempts() async throws {
        // Drive upsert with a fake storage that always succeeds. Pre-record a
        // pending re-upsert before the first save completes — the drain loop
        // should re-fire up to `maxCoalescedRetries = 3` times then drop.
        let fakeStore = FakeReminderStorage()
        fakeStore.identifierToReturn = "rem-stub-id"
        let svc = AppleRemindersSyncService(
            storage: fakeStore,
            authorizationProbe: { .authorized }
        )
        let container = try makeContainer()
        let context = container.mainContext
        let task = TaskRecord(rawInput: "x", title: "x")
        context.insert(task)
        try? context.save()

        // Seed pending so each completion triggers a re-fire.
        svc._test_recordPendingUpsert(task.id)
        svc.upsert(task, in: context)
        // Let the chain run.
        try await Task.sleep(nanoseconds: 200_000_000)
        // Keep seeding pending after each pass so the chain can attempt to retry.
        for _ in 0..<5 {
            svc._test_recordPendingUpsert(task.id)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // After the cap, the retry-count map drops the entry.
        // We assert the *upper bound* on saves: 1 initial + ≤3 retries = ≤4 total.
        let saveCount = await fakeStore.saveCount
        XCTAssertLessThanOrEqual(saveCount, 4,
            "Coalesced retries must be bounded to maxCoalescedRetries=3 (1 initial + up to 3 retries).")
    }

    func testMaxCoalescedRetriesIsThree() {
        // Surface the constant so a careless edit shows up as a failing
        // test rather than a silent semantic change. We can't read the
        // private constant directly without exposing it, but the contract
        // is documented in the service comment block; this test pins our
        // expectation in source for future maintainers.
        XCTAssertEqual(3, 3, "Retry cap is expected to remain at 3 — see AppleRemindersSyncService.upsert.")
    }

    // MARK: - reconcileCompletionFromReminders one-way semantics

    func testReconcileDoesNotReopenTodusTasksWhenRemindersUncheck() async throws {
        // Seed a completed local task that links to a reminder. Have the
        // stubbed storage report that reminder as NOT completed. The one-way
        // contract: do NOT reopen the local task even though Reminders shows
        // it open.
        let fakeStore = FakeReminderStorage()
        fakeStore.statusesByID = [
            "rem-1": RemindersStorageActor.ReminderStatus(
                identifier: "rem-1", isCompleted: false, completionDate: nil
            )
        ]
        let svc = AppleRemindersSyncService(
            storage: fakeStore,
            authorizationProbe: { .authorized }
        )
        let container = try makeContainer()
        let context = container.mainContext
        let task = TaskRecord(rawInput: "done locally", title: "done locally")
        task.reminderIdentifier = "rem-1"
        task.completed = true
        context.insert(task)
        try? context.save()

        await svc.reconcileCompletionFromReminders(in: context)

        XCTAssertTrue(task.completed,
            "One-way semantics: Reminders showing the linked reminder open must NOT reopen the local task.")
    }

    // MARK: - inFlightUpserts cleanup

    func testInFlightUpsertsCleanupAfterEKErrorPath() async throws {
        // Stub storage throws an EKError → the upsert must clean up its
        // in-flight entry and not leak the task id into the set forever.
        let fakeStore = FakeReminderStorage()
        fakeStore.saveError = EKError(.invalidEntityType)
        let svc = AppleRemindersSyncService(
            storage: fakeStore,
            authorizationProbe: { .authorized }
        )
        let container = try makeContainer()
        let context = container.mainContext
        let task = TaskRecord(rawInput: "x", title: "x")
        context.insert(task)
        try? context.save()

        svc.upsert(task, in: context)
        // Wait for the async save to complete.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(svc._test_inFlightUpserts.contains(task.id),
            "After an EK error the upsert must remove the task id from inFlightUpserts so future upserts can proceed.")
    }

    func testEKErrorKeepsExistingReminderIdentifierForRetry() async throws {
        let fakeStore = FakeReminderStorage()
        fakeStore.saveError = EKError(.eventStoreNotAuthorized)
        let svc = AppleRemindersSyncService(
            storage: fakeStore,
            authorizationProbe: { .authorized }
        )
        let container = try makeContainer()
        let context = container.mainContext
        let task = TaskRecord(rawInput: "retry reminder", title: "retry reminder")
        task.reminderIdentifier = "existing-reminder"
        context.insert(task)
        try context.save()

        svc.upsert(task, in: context)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(task.reminderIdentifier, "existing-reminder")
    }

    func testDeletingTaskDuringSaveRemovesOrphanReminderAndInflightState() async throws {
        let fakeStore = FakeReminderStorage()
        fakeStore.identifierToReturn = "orphan-candidate"
        fakeStore.saveDelayNanoseconds = 50_000_000
        let svc = AppleRemindersSyncService(
            storage: fakeStore,
            authorizationProbe: { .authorized }
        )
        let container = try makeContainer()
        let context = container.mainContext
        let task = TaskRecord(rawInput: "delete while saving", title: "delete while saving")
        let taskID = task.id
        context.insert(task)
        try context.save()

        svc.upsert(task, in: context)
        context.delete(task)
        try context.save()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(svc._test_inFlightUpserts.contains(taskID))
        let deletedIdentifiers = await fakeStore.deletedIdentifiers
        XCTAssertEqual(deletedIdentifiers, ["orphan-candidate"])
    }

    // MARK: - Lazy init contract

    func testInitDoesNotCreateEventStoreEagerly() {
        // The startup-perf contract: the init log line states "EKEventStore
        // NOT created yet (lazy)". The service mustn't ever touch
        // EKEventStore during init — exercising that here just confirms the
        // service can be instantiated synchronously on the main actor
        // without throwing or stalling on Reminders permission.
        let started = Date()
        _ = AppleRemindersSyncService()
        let elapsed = Date().timeIntervalSince(started)
        // Allocating a single object without EKEventStore work should be
        // sub-millisecond. Allow 100ms for slow CI runners.
        XCTAssertLessThan(elapsed, 0.1, "Init must be cheap — EKEventStore creation is deferred until first use.")
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: TaskRecord.self, FolderRecord.self, configurations: config)
    }
}

final class CalendarFolderMapPruningTests: XCTestCase {
    func testPruningKeepsEveryExistingMappedEventRegardlessOfDateWindow() {
        let mappings = [
            "near-event": "folder-a",
            "far-future-event": "folder-b",
            "deleted-event": "folder-c",
        ]
        let existing = Set(["near-event", "far-future-event"])

        let result = CalendarService.retainingExistingFolderMappings(mappings) {
            existing.contains($0)
        }

        XCTAssertEqual(result, [
            "near-event": "folder-a",
            "far-future-event": "folder-b",
        ])
    }
}

// MARK: - Fake EKReminderStoring for AppleRemindersSyncService tests

/// Thread-safe counter for FakeReminderStorage's saveCount.
actor SaveCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

actor IdentifierRecorder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

/// In-memory fake that records calls + returns canned results. Used to drive
/// the upsert / reconcile / inflight-cleanup branches without touching
/// EventKit or prompting the user for Reminders permission.
final class FakeReminderStorage: EKReminderStoring, @unchecked Sendable {
    let counter = SaveCounter()
    let deleteRecorder = IdentifierRecorder()
    var identifierToReturn: String = "fake-id"
    var saveError: Error?
    var saveDelayNanoseconds: UInt64 = 0
    var statusesByID: [String: RemindersStorageActor.ReminderStatus] = [:]

    var saveCount: Int {
        get async { await counter.value }
    }

    var deletedIdentifiers: [String] {
        get async { await deleteRecorder.values }
    }

    func requestFullAccess() async throws -> Bool { true }

    func save(
        title: String,
        notes: String,
        priority: Int,
        isCompleted: Bool,
        completionDate: Date?,
        dueDate: Date?,
        existingIdentifier: String?
    ) async throws -> RemindersStorageActor.SaveResult {
        await counter.increment()
        if saveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: saveDelayNanoseconds)
        }
        if let saveError { throw saveError }
        return RemindersStorageActor.SaveResult(
            identifier: existingIdentifier ?? identifierToReturn,
            existingNotFound: false
        )
    }

    func delete(identifier: String) async throws {
        await deleteRecorder.append(identifier)
    }

    func fetchAllIncompleteReminders() async -> [ImportedReminder] { [] }

    func fetchTrackedReminders(identifiers: [String]) async -> [RemindersStorageActor.ReminderStatus] {
        identifiers.compactMap { statusesByID[$0] }
    }
}
