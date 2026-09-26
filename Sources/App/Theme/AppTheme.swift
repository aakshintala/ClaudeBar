import SwiftUI
import Domain

/// A concrete theme. Two fixed instances (`dark`, `light`) are picked by `ThemeMode`.
struct AppTheme {
    let id: String
    let displayName: String
    let icon: String

    let backgroundGradient: LinearGradient
    let cardGradient: LinearGradient
    let glassBackground: Color
    let glassBorder: Color
    let cardCornerRadius: CGFloat

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let fontDesign: Font.Design

    let statusHealthy: Color
    let statusWarning: Color
    let statusCritical: Color
    let statusDepleted: Color

    let accentPrimary: Color
    let accentSecondary: Color
    let accentGradient: LinearGradient

    let hoverOverlay: Color

    /// Maps a quota status to its theme color.
    func statusColor(for status: QuotaStatus) -> Color {
        switch status {
        case .healthy: statusHealthy
        case .warning: statusWarning
        case .critical: statusCritical
        case .depleted: statusDepleted
        }
    }
}

extension AppTheme {
    /// Pure-black dark theme.
    static let dark: AppTheme = {
        let primary = Color(red: 0xE8 / 255, green: 0xE8 / 255, blue: 0xE8 / 255)
        let secondary = Color(red: 0x88 / 255, green: 0x88 / 255, blue: 0x88 / 255)
        return AppTheme(
            id: "dark",
            displayName: "Dark",
            icon: "moon.stars.fill",
            backgroundGradient: LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom),
            cardGradient: LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            glassBackground: Color.white.opacity(0.04),
            glassBorder: Color.white.opacity(0.10),
            cardCornerRadius: 10,
            textPrimary: primary,
            textSecondary: secondary,
            textTertiary: Color(red: 0x66 / 255, green: 0x66 / 255, blue: 0x66 / 255),
            fontDesign: .default,
            statusHealthy: Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255),
            statusWarning: Color(red: 0xEA / 255, green: 0xB3 / 255, blue: 0x08 / 255),
            statusCritical: Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255),
            statusDepleted: Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255),
            accentPrimary: primary,
            accentSecondary: secondary,
            accentGradient: LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing),
            hoverOverlay: Color.white.opacity(0.06)
        )
    }()

    /// Light theme with soft purple-pink tones.
    static let light = AppTheme(
        id: "light",
        displayName: "Light",
        icon: "sun.max.fill",
        backgroundGradient: LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.96, blue: 1.0),
                Color(red: 0.96, green: 0.94, blue: 0.99),
                Color(red: 0.94, green: 0.92, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        cardGradient: LinearGradient(
            colors: [Color.white.opacity(0.95), Color.white.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        glassBackground: Color.white.opacity(0.8),
        glassBorder: BaseTheme.purpleVibrant.opacity(0.15),
        cardCornerRadius: 14,
        textPrimary: Color(red: 0.15, green: 0.12, blue: 0.22),
        textSecondary: Color(red: 0.35, green: 0.32, blue: 0.42),
        textTertiary: Color(red: 0.55, green: 0.52, blue: 0.62),
        fontDesign: .rounded,
        statusHealthy: Color(red: 0.22, green: 0.78, blue: 0.55),
        statusWarning: Color(red: 0.92, green: 0.62, blue: 0.22),
        statusCritical: Color(red: 0.92, green: 0.32, blue: 0.42),
        statusDepleted: Color(red: 0.72, green: 0.18, blue: 0.28),
        accentPrimary: Color(red: 0.72, green: 0.25, blue: 0.55),
        accentSecondary: Color(red: 0.45, green: 0.22, blue: 0.75),
        accentGradient: LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.45, blue: 0.38),
                Color(red: 0.78, green: 0.28, blue: 0.58)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        hoverOverlay: BaseTheme.purpleDeep.opacity(0.08)
    )

    /// Both themes, in display order (settings picker).
    static let all: [AppTheme] = [light, dark]
}

// MARK: - Brand Colors

/// Shared brand colors used by the theme and by provider visual identity.
enum BaseTheme {
    static let coralAccent = Color(red: 0.98, green: 0.55, blue: 0.45)
    static let tealBright = Color(red: 0.35, green: 0.85, blue: 0.78)
    static let purpleDeep = Color(red: 0.38, green: 0.22, blue: 0.72)
    static let purpleVibrant = Color(red: 0.55, green: 0.32, blue: 0.85)
    static let pinkHot = Color(red: 0.85, green: 0.35, blue: 0.65)
}
