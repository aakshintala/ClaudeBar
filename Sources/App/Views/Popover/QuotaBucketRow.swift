import SwiftUI
import Domain

/// Single quota bucket row: name, colored percentage, reset time.
struct QuotaBucketRow: View {
    let quota: UsageQuota
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(quota.quotaType.displayName)
                .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 8)

            Text(percentageText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.statusColor(for: quota.status))

            Text(resetText)
                .font(.system(size: 12, weight: .regular, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
    }

    private var percentageText: String {
        "\(Int(quota.percentRemaining.rounded()))%"
    }

    private var resetText: String {
        quota.compactResetTime ?? "—"
    }
}
