# Claude CLI→API Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse `ClaudeProvider` from dual CLI/API probe modes down to API-only, then delete the CLI terminal-scrape path (`ClaudeUsageProbe`, `TerminalRenderer`, `SwiftTerm`) that mode-switching made possible to keep around.

**Architecture:** Behavioral surgery, not compiler-guided deletion (contrast with the Phase 1 provider-strip plan). `ClaudeProvider` currently branches on `ClaudeProbeMode` for probe selection, fallback behavior, and background-refresh cadence; this plan removes that branching first (Task 2), then removes the now-provably-dead settings/UI surface (Task 3), then deletes the CLI probe code the branching used to guard (Task 4), then drops the `SwiftTerm` dependency the CLI probe needed (Task 5). Each task ends green (build + full test suite) before committing, same discipline as Phase 1.

**Tech Stack:** Swift 6, Tuist 4.202.4, XCTest/Swift Testing, Mockable. macOS 15 deployment target.

## Global Constraints

- **Single API-only Claude provider.** No probe-mode switching, no CLI fallback logic. `ClaudeAPIUsageProbe` becomes the only way `ClaudeProvider` fetches usage.
- **No regression in account email/org display.** `ClaudeAPIUsageProbe` currently hardcodes `accountEmail: nil, accountOrganization: nil` — Task 1 wires in `ClaudeAccountInfoResolver` (reads `~/.claude.json`, zero CLI/subprocess dependency) so this doesn't silently regress once CLI mode is gone.
- **Green gate after every task.** Because `tuist test` (no args) has a stale-scheme quirk in this environment (reports "no tests to run" even when the scheme has testables), verify with a **clean regenerate**: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open && xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`. Expect `** TEST SUCCEEDED **` with no failures. Do not trust a bare `tuist test` "no tests to run" result as a real signal — always fall back to the `xcodebuild test` command above.
- **This is a fork.** Anything deleted is recoverable via `git log` / `git show` if ever needed again.
- **Personal build only.** No signing/notarization changes in this plan (already handled in Phase 1).

---

## Task 1: Wire `ClaudeAccountInfoResolver` into `ClaudeAPIUsageProbe`

Pure addition — establishes the account-info replacement path before any CLI code is removed, so at no point does account email/org regress.

**Files:**
- Modify: `Sources/Infrastructure/Claude/ClaudeAPIUsageProbe.swift`
- Test: `Tests/InfrastructureTests/Claude/ClaudeAPIUsageProbeTests.swift`

**Interfaces:**
- Consumes: `AccountInfoResolving` protocol (`Sources/Domain/Provider/AccountInfo.swift`) — `func resolve() -> AccountInfo?`. `ClaudeAccountInfoResolver` (`Sources/Infrastructure/Claude/ClaudeAccountInfoResolver.swift`) is the concrete file-reading implementation, already `Sendable`.
- Produces: `ClaudeAPIUsageProbe.init(credentialLoader:networkClient:timeout:snapshotCacheTTL:accountInfoResolver:)` — new trailing parameter, defaulted so existing call sites (`ClaudeBarApp.swift`, other tests) keep compiling unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/InfrastructureTests/Claude/ClaudeAPIUsageProbeTests.swift`, after the `// MARK: - isAvailable Tests` section's closing tests (right before `// MARK: - Snapshot Cache (TTL) Tests`):

```swift
    // MARK: - Account Info Tests

    @Test
    func `probe populates account email and organization from resolver`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_pro")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": {
            "utilization": 25.5,
            "resets_at": "2025-01-15T10:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let resolver = MockAccountInfoResolving()
        given(resolver).resolve().willReturn(Domain.AccountInfo(email: "user@example.com", organization: "Acme Corp"))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork, accountInfoResolver: resolver)

        let snapshot = try await probe.probe()

        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "Acme Corp")
    }

    @Test
    func `probe leaves account email nil when resolver has no data`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_pro")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": {
            "utilization": 10.0,
            "resets_at": "2025-01-15T10:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let resolver = MockAccountInfoResolving()
        given(resolver).resolve().willReturn(nil)

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork, accountInfoResolver: resolver)

        let snapshot = try await probe.probe()

        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open && xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64' -only-testing:InfrastructureTests/ClaudeAPIUsageProbeTests`
