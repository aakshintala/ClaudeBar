import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Tests for NotificationAlerter.
@Suite(.serialized)
struct NotificationAlerterTests {

    // MARK: - Should Alert Tests

    @Test(arguments: [
        (QuotaStatus.warning, true),
        (.critical, true),
        (.depleted, true),
        (.healthy, false),
    ])
    func `shouldAlert reflects status severity`(status: QuotaStatus, expected: Bool) {
        let alerter = NotificationAlerter()

        #expect(alerter.shouldAlert(for: status) == expected)
    }

    // MARK: - Provider Display Name Tests

    @Test
    func `providerDisplayName returns correct names for known providers`() {
        let alerter = NotificationAlerter()

        // Then - returns correct provider names
        #expect(alerter.providerDisplayName(for: "claude") == "Claude")
        #expect(alerter.providerDisplayName(for: "codex") == "Codex")
    }

    @Test
    func `providerDisplayName capitalizes unknown provider id`() {
        // Given - unknown provider IDs (not in registry)
        let alerter = NotificationAlerter()

        // Then - capitalizes the ID
        #expect(alerter.providerDisplayName(for: "unknown") == "Unknown")
        #expect(alerter.providerDisplayName(for: "chatgpt") == "Chatgpt")
    }

    // MARK: - Alert Body Tests

    @Test(arguments: [
        (QuotaStatus.warning, "Claude", "running low"),
        (.critical, "Codex", "critically low"),
        (.depleted, "Cursor", "depleted"),
        (.healthy, "Claude", "recovered"),
    ])
    func `alertBody describes status for provider`(status: QuotaStatus, providerName: String, expectedPhrase: String) {
        let alerter = NotificationAlerter()

        let body = alerter.alertBody(for: status, providerName: providerName)

        #expect(body.contains(providerName))
        #expect(body.contains(expectedPhrase))
    }

    // MARK: - Status Degradation Detection (Domain Logic)

    @Test
    func `status degradation from healthy to warning should trigger alert`() {
        #expect(QuotaStatus.warning > QuotaStatus.healthy)
    }

    @Test
    func `status degradation from warning to critical should trigger alert`() {
        #expect(QuotaStatus.critical > QuotaStatus.warning)
    }

    @Test
    func `status degradation to depleted should trigger alert`() {
        #expect(QuotaStatus.depleted > QuotaStatus.critical)
    }

    @Test
    func `status improvement should not trigger alert`() {
        #expect(QuotaStatus.healthy < QuotaStatus.warning)
    }

    @Test
    func `same status should not trigger alert`() {
        #expect(QuotaStatus.healthy == QuotaStatus.healthy)
    }

    // MARK: - Alert Integration Tests

    @Test(arguments: [
        (providerId: "claude", from: QuotaStatus.healthy, to: QuotaStatus.warning, expectedPhrase: "running low"),
        ("codex", .warning, .critical, "critically low"),
        ("cursor", .critical, .depleted, "depleted"),
    ])
    func `alert sends notification when status degrades`(
        providerId: String,
        from: QuotaStatus,
        to: QuotaStatus,
        expectedPhrase: String
    ) async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willReturn(())
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When
        await alerter.alert(providerId: providerId, previousStatus: from, currentStatus: to)

        // Then
        verify(mockSender).send(
            title: .matching { $0.contains("Quota Alert") },
            body: .matching { $0.contains(expectedPhrase) },
            categoryIdentifier: .value("QUOTA_ALERT")
        ).called(1)
    }

    @Test(arguments: [
        (from: QuotaStatus.warning, to: QuotaStatus.healthy), // status improves
        (.warning, .warning), // status stays the same
    ])
    func `alert does not send notification when status does not degrade`(from: QuotaStatus, to: QuotaStatus) async {
        // Given
        let mockSender = MockAlertSender()
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When
        await alerter.alert(providerId: "claude", previousStatus: from, currentStatus: to)

        // Then - no alert sent
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(0)
    }

    @Test
    func `alert silently handles sender errors`() async {
        // Given - sender throws an error
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willThrow(NSError(domain: "test", code: 1))
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When & Then - should not throw
        await alerter.alert(providerId: "claude", previousStatus: .healthy, currentStatus: .warning)

        // Verify alert was attempted
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(1)
    }

    @Test
    func `requestPermission delegates to alert sender`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).requestPermission().willReturn(true)
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When
        let result = await alerter.requestPermission()

        // Then
        #expect(result == true)
        verify(mockSender).requestPermission().called(1)
    }
}
