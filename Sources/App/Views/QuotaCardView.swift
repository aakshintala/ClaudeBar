import SwiftUI
import Domain

/// A card view displaying a single quota metric.
/// Directly uses the rich domain model - no ViewModel needed.
struct QuotaCardView: View {
    let quota: UsageQuota

    @State private var settings = AppSettings.shared

    /// Status considering burn rate setting
    private var effectiveStatus: QuotaStatus {
        if settings.burnRateWarningEnabled {
            return quota.paceAwareStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return quota.status
    }

    /// Display color for dollar-based quotas based on dollar thresholds.
    private var dollarDisplayColor: Color {
        guard let amount = quota.dollarRemaining else { return effectiveStatus.displayColor }
        let value = NSDecimalNumber(decimal: amount).doubleValue
        if value <= 5 { return .red }
        if value <= 20 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            Text(quota.quotaType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Value display
            if let dollarText = quota.formattedDollarRemaining {
                Text("\(dollarText) remaining")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(dollarDisplayColor)
            } else {
                Text("\(Int(quota.percentRemaining.rounded()))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(effectiveStatus.displayColor)
            }

            // Progress bar
            GeometryReader { geometry in
                let progressPercent = quota.percentRemaining
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 4)

                    // Fill (clamp width to 0-100%)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(effectiveStatus.displayColor)
                        .frame(width: geometry.size.width * max(0, min(100, progressPercent)) / 100, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}