Expected: FAIL — `extra argument 'accountInfoResolver' in call` (the initializer doesn't accept it yet).

- [ ] **Step 3: Implement the account-info wiring**

In `Sources/Infrastructure/Claude/ClaudeAPIUsageProbe.swift`, add the stored property right after `private let snapshotCache: SnapshotCache` (around line 130):

```swift
    private let snapshotCache: SnapshotCache
    private let accountInfoResolver: any AccountInfoResolving
```

Update the initializer (around line 158) to accept and store it:

```swift
    public init(
        credentialLoader: ClaudeCredentialLoader = ClaudeCredentialLoader(),
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15,
        snapshotCacheTTL: TimeInterval = Self.defaultSnapshotCacheTTL,
        accountInfoResolver: any AccountInfoResolving = ClaudeAccountInfoResolver()
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.timeout = timeout
        self.snapshotCache = SnapshotCache(ttl: snapshotCacheTTL)
        self.accountInfoResolver = accountInfoResolver
    }
```

In `parseUsageResponse(_:subscriptionType:)` (around line 537-550), replace the hardcoded nils in the returned `UsageSnapshot`:

```swift
        // Determine account tier from subscription type
        let accountTier = parseAccountTier(subscriptionType)

        AppLog.probes.info("Claude API: Parsed \(quotas.count) quotas, tier=\(accountTier?.badgeText ?? "unknown")")

        let accountInfo = accountInfoResolver.resolve()

        return UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: accountInfo?.email,
            accountOrganization: accountInfo?.organization,
            loginMethod: nil,
            accountTier: accountTier,
            costUsage: costUsage
        )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64' -only-testing:InfrastructureTests/ClaudeAPIUsageProbeTests`
Expected: PASS, including the two new tests.

- [ ] **Step 5: Full suite green + commit**

Run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** TEST SUCCEEDED **`, no regressions.

```bash
git add Sources/Infrastructure/Claude/ClaudeAPIUsageProbe.swift Tests/InfrastructureTests/Claude/ClaudeAPIUsageProbeTests.swift
git commit -m "feat(claude): populate account email/org in API probe via ClaudeAccountInfoResolver"
```

---

## Task 2: Collapse `ClaudeProvider` to a single API-only probe

Removes `ClaudeProbeMode` branching, the dual-probe initializer, and all CLI-fallback logic from `ClaudeProvider`. This is the core behavioral change; `ClaudeConfigCard.swift` is untouched here because it talks to the settings repository, not `ClaudeProvider` directly, so it stays compiling (its picker becomes inert dead UI until Task 3 removes it).

**Files:**
- Modify: `Sources/Domain/Provider/Claude/ClaudeProvider.swift`
- Modify: `Sources/App/ClaudeBarApp.swift` (provider registration)
- Modify: `Tests/DomainTests/Provider/Claude/ClaudeProviderTests.swift`
- Modify: `Tests/AcceptanceTests/RefreshSpec.swift`
- Delete: `Tests/AcceptanceTests/ClaudeConfigSpec.swift`

**Interfaces:**
- Produces: `ClaudeProvider.init(probe: any UsageProbe, passProbe: (any ClaudePassProbing)? = nil, settingsRepository: any ProviderSettingsRepository, dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil)` — the *only* initializer going forward (was already present as the "legacy" single-probe init; the dual `cliProbe:apiProbe:` init is deleted). `backgroundRefreshFloor` becomes unconditionally `.seconds(900)`. `probeMode`, `supportsApiMode`, `activeProbe`, `primaryProbe()`, `fallbackProbe()`, `cliFallbackEnabled`, `shouldAttemptFallback(after:)` are all removed.

- [ ] **Step 1: Rewrite `ClaudeProvider.swift`**

Replace the entire contents of `Sources/Domain/Provider/Claude/ClaudeProvider.swift`:

```swift
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

    /// The current guest pass information (nil if never fetched)
    public private(set) var guestPass: ClaudePass?

    /// Whether the provider is currently fetching passes
    public private(set) var isFetchingPasses: Bool = false

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

    /// The probe used to fetch guest pass data
    private let passProbe: (any ClaudePassProbing)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    /// Optional analyzer for daily usage from JSONL session data
    private let dailyUsageAnalyzer: (any DailyUsageAnalyzing)?

    // MARK: - Initialization

    /// Creates a Claude provider.
    /// - Parameters:
    ///   - probe: The probe used to fetch usage data
    ///   - passProbe: The probe used to fetch guest pass data (optional)
    ///   - settingsRepository: The repository for persisting settings
    ///   - dailyUsageAnalyzer: Optional analyzer for daily usage from JSONL session data
    public init(
        probe: any UsageProbe,
        passProbe: (any ClaudePassProbing)? = nil,
        settingsRepository: any ProviderSettingsRepository,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil
    ) {
        self.probe = probe
        self.passProbe = passProbe
        self.settingsRepository = settingsRepository
        self.dailyUsageAnalyzer = dailyUsageAnalyzer
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
    ///
    /// A `.background` refresh skips the daily-usage JSONL scan
    /// (`attachDailyReport`), which the menu-bar label never shows; that scan
    /// runs only when the dropdown is open, which always refreshes
    /// interactively (issue #204).
    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = await report(for: newSnapshot, kind: kind)
            lastError = nil
            return snapshot!
        } catch {
            lastError = error
            throw error
        }
    }

    /// Attaches the daily-usage report for interactive refreshes only.
    /// Background refreshes (the menu-bar poll) skip the JSONL scan to stay cheap
    /// — the menu-bar label never renders the daily report, and the dropdown that
    /// does always refreshes interactively (issue #204).
    private func report(for snapshot: UsageSnapshot, kind: RefreshKind) async -> UsageSnapshot {
        switch kind {
        case .interactive:
            return await attachDailyReport(to: snapshot)
        case .background:
            return snapshot
        }
    }

    /// Attaches daily usage report to snapshot if analyzer is available.
    private func attachDailyReport(to snapshot: UsageSnapshot) async -> UsageSnapshot {
        guard let analyzer = dailyUsageAnalyzer,
              let report = try? await analyzer.analyzeToday(),
              !report.today.isEmpty || !report.previous.isEmpty else {
            return snapshot
        }
        return UsageSnapshot(
            providerId: snapshot.providerId,
            quotas: snapshot.quotas,
            capturedAt: snapshot.capturedAt,
            accountEmail: snapshot.accountEmail,
            accountOrganization: snapshot.accountOrganization,
            loginMethod: snapshot.loginMethod,
            accountTier: snapshot.accountTier,
            costUsage: snapshot.costUsage,
            dailyUsageReport: report
        )
    }

    // MARK: - Guest Pass

    /// Fetches the current guest pass information.
    /// Sets isFetchingPasses during fetch and captures any errors.
    @discardableResult
    public func fetchPasses() async throws -> ClaudePass {
        guard let passProbe else {
            throw PassError.probeNotConfigured
        }

        isFetchingPasses = true
        defer { isFetchingPasses = false }

        do {
            let pass = try await passProbe.probe()
            guestPass = pass
            lastError = nil
            return pass
        } catch {
            lastError = error
            throw error
        }
    }

    /// Whether guest passes feature is available
    public var supportsGuestPasses: Bool {
        passProbe != nil
    }
}

