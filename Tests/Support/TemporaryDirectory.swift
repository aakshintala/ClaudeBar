import Foundation

/// Creates a fresh, empty temporary directory for a test. Callers are
/// responsible for removing it (typically via a `defer`).
func makeTemporaryDirectory(label: String = "quotabar-tests") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
}
