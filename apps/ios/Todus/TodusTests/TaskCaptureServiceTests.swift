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

    // MARK: - Capture sync safety (IOS-0608-1)
    //
    // Local captures are never deleted by a remote failure. Retryable failures
    // remain `.localOnly`; a semantic rejection may be surfaced as `.failed`.
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

    private func taskListResponseBody(
        id: UUID,
        title: String = "Remote task",
        updatedAt: String = "2025-01-02T12:00:00.000Z"
    ) throws -> Data {
        let task: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "title": title,
            "description": "Synced from another device",
            "status": "done",
            "priority": "high",
            "dueDate": "2025-01-03T12:00:00.000Z",
            "folderId": NSNull(),
            "reminderIdentifier": NSNull(),
            "emailThreadId": "thread-remote",
            "eventId": "event-remote",
            "createdAt": "2025-01-01T12:00:00.000Z",
            "updatedAt": updatedAt
        ]
        return try JSONSerialization.data(withJSONObject: [
            "result": ["data": ["json": ["tasks": [task]]]]
        ])
    }

    private func emptyTaskListResponseBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "result": ["data": ["json": ["tasks": []]]]
        ])
    }

    private func taskDeletionResponseBody(id: UUID? = nil) throws -> Data {
        let deletions: [[String: Any]] = id.map {
            [[
                "taskId": $0.uuidString.lowercased(),
                "deletedAt": "2025-01-04T12:00:00.000Z"
            ]]
        } ?? []
        return try JSONSerialization.data(withJSONObject: [
            "result": ["data": ["json": ["deletions": deletions]]]
        ])
    }

    @MainActor
    private func makeSyncService(
        configuration: AppConfiguration,
        apiClient: TodosAPIClient? = nil
    ) -> SupabaseSyncService {
        let client: TodosAPIClient
        if let apiClient {
            client = apiClient
        } else {
            // AuthService intentionally clears preloaded tokens on a simulated
            // first install. This suite tests transport, not first-launch auth.
            UserDefaults.standard.set(true, forKey: "Todus.hasLaunchedBefore")
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.protocolClasses = [SyncURLProtocolStub.self]
            let auth = AuthService(
                backendURL: URL(string: "https://stub.local")!,
                preloaded: AuthBootstrapTokens(
                    bearerToken: "test-token",
                    refreshToken: nil,
                    currentSessionId: nil
                )
            )
            client = TodosAPIClient(
                baseURL: URL(string: "https://stub.local")!,
                authService: auth,
                sessionConfiguration: sessionConfiguration
            )
        }
        return SupabaseSyncService(
            configuration: configuration,
            authStore: AuthSessionStore(configuration: configuration),
            apiClient: client
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
    private func assertHTTPFailureKeepsCapture(
        statusCode: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        SyncURLProtocolStub.outcome = .status(statusCode)

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = makeSyncService(configuration: config)
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(
            task.syncState,
            .localOnly,
            "HTTP \(statusCode) must retain the capture for retry.",
            file: file,
            line: line
        )
    }

    @MainActor
    func testOfflineCaptureKeptLocalOnlyNotDeleted() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .urlError(.notConnectedToInternet)

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = makeSyncService(configuration: config)
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
        let sync = makeSyncService(configuration: config)
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .localOnly,
            "A 5xx is transient and must keep the task for reconnect retry instead of deleting it.")
    }

    @MainActor
    func testRateLimitKeepsCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        try await assertHTTPFailureKeepsCapture(statusCode: 429)
    }

    @MainActor
    func testAuthFailuresKeepCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }

        try await assertHTTPFailureKeepsCapture(statusCode: 401)
        try await assertHTTPFailureKeepsCapture(statusCode: 403)
    }

    @MainActor
    func testRequestTimeoutKeepsCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        try await assertHTTPFailureKeepsCapture(statusCode: 408)
    }

    @MainActor
    func testNonAllowlistedClientErrorsKeepCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }

        try await assertHTTPFailureKeepsCapture(statusCode: 400)
        try await assertHTTPFailureKeepsCapture(statusCode: 409)
    }

    @MainActor
    func testMalformedSuccessKeepsCaptureLocalOnly() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .response(status: 200, body: Data("not-json".utf8))

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let sync = makeSyncService(configuration: config)
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
        let sync = makeSyncService(configuration: config)
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .failed,
            "An explicit semantic 4xx rejection is the only rollback case.")
    }

    @MainActor
    func testTaskSyncUsesTRPCShapeAndKeepsDueDateAsISOString() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .taskSyncSuccess
        SyncURLProtocolStub.lastRequestBody = nil

        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: nil)
        let sync = makeSyncService(configuration: config)
        let task = makeSyncTask(in: ctx)
        task.dueDate = Date(timeIntervalSince1970: 1_735_732_800)
        task.emailThreadId = "thread-123"
        task.eventId = "event-456"
        try ctx.save()

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .synced)
        let body = try XCTUnwrap(SyncURLProtocolStub.lastRequestBody)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(root["meta"], "dueDate must not be revived into a JS Date before Zod validation")
        let input = try XCTUnwrap(root["json"] as? [String: Any])
        let mutations = try XCTUnwrap(input["mutations"] as? [[String: Any]])
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations[0]["type"] as? String, "upsert")
        XCTAssertEqual(mutations[0]["id"] as? String, task.id.uuidString)
        let payload = try XCTUnwrap(mutations[0]["payload"] as? [String: Any])
        XCTAssertEqual(payload["title"] as? String, "buy milk")
        XCTAssertEqual(payload["emailThreadId"] as? String, "thread-123")
        XCTAssertEqual(payload["eventId"] as? String, "event-456")
        XCTAssertNotNil(payload["dueDate"] as? String)
    }

    @MainActor
    func testRemoteTaskReconciliationHydratesSignedInCache() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        let remoteID = UUID()
        SyncURLProtocolStub.outcome = .taskReconcile(
            tasks: try taskListResponseBody(id: remoteID),
            deletions: try taskDeletionResponseBody()
        )

        let ctx = try makeSyncContext()
        let sync = makeSyncService(configuration: makeSyncConfig(supabaseURL: nil))

        await sync.reconcileRemoteTasks(in: ctx)

        let tasks = try ctx.fetch(FetchDescriptor<TaskRecord>())
        let task = try XCTUnwrap(tasks.first { $0.id == remoteID })
        XCTAssertEqual(task.title, "Remote task")
        XCTAssertEqual(task.taskDescription, "Synced from another device")
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.syncState, .synced)
        XCTAssertEqual(task.emailThreadId, "thread-remote")
        XCTAssertEqual(task.eventId, "event-remote")
        XCTAssertNotNil(task.dueDate)
    }

    @MainActor
    func testRemoteTaskReconciliationDoesNotOverwritePendingLocalEdit() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        let taskID = UUID()
        SyncURLProtocolStub.outcome = .taskReconcile(
            tasks: try taskListResponseBody(id: taskID, title: "Stale remote"),
            deletions: try taskDeletionResponseBody(id: taskID)
        )

        let ctx = try makeSyncContext()
        let local = TaskRecord(
            id: taskID,
            rawInput: "Local edit",
            title: "Local edit",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            parseState: .parsed,
            syncState: .localOnly
        )
        ctx.insert(local)
        try ctx.save()
        let sync = makeSyncService(configuration: makeSyncConfig(supabaseURL: nil))

        await sync.reconcileRemoteTasks(in: ctx)

        XCTAssertEqual(local.title, "Local edit")
        XCTAssertEqual(local.syncState, .localOnly)
    }

    @MainActor
    func testRemoteTaskDeletionRemovesSyncedTaskAndCleansMirrors() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        let taskID = UUID()
        SyncURLProtocolStub.outcome = .taskReconcile(
            tasks: try emptyTaskListResponseBody(),
            deletions: try taskDeletionResponseBody(id: taskID)
        )

        let ctx = try makeSyncContext()
        let local = TaskRecord(
            id: taskID,
            rawInput: "Delete elsewhere",
            title: "Delete elsewhere",
            reminderIdentifier: "reminder-123",
            parseState: .parsed,
            syncState: .synced
        )
        ctx.insert(local)
        try ctx.save()
        let sync = makeSyncService(configuration: makeSyncConfig(supabaseURL: nil))
        var cleanedMirror: (UUID, String?)?
        sync.onRemoteTaskDeleted = { id, reminderIdentifier in
            cleanedMirror = (id, reminderIdentifier)
        }

        await sync.reconcileRemoteTasks(in: ctx)

        XCTAssertTrue(try ctx.fetch(FetchDescriptor<TaskRecord>()).isEmpty)
        XCTAssertEqual(cleanedMirror?.0, taskID)
        XCTAssertEqual(cleanedMirror?.1, "reminder-123")
    }

    func testEdgeClientPreservesHTTPStatusAndBody() async throws {
        URLProtocol.registerClass(SyncURLProtocolStub.self)
        defer { URLProtocol.unregisterClass(SyncURLProtocolStub.self) }
        SyncURLProtocolStub.outcome = .response(status: 403, body: Data("forbidden".utf8))

        struct Request: Encodable { let value: String }
        struct Response: Decodable { let success: Bool }

        let config = makeSyncConfig(supabaseURL: URL(string: "https://stub.local")!)
        let client = SupabaseEdgeFunctionClient(configuration: config)

        do {
            let _: Response = try await client.invoke(
                path: config.syncFunctionPath,
                body: Request(value: "test")
            )
            XCTFail("Expected the edge client to throw for HTTP 403.")
        } catch BackendClientError.httpError(let statusCode, let responseBody) {
            XCTAssertEqual(statusCode, 403)
            XCTAssertEqual(responseBody, "forbidden")
        } catch {
            XCTFail("Expected BackendClientError.httpError, got \(error).")
        }
    }

    @MainActor
    func testUnconfiguredBackendKeepsCaptureLocalOnly() async throws {
        // No unified API client means there is nowhere to upload. Keep, don't delete.
        let ctx = try makeSyncContext()
        let config = makeSyncConfig(supabaseURL: nil)
        let sync = SupabaseSyncService(configuration: config, authStore: AuthSessionStore(configuration: config))
        let task = makeSyncTask(in: ctx)

        await enqueueSync(sync, task, in: ctx)

        XCTAssertEqual(task.syncState, .localOnly,
            "A task with no usable API client must be kept .localOnly, not rolled back/deleted.")
    }
}