// MARK: - Pass Error

public enum PassError: Error, LocalizedError {
    case probeNotConfigured

    public var errorDescription: String? {
        switch self {
        case .probeNotConfigured:
            return "Guest pass probe is not configured"
        }
    }
}
```

- [ ] **Step 2: Fix the registration site in `ClaudeBarApp.swift`**

In `Sources/App/ClaudeBarApp.swift`, replace the `ClaudeProvider(...)` block (around line 56-62):

```swift
            ClaudeProvider(
                probe: ClaudeAPIUsageProbe(),
                passProbe: ClaudePassProbe(),
                settingsRepository: settingsRepository,
                dailyUsageAnalyzer: ClaudeDailyUsageAnalyzer()
            ),
```

- [ ] **Step 3: Rewrite `ClaudeProviderTests.swift`**

Replace the entire contents of `Tests/DomainTests/Provider/Claude/ClaudeProviderTests.swift`:

```swift
import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("ClaudeProvider Tests")
@MainActor
struct ClaudeProviderTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity

    @Test
    func `claude provider has correct id`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.id == "claude")
    }

    @Test
    func `claude provider has correct name`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.name == "Claude")
    }

    @Test
    func `claude provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.cliCommand == "claude")
    }

    @Test
    func `claude provider has dashboard URL pointing to anthropic`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.dashboardURL != nil)
        #expect(claude.dashboardURL?.host?.contains("anthropic") == true)
    }

    @Test
    func `claude provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.isEnabled == true)
    }

    // MARK: - State

    @Test
    func `claude provider starts with no snapshot`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.snapshot == nil)
    }

    @Test
    func `claude provider starts not syncing`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.isSyncing == false)
    }

    @Test
    func `claude provider starts with no error`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.lastError == nil)
    }

    // MARK: - Delegation

    @Test
    func `claude provider delegates isAvailable to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await claude.isAvailable()
        #expect(isAvailable == true)
    }

    @Test
    func `claude provider delegates refresh to probe`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date())
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let snapshot = try await claude.refresh()
        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Snapshot Storage

    @Test
    func `claude provider stores snapshot after refresh`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.snapshot == nil)
        _ = try await claude.refresh()
        #expect(claude.snapshot != nil)
        #expect(claude.snapshot?.quotas.first?.percentRemaining == 50)
    }

    // MARK: - Error Handling

    @Test
    func `claude provider stores error on refresh failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.lastError == nil)
        do {
            _ = try await claude.refresh()
        } catch {
            // Expected
        }
        #expect(claude.lastError != nil)
    }

    // MARK: - Syncing State

    @Test
    func `claude provider resets isSyncing after refresh completes`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date()))
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.isSyncing == false)
        _ = try await claude.refresh()
        #expect(claude.isSyncing == false)
    }

    // MARK: - Equality via ID

    @Test
    func `two claude providers have same id`() {
        let settings = makeSettingsRepository()
        let provider1 = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let provider2 = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(provider1.id == provider2.id)
    }

    // MARK: - Background Refresh Floor (issue #204)

    @Test
    func `background refresh floor is 15 minutes`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)

        // Floored to the API snapshot-cache TTL so background polling never
        // outpaces the cache and burns extra requests for no fresher data.
        #expect(claude.backgroundRefreshFloor == .seconds(900))
    }
}
```

- [ ] **Step 4: Delete `ClaudeConfigSpec.swift`**

Its three scenarios (#28 mode switching, #29 `supportsApiMode`, #30 expired-session error) are either being removed with the mode-switching feature (#28, #29) or already covered elsewhere: `ProbeErrorTests.swift` tests `sessionExpired`'s friendly-message formatting directly, and `ClaudeProviderTests.claude provider stores error on refresh failure` (above) already covers a provider surfacing a probe error as `lastError`.

```bash
git rm Tests/AcceptanceTests/ClaudeConfigSpec.swift
```

- [ ] **Step 5: Fix `RefreshSpec.swift`'s background-cadence tests**

Replace the block starting at `// MARK: - #204: Power-conscious background refresh` through the end of the `BackgroundSync` struct (i.e. everything from that comment to the file's closing braces) with:

