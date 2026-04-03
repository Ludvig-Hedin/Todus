import Foundation
import OSLog

/// Persistent file-based logger for macOS — mirrors the iOS AppLogger.
/// Appends to Documents/app.log across launches for structured diagnostics.
///
/// Thread-safe: all disk writes are serialized on a background queue.
/// Replaces scattered print() calls with a single structured logger.
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("app.log")
    }()

    // Background serial queue so file I/O never blocks the caller
    private let queue = DispatchQueue(label: "com.todus.mac.logger", qos: .utility)

    private init() {
        let separator = "\n─── Launch: \(Date()) ───\n"
        queue.async { [weak self] in
            self?.appendLine(separator)
        }
    }

    var logFileURL: URL { fileURL }

    /// Write a log line. Prints to Xcode console AND appends to the log file.
    func log(_ message: String) {
        let line = "[LOG] \(message)"
        print(line)
        queue.async { [weak self] in
            self?.appendLine(line + "\n")
        }
    }

    /// Read the entire log file as a string (for sharing or display).
    func readAll() -> String {
        queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "(no logs yet)"
        }
    }

    /// Clear the log file.
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
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
