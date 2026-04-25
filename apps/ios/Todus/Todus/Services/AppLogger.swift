import Foundation
import OSLog
import QuartzCore

/// Persistent file-based logger. Appends to Documents/app.log across launches.
///
/// Why a file? os.Logger requires Console.app or subsystem filtering to read in Xcode.
/// This file persists between restarts, capturing startup timing from the previous launch,
/// and can be shared via Settings → Developer → Share Logs so the log can be directly
/// read by the dev or an AI assistant.
///
/// Thread-safe: all disk writes are serialized on a background queue.
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("app.log")
    }()

    // Background serial queue so file I/O never blocks the caller
    private let queue = DispatchQueue(label: "com.todus.logger", qos: .utility)

    private init() {
        // On each launch, stamp a separator so it's easy to find where a session begins
        let separator = "\n─── Launch: \(Date()) ───\n"
        queue.async { [weak self] in
            self?.appendLine(separator)
        }
    }

    var logFileURL: URL { fileURL }

    /// Write a log line. Prints to Xcode console AND appends to the log file.
    func log(_ message: String) {
        let line = "[LOG] \(message)"
        print(line)  // Xcode Debug Console
        queue.async { [weak self] in
            self?.appendLine(line + "\n")
        }
    }

    /// Read the entire log file as a string (for sharing or display).
    func readAll() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "(no logs yet)"
    }

    /// Masks PII (emails, tokens) for safe logging. Keeps a short prefix so logs are
    /// still useful for debugging without exposing the full identifier.
    /// Example: `mask("ludvig@example.com")` → `"lud***@example.com"`.
    static func mask(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(empty)" }
        if let atIndex = trimmed.firstIndex(of: "@") {
            let local = trimmed[..<atIndex]
            let domain = trimmed[atIndex...]
            let prefix = local.prefix(3)
            return "\(prefix)***\(domain)"
        }
        // Not an email — treat as opaque token, only show first few chars
        let prefix = trimmed.prefix(3)
        return "\(prefix)***"
    }

    /// Clear the log file (e.g. user-initiated from settings).
    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            try? "".write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Private

    private func appendLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            // File doesn't exist yet — create it
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}

enum PerformanceTrace {
    static let initializeApp: StaticString = "InitializeApp"
    static let appServicesInit: StaticString = "AppServicesInit"
    static let rootStartup: StaticString = "RootStartup"
    static let tabSwitch: StaticString = "TabSwitch"
    static let saveContext: StaticString = "SaveContext"
    static let loadThreads: StaticString = "LoadThreads"
    static let checkEmailConnection: StaticString = "CheckEmailConnection"
    static let remindersSync: StaticString = "RemindersSync"
    static let remindersImport: StaticString = "RemindersImport"
    static let loadTodayEvents: StaticString = "LoadTodayEvents"
    static let calendarEventsFetch: StaticString = "CalendarEventsFetch"
    static let calendarFolderPrune: StaticString = "CalendarFolderPrune"
    static let sharedFolderSync: StaticString = "SharedFolderSync"
    static let taskListRecompute: StaticString = "TaskListRecompute"
    static let attachmentDecode: StaticString = "AttachmentDecode"

    typealias IntervalState = OSSignpostIntervalState

    private static let logger = Logger(subsystem: "com.todus.performance", category: "trace")
    private static let signposter = OSSignposter(logger: logger)

    static func beginInterval(_ name: StaticString, message: String? = nil) -> IntervalState {
        if let message {
            logger.debug("\(message, privacy: .public)")
        }
        return signposter.beginInterval(name)
    }

    static func endInterval(_ name: StaticString, _ state: IntervalState, message: String? = nil) {
        signposter.endInterval(name, state)
        if let message {
            logger.debug("\(message, privacy: .public)")
        }
    }

    static func event(_ name: StaticString, message: String) {
        signposter.emitEvent(name)
        logger.debug("\(message, privacy: .public)")
    }
}

#if DEBUG
final class MainThreadHangWatchdog: @unchecked Sendable {
    static let shared = MainThreadHangWatchdog()

    private let threshold: TimeInterval = 0.2
    private let queue = DispatchQueue(label: "com.todus.hang-watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isStarted = false

    private init() {}

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: .milliseconds(250))
            timer.setEventHandler { [weak self] in
                self?.sampleMainThread()
            }
            self.timer = timer
            timer.resume()
        }
    }

    private func sampleMainThread() {
        let startedAt = CACurrentMediaTime()
        DispatchQueue.main.async {
            let stall = CACurrentMediaTime() - startedAt
            guard stall > self.threshold else { return }
            AppLogger.shared.log(
                "[HangWatchdog] Main thread stall detected: \(String(format: "%.3f", stall))s"
            )
        }
    }
}
#endif
