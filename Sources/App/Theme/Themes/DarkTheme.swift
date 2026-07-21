import SwiftUI

/// Pure-black dark theme (Phase 3 mockup palette).
public struct DarkTheme: AppThemeProvider {
    public let id = "dark"
    public let displayName = "Dark"
    public let icon = "moon.stars.fill"

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom)
    }

    public var showBackgroundOrbs: Bool { false }

    public var cardGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var glassBackground: Color { Color.white.opacity(0.04) }
    public var glassBorder: Color { Color.white.opacity(0.10) }
    public var glassHighlight: Color { Color.white.opacity(0.14) }

    public var cardCornerRadius: CGFloat { 10 }
    public var pillCornerRadius: CGFloat { 8 }

    public var textPrimary: Color { Color(red: 0xE8/255, green: 0xE8/255, blue: 0xE8/255) }
    public var textSecondary: Color { Color(red: 0x88/255, green: 0x88/255, blue: 0x88/255) }
    public var textTertiary: Color { Color(red: 0x66/255, green: 0x66/255, blue: 0x66/255) }

    public var fontDesign: Font.Design { .default }

    public var statusHealthy: Color { Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255) }
    public var statusWarning: Color { Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255) }
    public var statusCritical: Color { Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255) }
    public var statusDepleted: Color { Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255) }

    public var accentPrimary: Color { textPrimary }
    public var accentSecondary: Color { textSecondary }

    public var accentGradient: LinearGradient {
        LinearGradient(colors: [textPrimary, textSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var pillGradient: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var shareGradient: LinearGradient {
        accentGradient
    }

    public var hoverOverlay: Color { Color.white.opacity(0.06) }
    public var pressedOverlay: Color { Color.white.opacity(0.10) }
    public var progressTrack: Color { Color.white.opacity(0.12) }

    public init() {}
}
