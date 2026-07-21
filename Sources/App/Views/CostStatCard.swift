import SwiftUI
import Domain

/// Compact cost row aligned with popover quota bucket list styling.
struct CostStatCard: View {
    let costUsage: CostUsage
    let delay: Double

    @Environment(\.appTheme) private var theme

    init(costUsage: CostUsage, delay: Double = 0) {
        self.costUsage = costUsage
        self.delay = delay
    }

    private var effectiveBudget: Decimal? {
        costUsage.budget
    }

    private var headerTitle: String {
        switch costUsage.kind {
        case .apiCost:
            "API Cost"
        case .extraUsage:
            "Extra Usage"
        }
    }

    private var budgetStatus: BudgetStatus? {
        guard let budget = effectiveBudget, budget > 0 else { return nil }
        return costUsage.budgetStatus(budget: budget)
    }

    private var statusColor: Color {
        guard let status = budgetStatus else { return theme.textPrimary }
        return theme.statusColor(for: status.toQuotaStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)

                Spacer(minLength: 8)

                Text(costUsage.formattedCost)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)

                Text(trailingDetail)
                    .font(.system(size: 12, weight: .regular, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .frame(minWidth: 36, alignment: .trailing)
            }

            if let budget = effectiveBudget, budget > 0 {
                Text("of \(formatBudget(budget))")
                    .font(.system(size: 11, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            } else if costUsage.kind == .extraUsage {
                Text("No monthly cap")
                    .font(.system(size: 11, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            if costUsage.apiDuration > 0 {
                Text("API time: \(costUsage.formattedApiDuration)")
                    .font(.system(size: 11, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
    }

    private var trailingDetail: String {
        if let resetText = costUsage.resetText {
            return resetText
        }
        if let budget = effectiveBudget, budget > 0, let status = budgetStatus {
            return status.badgeText
        }
        return "—"
    }

    private func formatBudget(_ budget: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: budget as NSDecimalNumber) ?? "$\(budget)"
    }
}

// MARK: - Preview

#Preview("Extra Usage - Capped Partial") {
    ZStack {
        DarkTheme().backgroundGradient

        CostStatCard(
            costUsage: CostUsage(
                totalCost: 5.41,
                budget: 20,
                apiDuration: 0,
                providerId: "claude",
                kind: .extraUsage,
                resetText: "Resets Jan 1, 2026"
            )
        )
        .padding()
    }
    .frame(width: 360, height: 120)
    .preferredColorScheme(.dark)
}

#Preview("API Cost") {
    ZStack {
        DarkTheme().backgroundGradient

        CostStatCard(
            costUsage: CostUsage(
                totalCost: 0.55,
                budget: 10,
                apiDuration: 379.7,
                providerId: "claude"
            )
        )
        .padding()
    }
    .frame(width: 360, height: 120)
    .preferredColorScheme(.dark)
}
