import Testing
import Foundation
@testable import Domain

@Suite
struct QuotaStatusTests {

    // MARK: - Factory Method Tests

    @Test(arguments: [
        (100.0, QuotaStatus.healthy),
        (75.0, .healthy),
        (51.0, .healthy),
        (50.0, .healthy),
        (49.0, .warning),
        (35.0, .warning),
        (20.0, .warning),
        (19.0, .critical),
        (10.0, .critical),
        (1.0, .critical),
        (0.0, .depleted),
        (-1.0, .depleted),
        (-100.0, .depleted),
    ])
    func `status from percentage remaining`(percentRemaining: Double, expected: QuotaStatus) {
        #expect(QuotaStatus.from(percentRemaining: percentRemaining) == expected)
    }

    // MARK: - Needs Attention Tests

    @Test(arguments: [
        (QuotaStatus.healthy, false),
        (.warning, true),
        (.critical, true),
        (.depleted, true),
    ])
    func `needsAttention reflects status severity`(status: QuotaStatus, expected: Bool) {
        #expect(status.needsAttention == expected)
    }

    // MARK: - Comparison Tests (Severity Order)

    @Test
    func `healthy is less severe than warning`() {
        #expect(QuotaStatus.healthy < QuotaStatus.warning)
    }

    @Test
    func `warning is less severe than critical`() {
        #expect(QuotaStatus.warning < QuotaStatus.critical)
    }

    @Test
    func `critical is less severe than depleted`() {
        #expect(QuotaStatus.critical < QuotaStatus.depleted)
    }

    @Test
    func `depleted is most severe`() {
        #expect(QuotaStatus.depleted > QuotaStatus.healthy)
        #expect(QuotaStatus.depleted > QuotaStatus.warning)
        #expect(QuotaStatus.depleted > QuotaStatus.critical)
    }

    @Test
    func `max of multiple statuses returns worst status`() {
        let statuses: [QuotaStatus] = [.healthy, .warning, .critical]
        #expect(statuses.max() == .critical)

        let mixedStatuses: [QuotaStatus] = [.warning, .depleted, .healthy]
        #expect(mixedStatuses.max() == .depleted)
    }

    // MARK: - Burn Rate (Pace-Aware) Tests

    @Test(arguments: [
        // 57% used, 85% time elapsed → burn rate 0.67 → HEALTHY (issue example: Claude SESSION)
        (percentRemaining: 43.0, percentTimeElapsed: 85.0, expected: QuotaStatus.healthy),
        // 53% used, 8.5% time elapsed → burn rate 6.2 → WARNING (issue example: Codex WEEKLY)
        (47.0, 8.5, .warning),
        // Depleted is always depleted, even if burn rate is low
        (0.0, 99.0, .depleted),
        // 15% remaining @ 90% elapsed → burn rate 0.94, well under threshold → healthy
        (15.0, 90.0, .healthy),
        // 15% remaining @ 10% elapsed → burn rate 8.5 → critical (accelerating toward zero)
        (15.0, 10.0, .critical),
        // Live Cursor monthly: 1.8% left @ 87.8% elapsed → burn rate 1.12. Under the
        // 1.5 warning threshold, but that pace exhausts the rest in ~12h with ~3.7 days to reset.
        (1.8, 87.8, .critical),
        // 10% used, 5% elapsed → burn rate 2.0, but 90% remaining — no warning yet
        (90.0, 5.0, .healthy),
        // At the very start of a period, fall back to absolute thresholds.
        // 43% remaining → absolute threshold says warning
        (43.0, 0.0, .warning),
        // Burn rate matters only when remaining < 50% (meaningful warning zone).
        // 55% used, 30% elapsed → burn rate ~1.83 > 1.5, remaining = 45% < 50 → warning
        (45.0, 30.0, .warning),
    ])
    func `pace aware status`(percentRemaining: Double, percentTimeElapsed: Double, expected: QuotaStatus) {
        let status = QuotaStatus.from(percentRemaining: percentRemaining, percentTimeElapsed: percentTimeElapsed)
        #expect(status == expected)
    }
}