```swift
        // MARK: - #204: Power-conscious background refresh

        /// A clock that records each requested sleep, then ends the loop by
        /// throwing — so one deterministic tick reveals the background cadence.
        private final class RecordingClock: Clock, @unchecked Sendable {
            private let lock = NSLock()
            private var _durations: [Duration] = []
            var durations: [Duration] { lock.withLock { _durations } }
            func sleep(for duration: Duration) async throws {
                lock.withLock { _durations.append(duration) }
                throw CancellationError()
            }
            func sleep(nanoseconds: UInt64) async throws {
                try await sleep(for: .nanoseconds(Int64(nanoseconds)))
            }
        }

        /// A probe that returns the next snapshot in a sequence on each call, so a
        /// test can tell successive refreshes apart by their data.
        private final class SequentialProbe: UsageProbe, @unchecked Sendable {
            private let lock = NSLock()
            private var index = 0
            private let snapshots: [UsageSnapshot]
            init(_ snapshots: [UsageSnapshot]) { self.snapshots = snapshots }
            func probe() async throws -> UsageSnapshot {
                lock.withLock {
                    let snapshot = snapshots[min(index, snapshots.count - 1)]
                    index += 1
                    return snapshot
                }
            }
            func isAvailable() async -> Bool { true }
        }

        @Test
        func `background cadence is at least 15 minutes`() async {
            // Given — a Claude provider and a user who picked the 1-minute option.
            let settings = RefreshSpec.makeSettings()
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            )
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(snapshot)
            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let clock = RecordingClock()
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: clock)

            // When — background sync runs one tick.
            let stream = monitor.startMonitoring(interval: .seconds(60), providerIds: ["claude"])
            for await _ in stream {}

            // Then — the cadence is floored to the 15-minute API cache TTL (#204).
            #expect(clock.durations == [.seconds(900)])
        }

        @Test
        func `interactive refresh is not throttled by the background floor`() async {
            // Given — a Claude provider (which imposes a 15-min background floor)
            // returning a different snapshot on each probe.
            let settings = RefreshSpec.makeSettings()
            let probe = SequentialProbe([
                UsageSnapshot(
                    providerId: "claude",
                    quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                    capturedAt: Date()
                ),
                UsageSnapshot(
                    providerId: "claude",
                    quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, providerId: "claude")],
                    capturedAt: Date()
                ),
            ])
            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())

            // When/Then — two back-to-back user-initiated refreshes both update the
            // snapshot. The 15-min floor governs only the background loop, never the
            // interactive path (#204), so neither call is gated.
            await monitor.refresh(providerId: "claude")
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 80)
            await monitor.refresh(providerId: "claude")
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 60)
        }
    }
}
```

This removes the `CLI mode keeps auto-refreshing in the background` test (its premise — a no-floor CLI mode — no longer exists; the remaining `continuous monitoring emits refresh events` / `monitoring stops when requested` tests earlier in the same file already cover generic background-loop behavior) and the `ClaudeModeSettings` fake (no longer needed once nothing constructs a mode-varying settings repo).

- [ ] **Step 6: Full suite green**