/// Failable URLProtocol stub for the task-sync transport and its retained legacy
/// edge-client status-code test.
final class SyncURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Outcome {
        case urlError(URLError.Code)
        case status(Int)
        case response(status: Int, body: Data)
        case taskReconcile(tasks: Data, deletions: Data)
        case taskSyncSuccess
    }
    nonisolated(unsafe) static var outcome: Outcome = .status(200)
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return url.host == "stub.local" || url.absoluteString.contains("functions/v1")
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
        case .taskReconcile(let tasks, let deletions):
            let body = request.url?.path.contains("tasks.deleted") == true ? deletions : tasks
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .taskSyncSuccess:
            // URLSession commonly converts `httpBody` into an input stream before
            // handing the request to URLProtocol. Read either representation so
            // the transport assertion covers the actual bytes sent on device.
            let body = requestBody()
            Self.lastRequestBody = body
            let id: String = {
                guard let data = body,
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let input = root["json"] as? [String: Any],
                      let mutations = input["mutations"] as? [[String: Any]],
                      let first = mutations.first,
                      let id = first["id"] as? String else { return "" }
                return id
            }()
            let responseBody = Data(
                #"{"result":{"data":{"json":{"syncedIds":["\#(id)"]}}}}"#.utf8
            )
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}

    private func requestBody() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }
}

