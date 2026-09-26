import SwiftUI

// MARK: - Theme Environment Key

/// Environment key for injecting the active theme into the view hierarchy.
private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.dark
}

extension EnvironmentValues {
    /// The active theme for the current view hierarchy.
    ///
    /// ## Usage
    /// ```swift
    /// struct MyView: View {
    ///     @Environment(\.appTheme) var theme
    ///
    ///     var body: some View {
    ///         Text("Hello")
    ///             .foregroundStyle(theme.textPrimary)
    ///     }
    /// }
    /// ```
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Theme Provider Modifier

/// View modifier that resolves `themeModeId` to a concrete `AppTheme` and provides it to the view hierarchy.
///
/// ## Usage
/// ```swift
/// ContentView()
///     .appThemeProvider(themeModeId: settings.themeMode)
/// ```
struct AppThemeProviderModifier: ViewModifier {
    let themeModeId: String

    private var isLight: Bool { ThemeMode(rawValue: themeModeId) == .light }

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, isLight ? .light : .dark)
            .environment(\.colorScheme, isLight ? .light : .dark)
    }
}

extension View {
    /// Applies the theme provider modifier to inject the active theme.
    /// - Parameter themeModeId: The theme mode ID from AppSettings
    /// - Returns: A view with the theme environment set
    func appThemeProvider(themeModeId: String) -> some View {
        modifier(AppThemeProviderModifier(themeModeId: themeModeId))
    }
}