Run: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open && xcodebuild build -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** BUILD SUCCEEDED **`. (Note: `ClaudeConfigCard.swift` will still compile here — it references `ClaudeProbeMode`/`ClaudeSettingsRepository`, both of which still exist until Task 3.)

Run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(claude): collapse ClaudeProvider to a single API-only probe"
```

---

## Task 3: Remove `ClaudeProbeMode`/`ClaudeSettingsRepository` and the mode-picker UI

Everything that made the now-removed dual-mode branching configurable: the enum, the settings sub-protocol, both repository implementations' conformances, the `AppSettings` accessor, and the Settings UI picker.

**Files:**
- Delete: `Sources/Domain/Provider/Claude/ClaudeProbeMode.swift`
- Modify: `Sources/Domain/Provider/ProviderSettingsRepository.swift`
- Modify: `Sources/Infrastructure/Storage/JSONSettingsRepository.swift`
- Modify: `Sources/Infrastructure/Storage/UserDefaultsProviderSettingsRepository.swift`
- Modify: `Sources/App/Settings/AppSettings.swift`
- Modify: `Sources/App/Views/Settings/ClaudeConfigCard.swift`
- Modify: `Tests/InfrastructureTests/Settings/JSONSettingsRepositoryProviderTests.swift`
- Modify: `Tests/InfrastructureTests/UserDefaultsProviderSettingsRepositoryTests.swift`

- [ ] **Step 1: Delete the enum**

```bash
git rm Sources/Domain/Provider/Claude/ClaudeProbeMode.swift
```

- [ ] **Step 2: Remove the `ClaudeSettingsRepository` protocol**

In `Sources/Domain/Provider/ProviderSettingsRepository.swift`, delete this block (around lines 29-42):

```swift
public protocol ClaudeSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Claude (CLI or API)
    func claudeProbeMode() -> ClaudeProbeMode

    /// Sets the probe mode for Claude
    func setClaudeProbeMode(_ mode: ClaudeProbeMode)

    /// Whether to fall back to the CLI probe when the OAuth API probe is unavailable.
    /// Defaults to true. Disable to prevent `claude /usage` from running in API mode.
    func claudeCliFallbackEnabled() -> Bool

    /// Sets whether CLI fallback is enabled in API mode
    func setClaudeCliFallbackEnabled(_ enabled: Bool)
}
```

- [ ] **Step 3: Strip conformance from `JSONSettingsRepository`**

In `Sources/Infrastructure/Storage/JSONSettingsRepository.swift`, remove `ClaudeSettingsRepository,` from the class declaration (around line 12):

```swift
public final class JSONSettingsRepository:
    AppSettingsRepository,
    CodexSettingsRepository,
    HookSettingsRepository,
    @unchecked Sendable
{
```

Delete the `// MARK: - ClaudeSettingsRepository` block (around lines 205-226):

```swift
    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let raw: String = store.read(key: "claude.probeMode"),
              let mode = ClaudeProbeMode(rawValue: raw) else {
            return .cli
        }
        return mode
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        store.write(value: mode.rawValue, key: "claude.probeMode")
    }

    public func claudeCliFallbackEnabled() -> Bool {
        store.read(key: "claude.cliFallbackEnabled") ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "claude.cliFallbackEnabled")
    }
```

- [ ] **Step 4: Strip conformance from `UserDefaultsProviderSettingsRepository`**

In `Sources/Infrastructure/Storage/UserDefaultsProviderSettingsRepository.swift`, remove `ClaudeSettingsRepository,` from the class declaration (line 6):

```swift
public final class UserDefaultsProviderSettingsRepository: CodexSettingsRepository, HookSettingsRepository, @unchecked Sendable {
```

Delete the `// MARK: - ClaudeSettingsRepository` block (lines 46-65):

```swift
    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.claudeProbeMode) else {
            return .cli // Default to CLI mode
        }
        return ClaudeProbeMode(rawValue: rawValue) ?? .cli
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.claudeProbeMode)
    }

    public func claudeCliFallbackEnabled() -> Bool {
        userDefaults.object(forKey: Keys.claudeCliFallbackEnabled) as? Bool ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Keys.claudeCliFallbackEnabled)
    }
```

Remove the two Claude key entries from the `Keys` enum (lines 108-110), keeping the Codex ones:

```swift
    private enum Keys {
        // Hook settings
        static let hookEnabled = "hookConfig.enabled"
        static let hookPort = "hookConfig.port"
        // Codex settings
        static let codexProbeMode = "providerConfig.codexProbeMode"
    }
```

- [ ] **Step 5: Remove the `AppSettings.claude` accessor**

In `Sources/App/Settings/AppSettings.swift`, delete this line (around line 290):

```swift
    public var claude: ClaudeSettingsRepository { repository }
```

