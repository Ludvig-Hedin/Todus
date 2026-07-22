import XCTest
import SwiftData
@testable import Todus

final class TaskCaptureServiceTests: XCTestCase {
    func testSplitInputLinesCreatesOnlyNonEmptyEntries() {
        let lines = TaskCaptureService.splitInputLines(
            """
            Fix navbar bug

              Buy milk tomorrow
            Call Johan 14
            """
        )

        XCTAssertEqual(lines, [
            "Fix navbar bug",
            "Buy milk tomorrow",
            "Call Johan 14"
        ])
    }

    func testInstantTitleKeepsOriginalInput() {
        XCTAssertEqual(TaskCaptureService.instantTitle(from: "  Review QA checklist "), "Review QA checklist")
    }

    // MARK: - Capture rollback safety (IOS-0608-1)
    //
    // `TaskCaptureService` DELETES tasks whose sync ends `.failed`. So a task may
    // only be marked `.failed` when the server actively rejected it — offline /
    // unreachable / unconfigured backends must keep it `.localOnly` so it survives
    // and re-uploads on reconnect, instead of silently deleting offline work.
    // (Lives here, not in a standalone file, so it's part of the TodusTests target's
    // compiled bundle — a new unreferenced .swift file would be discovered but never run.)

    @MainActor
    private func makeSyncContext() throws -> ModelContext {
        let schema = Schema([TaskRecord.self, FolderRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func makeSyncConfig(supabaseURL: URL?) -> AppConfiguration {
        AppConfiguration(
            backendURL: URL(string: "https://api.todus.app"),
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseURL == nil ? "" : "anon-key",
            parseFunctionPath: "parseTasks",
            syncFunctionPath: "syncTasks",
            upgradeFunctionPath: "upgradeAnonymousUser",
            chatFunctionPath: "chatAI",
            primaryModel: "m",
            fallbackModels: []
        )
    }

    @MainActor
    private func makeSyncTask(in ctx: ModelContext) -> TaskRecord {
        let now = Date()
        let task = TaskRecord(
            rawInput: "buy milk", title: "buy milk", taskDescription: "",
            completed: false, status: .todo, priority: .none, attachmentNames: [],
            reminderIdentifier: nil, createdAt: now, updatedAt: now, dueDate: nil,
            folder: nil, parseState: .pending, syncState: .pendingUpload
        )
        ctx.insert(task)
        try? ctx.save()
        return task
    }

    @MainActor
    private func enqueueSync(_ sync: SupabaseSyncService, _ task: TaskRecord, in ctx: ModelContext) async {
        await sync.enqueue(
            [SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)],
            in: ctx
        )
    }

    @MainActor
    func testOfflineCaptureKeptLocalOnlyNotDeleted() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .urlError(.notConnectedToInternet)

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = SupabaseSyncService(configuration: config, authStore: AuthSessionStore(configuration: config))
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .localOnly,
            "An offline (URLError) sync must keep the task .localOnly (retried on reconnect), NOT .failed — which TaskCaptureService deletes.")
    }

    @MainActor
    func testTransientServerFailureKeepsCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .status(500)

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = SupabaseSyncService(configuration: config, authStore: AuthSessionStore(configuration: config))
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .localOnly,
            "A 5xx is transient and must keep the task for reconnect retry instead of deleting it.")
    }

    @MainActor
    func testRateLimitKeepsCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .status(429)

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = SupabaseSyncService(configuration: config, authStore: AuthSessionStore(configuration: config))
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .localOnly)
    }

    @MainActor
    func testMalformedSuccessKeepsCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .response(status: 200, body: Data("not-json".utf8))

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = SupabaseSyncService(configuration: config, authStore: AuthSessionStore(configuration: config))
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .localOnly)
    }

    @MainActor
    func testSemanticClientRejectMarksCaptureFailed() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .status(422)

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = SupabaseSyncService(configuration: config, authStore: AuthSessionStore(configuration: config))
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .failed,
            "An explicit semantic 4xx rejection is the only rollback case.")
    }

    @MainActor
    func testUnconfiguredBackendKeepsCaptureLocalOnly() async throws {
        // backendURL set (a client is built) but supabaseURL nil → invoke throws
        // backendNotConfigured before any network call. Must keep, not delete.
        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: nil)
        let sync = SupabaseSyncService(configuration: config, authStore: AuthSessionStore(configuration: config))
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .localOnly,
            "A task with no usable Supabase endpoint must be kept .localOnly, not rolled back/deleted.")
    }
}

/// Failable URLProtocol stub scoped to the Supabase edge-function path, so it can't
/// interfere with other URLSession.shared traffic in the suite.
final class SyncURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Outcome {
        case urlError(URLError.Code)
        case status(Int)
        case response(status: Int, body: Data)
    }
    nonisolated(unsafe) static var outcome: Outcome = .status(200)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.absoluteString.contains("functions/v1") ?? false
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch SyncURLProtocolStub.outcome {
        case .urlError(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .status(let code):
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .response(let code, let body):
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
