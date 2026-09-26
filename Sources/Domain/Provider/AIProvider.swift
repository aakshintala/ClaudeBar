import Foundation

/// Protocol defining what an AI provider is.
/// Each provider (Claude, Codex, Cursor, OpenCode) is a rich domain model implementing this protocol.
/// Providers are @Observable classes with their own state (isSyncing, snapshot, error).
///
/// `@MainActor` isolates the observable state (isSyncing/snapshot/lastError) to the main
/// actor so its cheap writes land on the same thread the readers (QuotaMonitor, SwiftUI)
/// run on. The heavy probe work stays off-main: `refresh()` suspends at the non-isolated
/// `await probe.probe()`, which runs on the global executor. A `@MainActor` class is
/// implicitly Sendable, so conformers no longer need `@unchecked Sendable`.
@MainActor
public protocol AIProvider: AnyObject, Sendable, Identifiable where ID == String {
    // MARK: - Identity

    /// Unique identifier for the provider (e.g., "claude", "codex", "cursor")
    var id: String { get }

    /// Display name for the provider (e.g., "Claude", "Codex", "Cursor")
    var name: String { get }

    /// Whether the provider is enabled (user can toggle this)
    var isEnabled: Bool { get set }

    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data
    var isSyncing: Bool { get }

    /// The current usage snapshot (nil if never refreshed or unavailable)
    var snapshot: UsageSnapshot? { get }

    /// The last error that occurred during refresh
    var lastError: Error? { get }

    // MARK: - Operations

    /// Checks if the provider is available (CLI installed, credentials present, etc.)
    func isAvailable() async -> Bool

    /// Refreshes the usage data and updates the snapshot.
    @discardableResult
    func refresh() async throws -> UsageSnapshot
}

import Mockable

/// Protocol defining how to probe for usage data.
/// This is an internal implementation detail - callers use AIProvider.refresh() instead.
@Mockable
public protocol UsageProbe: Sendable {
    /// Fetches the current usage snapshot
    func probe() async throws -> UsageSnapshot

    /// Checks if the probe is available (CLI installed, credentials present, etc.)
    func isAvailable() async -> Bool
}