(Keep `public var provider: ProviderSettingsRepository { repository }` and the other accessors as-is.)

- [ ] **Step 6: Simplify `ClaudeConfigCard.swift`**

Replace the entire contents of `Sources/App/Views/Settings/ClaudeConfigCard.swift`:

```swift
import SwiftUI
import Domain
import Infrastructure

/// Claude provider configuration card for SettingsView.
struct ClaudeConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var claudeConfigExpanded: Bool = false
    @State private var claudeBudgetExpanded: Bool = false
    @State private var budgetInput: String = ""

    var body: some View {
        VStack(spacing: 12) {
            configCard
            budgetCard
        }
        .onAppear {
            if settings.claudeApiBudget > 0 {
                budgetInput = String(describing: settings.claudeApiBudget)
            }
        }
    }

    // MARK: - Config Card

    private var configCard: some View {
        DisclosureGroup(isExpanded: $claudeConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            configForm
        } label: {
            configHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        claudeConfigExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private var configHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Anthropic API status")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var configForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.accentPrimary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Anthropic API")
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("Calls the Anthropic API directly using OAuth credentials. Usage data is cached for 15 min to stay under rate limits.")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            let credentialLoader = ClaudeCredentialLoader()
            let hasCredentials = credentialLoader.loadCredentials() != nil

            HStack(spacing: 6) {
                Image(systemName: hasCredentials ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(hasCredentials ? theme.statusHealthy : theme.statusWarning)

                Text(hasCredentials ? "OAuth credentials found" : "No OAuth credentials found")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(hasCredentials ? theme.statusHealthy : theme.statusWarning)
            }

            if !hasCredentials {
                Text("Run `claude` in terminal to authenticate, then credentials will be available.")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        DisclosureGroup(isExpanded: $claudeBudgetExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            budgetForm
                .disabled(!settings.claudeApiBudgetEnabled)
                .opacity(settings.claudeApiBudgetEnabled ? 1 : 0.6)
        } label: {
            budgetHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        claudeBudgetExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private var budgetHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude API Budget")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Cost threshold warnings")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $settings.claudeApiBudgetEnabled)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    private var budgetForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MONTHLY BUDGET (USD)")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)

                    TextField("", text: $budgetInput, prompt: Text("10.00").foregroundStyle(theme.textTertiary))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                        .onChange(of: budgetInput) { _, newValue in
                            if let value = Decimal(string: newValue) {
                                settings.claudeApiBudget = value
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Get warnings when approaching your budget threshold.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Text("Only applies to Claude API accounts, not Claude Max.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
```

- [ ] **Step 7: Trim the settings test files**

In `Tests/InfrastructureTests/Settings/JSONSettingsRepositoryProviderTests.swift`, delete the `// MARK: - Claude Settings` block (around lines 114-149):

```swift
    @Test
    func `claudeProbeMode defaults to cli`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeProbeMode() == .cli)
    }

    @Test
    func `setClaudeProbeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeProbeMode(.api)
        #expect(repo.claudeProbeMode() == .api)
    }

    @Test
    func `claudeCliFallbackEnabled defaults to true`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeCliFallbackEnabled() == true)
    }

    @Test
    func `setClaudeCliFallbackEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeCliFallbackEnabled(false)
        #expect(repo.claudeCliFallbackEnabled() == false)
    }
```

In `Tests/InfrastructureTests/UserDefaultsProviderSettingsRepositoryTests.swift`, delete the `// MARK: - Claude CLI Fallback` block (around lines 137-154):

```swift
    // MARK: - Claude CLI Fallback

    @Test
    func `claudeCliFallbackEnabled defaults to true`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        #expect(repository.claudeCliFallbackEnabled() == true)
    }

    @Test
    func `setClaudeCliFallbackEnabled persists value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setClaudeCliFallbackEnabled(false)
        #expect(repository.claudeCliFallbackEnabled() == false)
    }
```

(Leave the closing `}` of the containing suite in place — only remove the block above it.)

- [ ] **Step 8: Full suite green**

Run: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open && xcodebuild build -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** BUILD SUCCEEDED **`.

