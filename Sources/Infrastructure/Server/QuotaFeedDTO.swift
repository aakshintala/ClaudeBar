import Foundation
import Domain

// MARK: - Wire Types

public struct QuotaFeedDTO: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let providers: [QuotaFeedProviderDTO]
    public let disabledProviderIds: [String]

    public init(generatedAt: Date, providers: [QuotaFeedProviderDTO], disabledProviderIds: [String]) {
        self.generatedAt = generatedAt
        self.providers = providers
        self.disabledProviderIds = disabledProviderIds
    }
}

public struct QuotaFeedProviderDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let tier: String?
    public let capturedAt: Date?
    public let ageSeconds: Int?
    public let status: String
    public let unavailable: String?
    public let throttledUntil: Date?
    public let quotas: [QuotaFeedQuotaDTO]

    public init(
        id: String,
        name: String,
        tier: String?,
        capturedAt: Date?,
        ageSeconds: Int?,
        status: String,
        unavailable: String?,
        throttledUntil: Date?,
        quotas: [QuotaFeedQuotaDTO]
    ) {
        self.id = id
        self.name = name
        self.tier = tier
        self.capturedAt = capturedAt
        self.ageSeconds = ageSeconds
        self.status = status
        self.unavailable = unavailable
        self.throttledUntil = throttledUntil
        self.quotas = quotas
    }
}

public struct QuotaFeedQuotaDTO: Codable, Sendable, Equatable {
    public let key: String
    public let label: String
    public let percentRemaining: Double
    public let resetsAt: Date?
    public let resetText: String?
    public let status: String

    public init(
        key: String,
        label: String,
        percentRemaining: Double,
        resetsAt: Date?,
        resetText: String?,
        status: String
    ) {
        self.key = key
        self.label = label
        self.percentRemaining = percentRemaining
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.status = status
    }
}

// MARK: - Mapping

public enum QuotaFeedDTOMapper {
    @MainActor
    public static func make(from providers: [any AIProvider], at now: Date) -> QuotaFeedDTO {
        var enabled: [QuotaFeedProviderDTO] = []
        var disabledIds: [String] = []

        for provider in providers {
            if provider.isEnabled {
                enabled.append(mapProvider(provider, at: now))
            } else {
                disabledIds.append(provider.id)
            }
        }

        return QuotaFeedDTO(
            generatedAt: now,
            providers: enabled,
            disabledProviderIds: disabledIds
        )
    }

    @MainActor
    private static func mapProvider(_ provider: any AIProvider, at now: Date) -> QuotaFeedProviderDTO {
        let snapshot = provider.snapshot
        let capturedAt = snapshot?.capturedAt
        let ageSeconds = capturedAt.map { Int(now.timeIntervalSince($0)) }

        let rateLimit = rateLimitState(from: provider.lastError)
        let unavailable: String?
        let throttledUntil: Date?
        if let rateLimit {
            unavailable = nil
            throttledUntil = rateLimit
        } else if let error = provider.lastError {
            unavailable = error.localizedDescription
            throttledUntil = nil
        } else {
            unavailable = nil
            throttledUntil = nil
        }

        let quotas = snapshot?.quotas.map(mapQuota) ?? []
        let status = snapshot?.overallStatus.feedKey ?? "healthy"

        return QuotaFeedProviderDTO(
            id: provider.id,
            name: provider.name,
            tier: snapshot?.accountTier.map(feedTierName),
            capturedAt: capturedAt,
            ageSeconds: ageSeconds,
            status: status,
            unavailable: unavailable,
            throttledUntil: throttledUntil,
            quotas: quotas
        )
    }

    private static func mapQuota(_ quota: UsageQuota) -> QuotaFeedQuotaDTO {
        QuotaFeedQuotaDTO(
            key: quota.quotaType.quotaKey,
            label: quota.quotaType.displayName,
            percentRemaining: quota.percentRemaining,
            resetsAt: quota.resetsAt,
            resetText: quota.resetText,
            status: quota.status.feedKey
        )
    }

    private static func rateLimitState(from error: Error?) -> Date? {
        guard let error else { return nil }
        if case ProbeError.rateLimited(let retryAt) = error {
            return retryAt
        }
        return nil
    }

    private static func feedTierName(_ tier: AccountTier) -> String {
        switch tier {
        case .custom(let badge):
            return badge
        case .claudeMax, .claudePro, .claudeApi:
            let badge = tier.badgeText
            return badge.prefix(1).uppercased() + badge.dropFirst().lowercased()
        }
    }
}

public extension QuotaFeedDTO {
    @MainActor
    static func make(from providers: [any AIProvider], at now: Date) -> QuotaFeedDTO {
        QuotaFeedDTOMapper.make(from: providers, at: now)
    }
}

private extension QuotaStatus {
    var feedKey: String {
        switch self {
        case .healthy: "healthy"
        case .warning: "warning"
        case .critical: "critical"
        case .depleted: "depleted"
        }
    }
}
