import SwiftUI
import Domain
import Infrastructure

/// Inline settings content view that fits within the menu bar popup.
struct SettingsContentView: View {
    @Binding var showSettings: Bool
    let monitor: QuotaMonitor
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    @State private var providersExpanded: Bool = false
    @State private var backgroundSyncExpanded: Bool = false

    private enum ProviderID {
        static let claude = "claude"
        static let codex = "codex"
    }

    private var isClaudeEnabled: Bool {
        monitor.provider(for: ProviderID.claude)?.isEnabled ?? false
    }

    private var isCodexEnabled: Bool {
        monitor.provider(for: ProviderID.codex)?.isEnabled ?? false
    }

    /// Maximum height for the settings view to ensure it fits on small screens
    private var maxSettingsHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return min(screenHeight * 0.8, 550)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    themeCard
                    providersCard
                    if isClaudeEnabled {
                        ClaudeConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isCodexEnabled {
                        CodexConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    backgroundSyncCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxHeight: maxSettingsHeight)
    }

    // MARK: - Theme Card

    /// Convert ThemeMode to string for settings storage
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .dark
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: currentThemeMode.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("Choose your theme")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }

            // Theme options grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(ThemeRegistry.shared.allThemes, id: \.id) { registeredTheme in
                    ThemeOptionButton(
                        themeProvider: registeredTheme,
                        isSelected: settings.themeMode == registeredTheme.id
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.themeMode = registeredTheme.id
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Providers Card

    private var providersCard: some View {
        DisclosureGroup(isExpanded: $providersExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            // Provider toggles
            VStack(spacing: 8) {
                ForEach(monitor.allProviders, id: \.id) { provider in
                    providerToggleRow(provider: provider)
                }
            }
        } label: {
            providersHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        providersExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    private var providersHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Providers")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Enable or disable AI providers")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private func providerToggleRow(provider: any AIProvider) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                // Provider icon
                ProviderIconView(providerId: provider.id, size: 20)

                Text(provider.name)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.setProviderEnabled(provider.id, enabled: newValue)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Back button
            Button {
                showSettings = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Back")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(theme.glassBackground)
                        .overlay(
                            Capsule()
                                .stroke(theme.glassBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Settings")
                .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            // Invisible placeholder to balance the header
            Color.clear
                .frame(width: 60, height: 1)
        }
    }

    // MARK: - Background Sync Card

    private var backgroundSyncCard: some View {
        DisclosureGroup(isExpanded: $backgroundSyncExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REFRESH INTERVAL")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text("Keep the menu-bar number fresh in the background. \"Off\" updates only when you open the menu. Never refreshes faster than once a minute.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        } label: {
            backgroundSyncHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        backgroundSyncExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    private var backgroundSyncHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.6, blue: 0.9),
                                Color(red: 0.2, green: 0.45, blue: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Background Sync")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Keep data fresh automatically")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // The on/off control now lives in the picker's "Off" case; show the
            // current cadence here so it's visible while the card is collapsed.
            Text(settings.refreshInterval.label)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings = false
                }
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(theme.accentGradient)
                            .shadow(color: theme.accentSecondary.opacity(0.25), radius: 6, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Theme Option Button

struct ThemeOptionButton: View {
    let themeProvider: any AppThemeProvider
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(themeProvider.accentGradient)
                        .frame(width: 28, height: 28)

                    Image(systemName: themeProvider.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(themeProvider.displayName)
                        .font(.system(size: 11, weight: .medium, design: themeProvider.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    if let subtitle = themeProvider.subtitle {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(themeProvider.accentPrimary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.statusHealthy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: themeProvider.cardCornerRadius)
                    .fill(isSelected ? theme.accentPrimary.opacity(0.15) : (isHovering ? theme.hoverOverlay : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: themeProvider.cardCornerRadius)
                            .stroke(isSelected ? theme.accentPrimary : theme.glassBorder.opacity(0.5), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Preview

#Preview("Settings - Dark") {
    ZStack {
        DarkTheme().backgroundGradient
        SettingsContentView(showSettings: .constant(true), monitor: QuotaMonitor(providers: AIProviders(providers: [])))
    }
    .appThemeProvider(themeModeId: "dark")
    .frame(width: 380, height: 420)
}

#Preview("Settings - Light") {
    ZStack {
        LightTheme().backgroundGradient
        SettingsContentView(showSettings: .constant(true), monitor: QuotaMonitor(providers: AIProviders(providers: [])))
    }
    .appThemeProvider(themeModeId: "light")
    .frame(width: 380, height: 420)
}