Run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(claude): remove ClaudeProbeMode/ClaudeSettingsRepository and the mode-picker UI"
```

---

## Task 4: Delete `ClaudeUsageProbe` + `TerminalRenderer` and their tests

Nothing constructs `ClaudeUsageProbe` outside of tests anymore after Task 2/3 — this task removes the dead probe and the terminal-emulation helper it alone used, and updates the three `QuotaDisplaySpec.swift` tests that exercised generic quota-display behavior through it.

**Files:**
- Delete: `Sources/Infrastructure/Claude/ClaudeUsageProbe.swift`
- Delete: `Sources/Infrastructure/Shared/TerminalRenderer.swift`
- Delete: `Tests/InfrastructureTests/Claude/ClaudeUsageProbeTests.swift`
- Delete: `Tests/InfrastructureTests/Claude/ClaudeUsageProbeParsingTests.swift`
- Modify: `Tests/AcceptanceTests/QuotaDisplaySpec.swift`

`ClaudeAccountInfoResolver.swift` and `ClaudeAccountInfoResolverTests.swift` are **not** deleted — Task 1 gave them a live consumer in `ClaudeAPIUsageProbe`.

- [ ] **Step 1: Confirm no other consumers**

Run: `grep -rln "ClaudeUsageProbe\b" Sources/ Tests/`
Expected: only `Sources/Infrastructure/Claude/ClaudeUsageProbe.swift`, `Tests/InfrastructureTests/Claude/ClaudeUsageProbeTests.swift`, `Tests/InfrastructureTests/Claude/ClaudeUsageProbeParsingTests.swift`, and the three `QuotaDisplaySpec.swift` call sites fixed in Step 3 below.

Run: `grep -rln "TerminalRenderer" Sources/ Tests/`
Expected: `Sources/Infrastructure/Claude/ClaudeUsageProbe.swift`, `Sources/Infrastructure/Shared/TerminalRenderer.swift`, `Tests/InfrastructureTests/Claude/ClaudeUsageProbeParsingTests.swift` — all being deleted in this task.

- [ ] **Step 2: Delete the probe, renderer, and their tests**

```bash
git rm Sources/Infrastructure/Claude/ClaudeUsageProbe.swift
git rm Sources/Infrastructure/Shared/TerminalRenderer.swift
git rm Tests/InfrastructureTests/Claude/ClaudeUsageProbeTests.swift
git rm Tests/InfrastructureTests/Claude/ClaudeUsageProbeParsingTests.swift
```

- [ ] **Step 3: Rewrite `QuotaDisplaySpec.swift`'s three CLI-probe-based tests**

These tests simulated raw `claude /usage` terminal output through `ClaudeUsageProbe` to exercise generic snapshot-display behavior (account info, quota status). Since that behavior lives in `ClaudeProvider`/`UsageQuota`/`UsageSnapshot`, not in any specific probe, construct the snapshot directly instead.

Replace the `account email and tier are displayed after refresh` test (in the `AccountInfo` suite):

```swift
        @Test
        func `account email and tier are displayed after refresh`() async throws {
            // Given — probe returns a snapshot with account metadata
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "user@example.com",
                accountOrganization: "Acme Corp",
                accountTier: .claudeMax
            )
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(snapshot)

            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — user opens menu and quota is refreshed
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot != nil)
            #expect(claude.snapshot?.accountEmail == "user@example.com")
            #expect(claude.snapshot?.accountTier == .claudeMax)
        }
```

Replace the `healthy session and warning weekly quotas display with correct status` and `exhausted session shows depleted status` tests (in the `QuotaCards` suite):

```swift
        @Test
        func `healthy session and warning weekly quotas display with correct status`() async throws {
            // Given — 65% session (healthy) and 35% weekly (warning)
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [
                    UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude"),
                    UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
                ],
                capturedAt: Date()
            )
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(snapshot)

            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then — multiple quota cards with correct statuses
            let resultSnapshot = claude.snapshot
            #expect(resultSnapshot != nil)
            #expect(resultSnapshot!.quotas.count == 2)

            let session = resultSnapshot?.quota(for: .session)
            #expect(session?.percentRemaining == 65)
            #expect(session?.status == .healthy)

            let weekly = resultSnapshot?.quota(for: .weekly)
            #expect(weekly?.percentRemaining == 35)
            #expect(weekly?.status == .warning)
        }

        @Test
        func `exhausted session shows depleted status`() async throws {
            // Given — 0% left
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            )
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(snapshot)

            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then
            let session = claude.snapshot?.quota(for: .session)
            #expect(session?.percentRemaining == 0)
            #expect(session?.status == .depleted)
        }
```

- [ ] **Step 4: Full suite green**

Run: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open && xcodebuild build -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** BUILD SUCCEEDED **`. (`SwiftTerm` is still linked into `Infrastructure` here — Task 5 drops it — so this should build clean even though nothing in Claude uses it anymore.)

Run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(claude): delete ClaudeUsageProbe and TerminalRenderer"
```

---

## Task 5: Drop the `SwiftTerm` dependency

Nothing in `Sources/` references `SwiftTerm` after Task 4 — remove it from the Tuist project and package manifest.

**Files:**
- Modify: `Project.swift`
- Modify: `Tuist/Package.swift`

- [ ] **Step 1: Confirm no remaining references**

Run: `grep -rln "SwiftTerm" Sources/ Tests/`
Expected: no output.

- [ ] **Step 2: Remove the dependency from `Project.swift`**

In the `Infrastructure` target's `dependencies` array (around line 50-54), remove the `SwiftTerm` line:

```swift
            dependencies: [
                .target(name: "Domain"),
                .external(name: "Mockable"),
            ],
