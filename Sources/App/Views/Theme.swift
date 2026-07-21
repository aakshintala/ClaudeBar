import SwiftUI
import Domain

// MARK: - Theme Mode

/// The active theme mode for the application
enum ThemeMode: String, CaseIterable {
    case light
    case dark

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
}

// MARK: - BudgetStatus Theme Extension

extension BudgetStatus {
    /// Maps BudgetStatus to QuotaStatus for theme color lookup
    var toQuotaStatus: QuotaStatus {
        switch self {
        case .withinBudget: .healthy
        case .approachingLimit: .warning
        case .overBudget: .critical
        }
    }
}