final class FolderSyncServiceTests: XCTestCase {
    @MainActor
    func testClearQueueInvalidatesFailureAndProcessesNextAccountMutation() async throws {
        let suiteName = "FolderSyncServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let gate = FolderSyncRequestGate()
        FolderSyncURLProtocolStub.gate = gate
        defer { FolderSyncURLProtocolStub.gate = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FolderSyncURLProtocolStub.self]
        let auth = AuthService(
            backendURL: URL(string: "https://stub.local")!,
            preloaded: AuthBootstrapTokens(
                bearerToken: "test-token",
                refreshToken: nil,
                currentSessionId: nil
            )
        )
        let client = TodosAPIClient(
            baseURL: URL(string: "https://stub.local")!,
            authService: auth,
            sessionConfiguration: config
        )
        let queueKey = "folder-sync-test-\(UUID().uuidString)"
        let service = FolderSyncService(
            apiClient: client,
            defaults: defaults,
            queueKey: queueKey
        )

        let oldAccountSend = Task {
            await service.enqueue(.delete(id: "old-account-folder"))
        }
        await gate.waitForFirstRequest()

        // Mirrors AppServices.signOut(): the next enqueue belongs to a newly
        // authenticated account and must not inherit the failed old batch.
        service.clearQueue()
        let newAccountSend = Task {
            await service.enqueue(.delete(id: "new-account-folder"))
        }
        for _ in 0..<10 where !service.hasPending(id: "new-account-folder") {
            await Task.yield()
        }
        XCTAssertTrue(service.hasPending(id: "new-account-folder"))

        gate.releaseFirstRequestAsFailure()
        await oldAccountSend.value
        await newAccountSend.value

        XCTAssertFalse(service.hasPending(id: "old-account-folder"))
        XCTAssertFalse(service.hasPending(id: "new-account-folder"))
        XCTAssertNil(defaults.data(forKey: queueKey))

        XCTAssertEqual(gate.requestCount(), 2)
    }
}

private final class FolderSyncRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseFirst = DispatchSemaphore(value: 0)
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private var firstRequestStarted = false
    private var requests = 0

    func waitForFirstRequest() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if firstRequestStarted {
                lock.unlock()
                continuation.resume()
            } else {
                firstRequestContinuation = continuation
                lock.unlock()
            }
        }
    }

    func releaseFirstRequestAsFailure() {
        releaseFirst.signal()
    }

    func requestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func response(for request: URLRequest) -> (status: Int, data: Data) {
        lock.lock()
        requests += 1
        let requestNumber = requests
        let continuation = requestNumber == 1 ? firstRequestContinuation : nil
        if requestNumber == 1 {
            firstRequestStarted = true
            firstRequestContinuation = nil
        }
        lock.unlock()
        continuation?.resume()

        if requestNumber == 1 {
            _ = releaseFirst.wait(timeout: .now() + 5)
            return (500, Data(#"{"error":"offline"}"#.utf8))
        }
        return (
            200,
            Data(#"{"result":{"data":{"json":{"syncedIds":["new-account-folder"]}}}}"#.utf8)
        )
    }
}

private final class FolderSyncURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var gate: FolderSyncRequestGate?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.absoluteString.contains("folders.sync") ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let gate = Self.gate else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let result = gate.response(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: result.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
