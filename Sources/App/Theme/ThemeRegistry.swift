import SwiftUI

// MARK: - Theme Registry

/// Manages available themes in the application.
/// Follows the same pattern as `AIProviders` for provider registration.
///
/// ## Usage
/// ```swift
/// // Get a theme by ID
/// let theme = ThemeRegistry.shared.theme(for: "dark")
///
/// // Register a custom theme
/// ThemeRegistry.shared.register(MyCustomTheme())
///
/// // Get all available themes
/// let allThemes = ThemeRegistry.shared.allThemes
/// ```
@MainActor
public final class ThemeRegistry {
    /// Shared singleton instance
    public static let shared = ThemeRegistry()

    /// Registered themes keyed by ID
    private var themes: [String: any AppThemeProvider] = [:]

    /// Order of theme IDs for consistent display
    private var themeOrder: [String] = []

    /// Initialize with built-in themes
    private init() {
        registerBuiltInThemes()
    }

    /// Register all built-in themes
    private func registerBuiltInThemes() {
        register(LightTheme())
        register(DarkTheme())
    }

    // MARK: - Public API

    /// Register a theme. If a theme with the same ID exists, it will be replaced.
    /// - Parameter theme: The theme to register
    public func register(_ theme: any AppThemeProvider) {
        let isNew = themes[theme.id] == nil
        themes[theme.id] = theme
        if isNew {
            themeOrder.append(theme.id)
        }
    }

    /// Get a theme by its ID
    /// - Parameter id: The theme ID
    /// - Returns: The theme if found, nil otherwise
    public func theme(for id: String) -> (any AppThemeProvider)? {
        themes[id]
    }

    /// All registered themes in registration order
    public var allThemes: [any AppThemeProvider] {
        themeOrder.compactMap { themes[$0] }
    }

    /// All theme IDs in registration order
    public var allThemeIds: [String] {
        themeOrder
    }

    /// The default theme (Dark)
    public var defaultTheme: any AppThemeProvider {
        themes["dark"] ?? DarkTheme()
    }

    /// Resolve a theme ID to a concrete theme
    /// - Parameters:
    ///   - id: The theme ID
    ///   - systemColorScheme: Unused; kept for call-site compatibility
    /// - Returns: The resolved theme (unknown ids fall back to Dark)
    public func resolveTheme(for id: String, systemColorScheme: ColorScheme) -> any AppThemeProvider {
        _ = systemColorScheme
        return themes[id] ?? defaultTheme
    }
}
