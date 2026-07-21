import Foundation
import Observation

/// Claude AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Fetches usage via the Anthropic OAuth API.
@MainActor
@Observable
public final class ClaudeProvider: AIProvider {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "claude"
    public let name: String = "Claude"
    public let cliCommand: String = "claude"

    public var dashboardURL: URL? {
        URL(string: "https://console.anthropic.com/settings/billing")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.anthropic.com")
    }

    /// Whether the provider is enabled (persisted via settingsRepository)
    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data
    public private(set) var isSyncing: Bool = false

    /// The current usage snapshot (nil if never refreshed or unavailable)
    public private(set) var snapshot: UsageSnapshot?

    /// The last error that occurred during refresh
    public private(set) var lastError: Error?

    /// Background poll cadence floor, in lockstep with `ClaudeAPIUsageProbe`'s
    /// snapshot-cache TTL: polling faster only re-serves the cache (or, once
    /// expired, risks 429s), so there's no benefit to a tighter background
    /// cadence (issue #204).
    public var backgroundRefreshFloor: Duration? {
        .seconds(900)
    }

    // MARK: - Internal

    /// The probe used to fetch usage data via the Anthropic OAuth API
    private let probe: any UsageProbe

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    // MARK: - Initialization

    /// Creates a Claude provider.
    /// - Parameters:
    ///   - probe: The probe used to fetch usage data
    ///   - settingsRepository: The repository for persisting settings
    public init(
        probe: any UsageProbe,
        settingsRepository: any ProviderSettingsRepository
    ) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        // Load persisted enabled state (defaults to true)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Interactive refresh: delegates to the kind-aware implementation.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        try await refresh(.interactive)
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Sets isSyncing during refresh and captures any errors.
    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil
            return snapshot!
        } catch {
            lastError = error
            throw error
        }
    }
}
