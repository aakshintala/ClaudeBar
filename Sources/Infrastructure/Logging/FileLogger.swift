import Foundation

/// File-based logger that writes to ~/Library/Logs/ClaudeBar/ClaudeBar.log
/// Provides user-accessible logs for debugging and support.
///
/// Thread-safety: All file operations are serialized on a dedicated dispatch queue.
/// The class is marked `Sendable` because:
/// - `fileURL` and `maxFileSize` are immutable after init
/// - `queue` is a serial queue that serializes all mutable state access
/// - Timestamp formatting happens inside the serial queue
public final class FileLogger: @unchecked Sendable {
    public static let shared = FileLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.tddworks.ClaudeBar.FileLogger")
    private let maxFileSize: UInt64
    private let rotationCheckInterval: Int

    /// ISO8601DateFormatter is thread-safe; one instance is reused across all
    /// writes instead of allocating one per log line.
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatter
    }()

    /// Kept open across writes; touched only from `queue`.
    private var writeHandle: FileHandle?
    private var writesSinceRotationCheck = 0

    private convenience init() {
        // ~/Library/Logs/ClaudeBar/ClaudeBar.log
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("ClaudeBar", isDirectory: true)
        self.init(directory: logsDir)
    }

    /// - Parameters:
    ///   - directory: Where `ClaudeBar.log` (and its `.old.log` rotation) live. Exposed so tests
    ///     can point at a temp directory instead of `~/Library/Logs`.
    ///   - maxFileSize: Rotation threshold in bytes. Exposed so tests don't need to write 5 MB.
    ///   - rotationCheckInterval: How many writes between size checks.
    init(directory: URL, maxFileSize: UInt64 = 5 * 1024 * 1024, rotationCheckInterval: Int = 100) {
        // Create directory if needed
        // Note: Can't use AppLog here as FileLogger is used by AppLog (circular dependency)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("[FileLogger] Failed to create logs directory at %@: %@", directory.path, error.localizedDescription)
        }

        self.fileURL = directory.appendingPathComponent("ClaudeBar.log")
        self.maxFileSize = maxFileSize
        self.rotationCheckInterval = rotationCheckInterval
    }

    deinit {
        try? writeHandle?.close()
    }

    /// Blocks until every write queued so far has completed. Test-only: `log`
    /// is fire-and-forget on a background queue, so tests need a sync point
    /// before asserting on file contents.
    func flushForTesting() {
        queue.sync {}
    }

    /// Log levels matching OSLog conventions
    public enum Level: String, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Write a log entry to the file
    public func log(_ level: Level, category: String, message: String) {
        queue.async { [self] in
            writesSinceRotationCheck += 1
            if writesSinceRotationCheck >= rotationCheckInterval {
                writesSinceRotationCheck = 0
                rotateIfNeeded()
            }

            let ts = formatter.string(from: Date())
            let line = "[\(ts)] [\(level.rawValue)] [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            write(data)
        }
    }

    /// Appends to a single open handle, opening (or creating) it on first use
    /// and after rotation. Called only from `queue`.
    private func write(_ data: Data) {
        if writeHandle == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            writeHandle = handle
        }
        writeHandle?.write(data)
    }

    /// Rotate log file if it exceeds max size. Called only from `queue`.
    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else {
            return
        }

        // Close the handle before moving the file out from under it.
        try? writeHandle?.close()
        writeHandle = nil

        // Rotate: rename current to .old, start fresh
        let oldURL = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: fileURL, to: oldURL)
    }
}
