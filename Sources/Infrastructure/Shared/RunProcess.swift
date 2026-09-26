import Foundation
import Domain

/// Runs `executable` to completion at utility QoS and returns its exit status and stdout.
/// Stdin and stdout are pumped on GCD threads while the child runs (so output larger than
/// the 64 KB pipe buffer cannot deadlock), exit is awaited via `terminationHandler`
/// (no cooperative thread blocks), and a child still running after `timeout` is
/// terminated and `ProbeError.timeout` thrown. Stderr is discarded.
func runProcess(
    _ executable: String,
    _ arguments: [String],
    stdin: Data? = nil,
    timeout: TimeInterval = 10
) async throws -> (status: Int32, stdout: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.qualityOfService = .utility
    let stdout = Pipe()
    let input = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    process.standardInput = stdin == nil ? FileHandle.nullDevice : input

    let (exited, exit) = AsyncStream<Void>.makeStream()
    process.terminationHandler = { _ in exit.finish() }
    try process.run()

    let timer = Task {
        try await Task.sleep(for: .seconds(timeout))
        process.terminate()
    }
    if let stdin {
        DispatchQueue.global(qos: .utility).async {
            try? input.fileHandleForWriting.write(contentsOf: stdin)
            try? input.fileHandleForWriting.close()
        }
    }
    let data = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            continuation.resume(returning: stdout.fileHandleForReading.readDataToEndOfFile())
        }
    }
    for await _ in exited {}
    timer.cancel()
    if case .success = await timer.result { throw ProbeError.timeout }
    return (process.terminationStatus, data)
}
