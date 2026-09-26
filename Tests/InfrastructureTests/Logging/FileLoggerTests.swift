import Foundation
import Testing
@testable import Infrastructure

/// Covers the reused FileHandle/formatter and size-checked rotation added to
/// avoid a stat+open+seek+write+close and a fresh ISO8601DateFormatter per line.
@Suite("FileLogger")
struct FileLoggerTests {

    @Test
    func `log writes a line to the log file`() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let logger = FileLogger(directory: dir)
        logger.log(.info, category: "test", message: "hello world")
        logger.flushForTesting()

        let contents = try String(contentsOf: dir.appendingPathComponent("ClaudeBar.log"), encoding: .utf8)
        #expect(contents.contains("[INFO] [test] hello world"))
    }

    @Test
    func `repeated writes append rather than overwrite`() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let logger = FileLogger(directory: dir)
        logger.log(.info, category: "test", message: "first")
        logger.log(.info, category: "test", message: "second")
        logger.flushForTesting()

        let contents = try String(contentsOf: dir.appendingPathComponent("ClaudeBar.log"), encoding: .utf8)
        #expect(contents.contains("first"))
        #expect(contents.contains("second"))
    }

    @Test
    func `rotates to old log once the size threshold is crossed`() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Tiny threshold and a check on every write so the test doesn't need
        // to write megabytes of data to exercise rotation.
        let logger = FileLogger(directory: dir, maxFileSize: 100, rotationCheckInterval: 1)

        let logURL = dir.appendingPathComponent("ClaudeBar.log")
        let oldURL = dir.appendingPathComponent("ClaudeBar.old.log")

        for i in 0..<20 {
            logger.log(.info, category: "test", message: "padding message number \(i) to grow the file")
        }
        logger.flushForTesting()

        #expect(FileManager.default.fileExists(atPath: oldURL.path), "expected rotation to produce ClaudeBar.old.log")

        let oldSize = try FileManager.default.attributesOfItem(atPath: oldURL.path)[.size] as? UInt64
        #expect((oldSize ?? 0) > 100)

        // The active log file keeps accepting writes after rotation.
        logger.log(.info, category: "test", message: "after-rotation")
        logger.flushForTesting()
        let contents = try String(contentsOf: logURL, encoding: .utf8)
        #expect(contents.contains("after-rotation"))
    }

    @Test
    func `does not rotate before the size threshold is crossed`() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let logger = FileLogger(directory: dir, maxFileSize: 1024 * 1024, rotationCheckInterval: 1)
        logger.log(.info, category: "test", message: "small")
        logger.flushForTesting()

        let oldURL = dir.appendingPathComponent("ClaudeBar.old.log")
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
    }
}
