import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite
@MainActor
struct QuotaMonitorTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// A clock whose `sleep` suspends until the surrounding task is cancelled,
    /// rather than waiting real wall-clock time. The monitoring loop runs exactly
    /// one cycle and then parks here; `stopMonitoring()`
    /// cancels the loop's task, resuming this with a `CancellationError` so the
    /// loop ends at once. Replacing the old real `Task.sleep(60s)` removes the
    /// timing race that made the continuous-monitoring tests flake under load.
    private final class SuspendingClock: Clock, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var cancelled = false

        /// Parks the caller on a continuation that only resumes — throwing
        /// `CancellationError` — once the surrounding task is cancelled, so the
        /// monitoring loop suspends after one cycle instead of sleeping for real.
        func sleep(for duration: Duration) async throws {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    lock.lock()
                    if cancelled {
                        lock.unlock()
                        cont.resume(throwing: CancellationError())
                    } else {
                        continuation = cont
                        lock.unlock()
                    }
                }
            } onCancel: {
                lock.lock()
                cancelled = true
                let cont = continuation
                continuation = nil
                lock.unlock()
                cont?.resume(throwing: CancellationError())
            }
        }

        /// Bridges the legacy nanosecond API onto the cancellation-gated `sleep(for:)`.
        func sleep(nanoseconds: UInt64) async throws {
            try await sleep(for: .nanoseconds(Int64(nanoseconds)))
        }
    }

    private actor RefreshCounter {
        private var value = 0

        func increment() -> Int {
            value += 1
            return value
        }

        func count() -> Int {
            value
        }
    }

    /// Holds probes until opened; waiting on an open gate returns at once.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    private final class CountingUsageProbe: UsageProbe, @unchecked Sendable {
        let providerId: String
        let counter = RefreshCounter()
        private let gate: Gate?
        private let capturedAgo: TimeInterval

        init(providerId: String, gate: Gate? = nil, capturedAgo: TimeInterval = 0) {
            self.providerId = providerId
            self.gate = gate
            self.capturedAgo = capturedAgo
        }

        func probe() async throws -> UsageSnapshot {
            let count = await counter.increment()
            await gate?.wait()
            return UsageSnapshot(
                providerId: providerId,
                quotas: [
                    UsageQuota(
                        percentRemaining: Double(100 - count),
                        quotaType: .session,
                        providerId: providerId
                    ),
                ],
                capturedAt: Date().addingTimeInterval(-capturedAgo)
            )
        }

        func isAvailable() async -> Bool {
            true
        }
    }

    private func makeMonitor(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil
    ) -> QuotaMonitor {
        QuotaMonitor(providers: providers, alerter: alerter, clock: TestClock())
    }

    private func makeSuspendingMonitor(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil
    ) -> QuotaMonitor {
        QuotaMonitor(providers: providers, alerter: alerter, clock: SuspendingClock())
    }


    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Single Provider Monitoring

    @Test
    func `monitor refreshes a provider`() async throws {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude"),
                UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
            ],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        await monitor.refresh()

        // Then
        #expect(provider.snapshot != nil)
        #expect(provider.snapshot?.quotas.count == 2)
        #expect(provider.snapshot?.quota(for: .session)?.percentRemaining == 65)
    }

    @Test
    func `monitor skips unavailable providers`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(false)
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        await monitor.refresh()

        // Then
        #expect(provider.snapshot == nil)
    }

    // MARK: - Multiple Provider Monitoring

    @Test
    func `monitor refreshes all providers concurrently`() async {
        // Given
        let claudeProbe = MockUsageProbe()
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))

        let codexProbe = MockUsageProbe()
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willReturn(UsageSnapshot(
            providerId: "codex",
            quotas: [UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "codex")],
            capturedAt: Date()
        ))

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When
        await monitor.refresh()

        // Then
        #expect(claudeProvider.snapshot?.quota(for: .session)?.percentRemaining == 70)
        #expect(codexProvider.snapshot?.quota(for: .session)?.percentRemaining == 40)
    }

    @Test
    func `one provider failure does not affect others`() async {
        // Given
        let settings = makeSettingsRepository()
        let claudeProbe = MockUsageProbe()
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))

        let codexProbe = MockUsageProbe()
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willThrow(ProbeError.timeout)

        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When
        await monitor.refresh()

        // Then
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
        #expect(codexProvider.lastError != nil)
    }

    // MARK: - Continuous Monitoring

    @Test
    func `background tick refreshes every enabled provider`() async {
        // Given - two enabled providers and one disabled
        let settings = makeSettingsRepository()
        let claudeProbe = CountingUsageProbe(providerId: "claude")
        let codexProbe = CountingUsageProbe(providerId: "codex")
        let cursorProbe = CountingUsageProbe(providerId: "cursor")
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let cursorProvider = CursorProvider(probe: cursorProbe, settingsRepository: settings)
        cursorProvider.isEnabled = false
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [claudeProvider, codexProvider, cursorProvider]),
            clock: RecordingClock()
        )

        // When - one tick (the recording clock ends the loop at its first sleep)
        await monitor.startMonitoring(interval: .seconds(60)).value

        // Then
        #expect(await claudeProbe.counter.count() == 1)
        #expect(await codexProbe.counter.count() == 1)
        #expect(await cursorProbe.counter.count() == 0)
    }

    @Test
    func `concurrent refreshes probe each provider once`() async {
        // Given - probes that hold until released, so the two refreshes overlap
        let settings = makeSettingsRepository()
        let gate = Gate()
        let claudeProbe = CountingUsageProbe(providerId: "claude", gate: gate)
        let codexProbe = CountingUsageProbe(providerId: "codex", gate: gate)
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When - the popover and the feed refresh at the same time
        async let popover: Void = monitor.refresh()
        async let feed: Void = monitor.refresh(force: true)
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Then - still syncing while the joined refresh is in flight
        #expect(claudeProvider.isSyncing)
        await gate.open()
        _ = await (popover, feed)

        #expect(await claudeProbe.counter.count() == 1)
        #expect(await codexProbe.counter.count() == 1)
        #expect(claudeProvider.isSyncing == false)
    }

    @Test
    func `fresh snapshot is re-probed only when forced`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = CountingUsageProbe(providerId: "claude")
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When / Then - a snapshot under a minute old is kept...
        await monitor.refresh()
        await monitor.refresh()
        #expect(await probe.counter.count() == 1)

        // ...unless the user forces a refresh
        await monitor.refresh(force: true)
        #expect(await probe.counter.count() == 2)
    }

    @Test
    func `stale snapshot is re-probed without force`() async {
        // Given - the probe reports data captured two minutes ago
        let settings = makeSettingsRepository()
        let probe = CountingUsageProbe(providerId: "claude", capturedAgo: 120)
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        await monitor.refresh()
        await monitor.refresh()

        // Then
        #expect(await probe.counter.count() == 2)
    }

    @Test
    func `monitor stops when requested`() async {
        // Given
        let settings = makeSettingsRepository()
        let provider = ClaudeProvider(probe: CountingUsageProbe(providerId: "claude"), settingsRepository: settings)
        let monitor = makeSuspendingMonitor(providers: AIProviders(providers: [provider]))

        // When
        let loop = monitor.startMonitoring(interval: .seconds(60))
        monitor.stopMonitoring()

        // Then - the loop ends instead of sleeping for a minute
        await loop.value
        #expect(monitor.isMonitoring == false)
    }

    /// #182 regression guard: monitoring flips `isMonitoring` on at start and
    /// off at stop entirely on the main actor (this @MainActor suite would not
    /// compile otherwise), so observable state is never mutated off-main.
    @Test
    func `startMonitoring keeps observable state on the main actor`() async {
        // Reading and writing isMonitoring here compiles only because both this
        // suite and QuotaMonitor are @MainActor — the structural guard against
        // the #182 off-main mutation. The flow asserts the flag flips on, then off.
        let settings = makeSettingsRepository()
        let provider = ClaudeProvider(probe: CountingUsageProbe(providerId: "claude"), settingsRepository: settings)
        let monitor = makeSuspendingMonitor(providers: AIProviders(providers: [provider]))

        monitor.startMonitoring(interval: .seconds(60))
        #expect(monitor.isMonitoring == true)

        monitor.stopMonitoring()

        #expect(monitor.isMonitoring == false)
    }

    /// Sub-minute and zero intervals clamp up to the 1-minute floor, while
    /// at- or above-floor intervals pass through unchanged (energy — #67).
    @Test
    func `clampedInterval enforces the one minute floor`() {
        #expect(QuotaMonitor.clampedInterval(.seconds(5)) == .seconds(60))
        #expect(QuotaMonitor.clampedInterval(.zero) == .seconds(60))
        #expect(QuotaMonitor.clampedInterval(.seconds(60)) == .seconds(60))
        #expect(QuotaMonitor.clampedInterval(.seconds(300)) == .seconds(300))
        #expect(QuotaMonitor.clampedInterval(.seconds(900)) == .seconds(900))
    }

    // MARK: - Energy Awareness (issue #204)

    /// A controllable `PowerStateProvider` fake. `waitUntilParked()` lets a test
    /// deterministically know the monitoring loop has reached the asleep gate
    /// (and is about to park on the event stream), so a "no refresh while asleep"
    /// assertion is race-free.
    private final class FakePowerStateProvider: PowerStateProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var asleep: Bool
        private var battery: Bool
        private var continuation: AsyncStream<PowerEvent>.Continuation?
        private var asleepChecks = 0
        private var awaitingCheck: CheckedContinuation<Void, Never>?

        init(asleep: Bool = false, onBattery: Bool = false) {
            self.asleep = asleep
            self.battery = onBattery
        }

        var isDisplayAsleep: Bool {
            lock.lock()
            let value = asleep
            var signal: CheckedContinuation<Void, Never>?
            if value {
                asleepChecks += 1
                signal = awaitingCheck
                awaitingCheck = nil
            }
            lock.unlock()
            signal?.resume()
            return value
        }

        var isOnBattery: Bool {
            lock.lock(); defer { lock.unlock() }
            return battery
        }

        func events() -> AsyncStream<PowerEvent> {
            AsyncStream { continuation in
                self.lock.lock()
                self.continuation = continuation
                self.lock.unlock()
            }
        }

        /// Resumes once the loop has read `isDisplayAsleep` while asleep.
        func waitUntilParked() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                if asleepChecks > 0 {
                    lock.unlock()
                    cont.resume()
                } else {
                    awaitingCheck = cont
                    lock.unlock()
                }
            }
        }

        func wake() {
            lock.lock()
            asleep = false
            let cont = continuation
            lock.unlock()
            cont?.yield(.didWake)
        }
    }

    /// A clock that records each requested sleep duration, then ends the loop by
    /// throwing — so a single monitoring tick runs deterministically and the
    /// recorded cadence can be asserted.
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

    @Test
    func `background loop pauses while display asleep and refreshes on wake`() async {
        let settings = makeSettingsRepository()
        let probe = CountingUsageProbe(providerId: "claude")
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let power = FakePowerStateProvider(asleep: true)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: RecordingClock(),
            powerStateProvider: power
        )

        let loop = monitor.startMonitoring(interval: .seconds(60))

        // The loop reaches the asleep gate and parks — no refresh while asleep.
        await power.waitUntilParked()
        #expect(await probe.counter.count() == 0)

        // Waking lets exactly one refresh through, then the clock ends the loop.
        power.wake()
        await loop.value
        #expect(await probe.counter.count() == 1)
    }

    @Test
    func `background loop doubles the cadence while on battery`() async {
        let settings = makeSettingsRepository()
        let provider = CodexProvider(probe: CountingUsageProbe(providerId: "codex"), settingsRepository: settings)
        let power = FakePowerStateProvider(asleep: false, onBattery: true)
        let clock = RecordingClock()
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: clock,
            powerStateProvider: power
        )

        await monitor.startMonitoring(interval: .seconds(600)).value

        // 600s → 1200s on battery (×2).
        #expect(clock.durations == [.seconds(1200)])
    }

    @Test
    func `background loop keeps the normal cadence on AC power`() async {
        let settings = makeSettingsRepository()
        let provider = CodexProvider(probe: CountingUsageProbe(providerId: "codex"), settingsRepository: settings)
        let power = FakePowerStateProvider(asleep: false, onBattery: false)
        let clock = RecordingClock()
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: clock,
            powerStateProvider: power
        )

        await monitor.startMonitoring(interval: .seconds(600)).value

        #expect(clock.durations == [.seconds(600)])
    }

    // MARK: - Provider Collections

    @Test
    func `allProviders returns all registered providers`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then
        #expect(monitor.allProviders.count == 2)
    }

    @Test
    func `enabledProviders returns only enabled providers`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        codex.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then
        #expect(monitor.enabledProviders.count == 1)
        #expect(monitor.enabledProviders.first?.id == "claude")
    }

    // MARK: - Quota Alerter

    @Test
    func `alerter is called on status change`() async {
        // Given
        let mockAlerter = MockQuotaAlerter()
        given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]), alerter: mockAlerter)

        // When
        await monitor.refresh()

        // Then
        verify(mockAlerter).alert(
            providerId: .value("claude"),
            previousStatus: .value(.healthy),
            currentStatus: .value(.critical)
        ).called(1)
    }

    @Test
    func `alerter not called when status unchanged`() async {
        // Given
        let mockAlerter = MockQuotaAlerter()
        given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]), alerter: mockAlerter)

        // When - refresh twice with same status
        await monitor.refresh()
        await monitor.refresh()

        // Then - only notified once (first change from nil/healthy to healthy)
        // Actually, the first refresh won't trigger because healthy -> healthy
        verify(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).called(0)
    }

    // MARK: - Disabled Provider Skipping

    @Test
    func `refresh skips disabled providers`() async {
        // Given
        let claudeProbe = MockUsageProbe()
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))

        let codexProbe = MockUsageProbe()
        // Don't set up codex probe expectations - it shouldn't be called

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        codexProvider.isEnabled = false

        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When
        await monitor.refresh()

        // Then - claude refreshed, codex skipped (no snapshot)
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
    }

    // MARK: - Set Provider Enabled

    @Test
    func `setProviderEnabled disables provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.setProviderEnabled("claude", enabled: false)

        // Then
        #expect(claude.isEnabled == false)
        #expect(monitor.enabledProviders.map(\.id) == ["codex"])
    }

    @Test
    func `setProviderEnabled enables provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        codex.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.setProviderEnabled("codex", enabled: true)

        // Then
        #expect(codex.isEnabled == true)
    }
}