```

- [ ] **Step 3: Remove the package from `Tuist/Package.swift`**

Replace the full contents of `Tuist/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription


#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    targetSettings: [
        "IssueReporting": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
        "IssueReportingPackageSupport": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
    ]
)
#endif

let package = Package(
    name: "ClaudeBar",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
        // Exposes MenuBarExtra's underlying NSStatusItem so the menu-bar label
        // can be driven imperatively (AppKit), surviving the SwiftUI label
        // freeze after system sleep (issue #192).
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.0"),
    ]
)
```

- [ ] **Step 4: Reinstall dependencies and verify green**

Run: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist install && tuist generate --no-open && xcodebuild build -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** BUILD SUCCEEDED **`, with no `SwiftTerm` project generated in the workspace.

Run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(deps): drop SwiftTerm now that ClaudeUsageProbe is gone"
```

---

## Task 6: Update architecture/behavior docs + final verification

**Files:**
- Modify: `docs/architecture/USER_BEHAVIORS.md`
- Modify: `docs/architecture/ARCHITECTURE.md`

- [ ] **Step 1: Update the Claude Configuration behavior catalog**

In `docs/architecture/USER_BEHAVIORS.md`, replace the `## Claude Configuration` section (from that heading through the `### Inner TDD Tests (existing)` list just before the next `---`):

```markdown
## Claude Configuration

| # | Behavior |
|---|----------|
| 29 | API credential status is shown (found / not found) |
| 30 | Expired session shows "Run `claude` in terminal to log in again" |
| 31 | User sets monthly budget → sees cost-based usage card |

Behaviors #28 (CLI/API mode switching) and #32 (CLI folder-trust auto-accept) were
removed with the CLI probe (`ClaudeUsageProbe`) — Claude now always fetches usage
via the Anthropic OAuth API, so there is no mode to switch and no CLI trust dialog
to dismiss.

### BDD Scenarios

**#30 — Expired session error**
```
Scenario: API returns 401
  Given Claude authenticates via the Anthropic OAuth API
  When the API returns HTTP 401
  Then the error message shows "Session expired. Run `claude` in terminal to log in again"
```

### Inner TDD Tests (existing)
- `ClaudeAPIUsageProbeTests.*`
- `ClaudeCredentialLoaderTests.*`
- `ProbeErrorTests.sessionExpired description`

---
```

- [ ] **Step 2: Fix the stale architecture diagram line**

In `docs/architecture/ARCHITECTURE.md`, replace (around line 72):

```
│  ├── ClaudeUsageProbe - probes `claude /usage` (CLI + API)          │
```

with:

```
│  ├── ClaudeAPIUsageProbe - probes Anthropic OAuth API                │
```

(The rest of that diagram already lists several providers removed in Phase 1 — Zai, Bedrock, AmpCode, Kimi, Gemini, Copilot — as pre-existing stale documentation debt from before this plan; out of scope here.)

- [ ] **Step 3: Final full-suite verification**

Run: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist install && tuist generate --no-open && xcodebuild build -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** BUILD SUCCEEDED **`.

Run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'`
Expected: `** TEST SUCCEEDED **`, full suite green.

Run: `grep -rn "ClaudeProbeMode\|ClaudeUsageProbe\|ClaudeSettingsRepository\|TerminalRenderer\|SwiftTerm" Sources/ Tests/ Project.swift Tuist/Package.swift`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: update Claude Configuration behaviors and architecture diagram for API-only cutover"
```

---

## Done criteria

- `ClaudeProvider` has a single initializer taking one `UsageProbe`; no `ClaudeProbeMode`, no CLI fallback, no `cliProbe`/`apiProbe` distinction.
- `ClaudeAPIUsageProbe` populates `accountEmail`/`accountOrganization` via `ClaudeAccountInfoResolver`.
- `ClaudeUsageProbe.swift`, `TerminalRenderer.swift`, and `ClaudeProbeMode.swift` no longer exist.
- `SwiftTerm` is not in `Project.swift` or `Tuist/Package.swift`.
- `ClaudeConfigCard` shows API status + credential health + budget only — no mode picker.
- Full test suite green via `xcodebuild test` on a freshly `tuist generate`d workspace.
- `docs/architecture/USER_BEHAVIORS.md` and the one stale diagram line in `docs/architecture/ARCHITECTURE.md` reflect the API-only reality.
