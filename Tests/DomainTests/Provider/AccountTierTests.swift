import Testing
@testable import Domain

@Suite("AccountTier Tests")
struct AccountTierTests {

    // MARK: - Badge Text Tests

    @Test(arguments: [
        (AccountTier.claudeMax, "MAX"),
        (.claudePro, "PRO"),
        (.claudeApi, "API"),
        (.custom("ULTRA"), "ULTRA"),
    ])
    func `account tier has correct badge text`(tier: AccountTier, expected: String) {
        #expect(tier.badgeText == expected)
    }

    // MARK: - Equality Tests

    @Test
    func `account tiers are equal when same`() {
        #expect(AccountTier.claudeMax == AccountTier.claudeMax)
        #expect(AccountTier.claudePro == AccountTier.claudePro)
        #expect(AccountTier.claudeApi == AccountTier.claudeApi)
        #expect(AccountTier.custom("PRO") == AccountTier.custom("PRO"))
    }

    @Test
    func `account tiers are not equal when different`() {
        #expect(AccountTier.claudeMax != AccountTier.claudePro)
        #expect(AccountTier.claudeMax != AccountTier.claudeApi)
        #expect(AccountTier.claudePro != AccountTier.claudeApi)
        #expect(AccountTier.custom("PRO") != AccountTier.custom("ULTRA"))
    }

    @Test
    func `custom tier is not equal to Claude tier with same badge`() {
        // .custom("PRO") is NOT the same as .claudePro even though badge text is "PRO"
        #expect(AccountTier.custom("PRO") != AccountTier.claudePro)
    }
}
