import SwiftUI
import Domain
import Infrastructure

/// The main menu content view with adaptive theme support via AppThemeProvider.
/// Uses the pluggable theme system for consistent styling across all themes.
struct MenuContentView: View {
    let monitor: QuotaMonitor
    let quotaAlerter: QuotaAlerter

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveringRefresh = false
    @State private var animateIn = false
    @State private var showSettings = false
    @State private var settings = AppSettings.shared
    @State private var hasRequestedNotificationPermission = false

    /// The currently selected provider ID (from monitor, which is @Observable)
    private var selectedProviderId: String {
        get { monitor.selectedProviderId }
        nonmutating set { monitor.selectedProviderId = newValue }
    }

    /// The currently selected provider
    private var selectedProvider: (any AIProvider)? {
        monitor.selectedProvider
    }

    var body: some View {
        ZStack {
            // Gradient background from theme
            theme.backgroundGradient
                .ignoresSafeArea()

            // Background orbs (if theme supports them)
            if theme.showBackgroundOrbs {
                backgroundOrbs
            }

            // Theme overlay (e.g., optional effects)
            theme.overlayView

            if showSettings {
                // Settings View
                SettingsContentView(showSettings: $showSettings, monitor: monitor)
            } else {
                // Main Content
                VStack(spacing: 0) {
                    // Header with branding
                    headerView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    // Provider Pills (hidden in overview mode)
                    if !settings.overviewModeEnabled {
                        providerPills
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // Main Content Area — hugs its content, but caps at the
                    // screen height and scrolls beyond it (aggregating
                    // providers can show a dozen cards; the action bar must
                    // never be pushed off-screen).
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 12) {
                            metricsContent
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .frame(maxHeight: contentMaxHeight)
                    // Recreate the scroll view when the shown content
                    // changes, so a newly selected provider starts at the
                    // top instead of inheriting the previous scroll offset.
                    .id(settings.overviewModeEnabled ? "overview" : monitor.selectedProviderId)

                    // Bottom Action Bar
                    actionBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            // Request alert permission once (after app run loop is active)
            if !hasRequestedNotificationPermission {
                hasRequestedNotificationPermission = true
                let granted = await quotaAlerter.requestPermission()
                AppLog.notifications.info("Alert permission request result: \(granted ? "granted" : "denied")")
            }

            // Show header and tabs immediately
            withAnimation(.easeOut(duration: 0.6)) {
                animateIn = true
            }
            // Then fetch data in background
            if settings.overviewModeEnabled {
                await refreshAllEnabled()
            } else {
                await refresh(providerId: selectedProviderId)
            }

        }
        .onChange(of: selectedProviderId) { _, newProviderId in
            // Refresh immediately when the user switches provider while the
            // dropdown is open. Periodic background refresh is owned by the
            // app-lifetime loop in ClaudeBarApp, which restarts itself when the
            // selected or menu-bar provider changes.
            Task {
                await refresh(providerId: newProviderId)
            }
        }
    }

    private var contentMaxHeight: CGFloat { 500 }

    // MARK: - Background Orbs

    private var backgroundOrbs: some View {
        GeometryReader { geo in
            ZStack {
                // Large purple orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.purpleVibrant.opacity(colorScheme == .dark ? 0.4 : 0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .offset(x: -60, y: -80)
                    .blur(radius: 40)

                // Pink orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.pinkHot.opacity(colorScheme == .dark ? 0.35 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .offset(x: geo.size.width - 80, y: geo.size.height - 150)
                    .blur(radius: 30)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Custom Provider Icon - shows AppLogo in overview mode, provider icon otherwise
            // Avoid animation on provider icon to prevent constraint update loops in MenuBarExtra
            ZStack {
                if settings.overviewModeEnabled, let logo = NSImage(named: "AppLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(theme.accentPrimary.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: theme.accentPrimary.opacity(0.15), radius: 3, y: 1)
                } else {
                    ProviderIconView(providerId: selectedProviderId, size: 38)
                }

            }

            VStack(alignment: .leading, spacing: 2) {
                Text("ClaudeBar")
                    .font(.system(size: 18, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            // Status Badge
            statusBadge
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -10)
    }

    private var headerSubtitle: String {
        "AI Usage Monitor"
    }

    /// Status of the currently selected provider
    private var selectedProviderStatus: QuotaStatus {
        guard let snapshot = selectedProvider?.snapshot else { return .healthy }
        if settings.burnRateWarningEnabled {
            return snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return snapshot.overallStatus
    }

    /// Whether the selected provider is currently syncing
    private var isSelectedProviderSyncing: Bool {
        selectedProvider?.isSyncing ?? false
    }

    private var statusBadge: some View {
        let statusColor = theme.statusColor(for: selectedProviderStatus)

        return HStack(spacing: 6) {
            // Animated pulse dot
            PulsingStatusDot(
                color: statusColor,
                isSyncing: isSelectedProviderSyncing
            )

            Text(statusText)
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                .fill(theme.glassBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(statusColor.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var statusText: String {
        if isSelectedProviderSyncing { return "Syncing..." }
        return selectedProviderStatus.badgeText
    }

    /// Help text for settings button
    private var updateAvailableHelpText: String {
        "Settings"
    }

    // MARK: - Provider Pills

    /// Only show enabled providers in the pills
    private var enabledProviders: [any AIProvider] {
        monitor.enabledProviders
    }

    private var providerPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(enabledProviders, id: \.id) { provider in
                    ProviderPill(
                        providerId: provider.id,
                        providerName: provider.name,
                        isSelected: provider.id == selectedProviderId,
                        hasData: provider.snapshot != nil
                    ) {
                        // Avoid withAnimation to prevent constraint update loops in MenuBarExtra
                        selectedProviderId = provider.id
                    }
                }
            }
            .background(HorizontalScrollBooster())
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateIn)
    }

    // MARK: - Metrics Content

    @ViewBuilder
    private var metricsContent: some View {
        if settings.overviewModeEnabled {
            let providers = monitor.enabledProviders
            if providers.isEmpty {
                emptyState
            } else {
                overviewContent(providers: providers)
            }
        } else if let provider = selectedProvider, let snapshot = provider.snapshot {
            VStack(spacing: 12) {
                if let displayName = snapshot.accountEmail ?? snapshot.accountOrganization {
                    accountCard(displayName: displayName, snapshot: snapshot)
                }
                statsGrid(snapshot: snapshot)
            }
            .opacity(animateIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if selectedProvider?.isSyncing == true {
            loadingState
        } else {
            emptyState
        }
    }

    private func overviewContent(providers: [any AIProvider]) -> some View {
        // Scrolling is owned by the shared middle-region ScrollView in
        // `body`; nesting another vertical ScrollView here would break
        // height negotiation and swallow gestures.
        VStack(spacing: 12) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    Divider()
                        .background(theme.glassBorder)
                }
                providerSection(provider: provider)
            }
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
    }

    private func providerSection(provider: any AIProvider) -> some View {
        VStack(spacing: 8) {
            providerSectionHeader(provider: provider)

            if let snapshot = provider.snapshot {
                statsGrid(snapshot: snapshot)
            } else if provider.isSyncing {
                LoadingSpinnerView()
            } else {
                compactErrorState(provider: provider)
            }
        }
    }

    private func providerSectionHeader(provider: any AIProvider) -> some View {
        HStack(spacing: 8) {
            ProviderIconView(providerId: provider.id, size: 20, showGlow: false)

            Text(provider.name)
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            let status = provider.snapshot?.overallStatus ?? .healthy
            Text(provider.isSyncing ? "Syncing..." : status.badgeText)
                .badge(theme.statusColor(for: status))
        }
        .padding(.horizontal, 4)
    }

    private func compactErrorState(provider: any AIProvider) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.statusWarning)

            Text(provider.lastError?.localizedDescription ?? "Unavailable")
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
    }


    private func accountCard(displayName: String, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(ProviderVisualIdentityLookup.gradient(for: selectedProviderId, scheme: colorScheme))
                    .frame(width: 32, height: 32)

                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    // Account tier badge
                    if let accountTier = snapshot.accountTier {
                        Text(accountTier.badgeText)
                            .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(theme.accentPrimary.opacity(0.8))
                            )
                    }
                }

                Text("Updated \(snapshot.ageDescription)")
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // Stale indicator
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.statusWarning)
            }
        }
        .glassCard(cornerRadius: 12, padding: 10)
    }

    /// Collapsed state of quota-group sections, keyed by `QuotaGroup.id`.
    /// Ephemeral by design: reopening the popover starts fully expanded.
    @State private var collapsedQuotaGroups: Set<String> = []

    /// Sections for aggregating providers (e.g. Oh My Pi): one collapsible
    /// block per upstream account, so ten flat cards become scannable.
    @ViewBuilder
    private func quotaGroupSections(snapshot: UsageSnapshot) -> some View {
        let groups = snapshot.quotaGroups
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                let baseDelay = Double(groups.prefix(groupIndex).reduce(0) { $0 + $1.quotas.count }) * 0.08
                quotaGroupSection(group, baseDelay: baseDelay)
            }
        }
    }

    private func quotaGroupSection(_ group: QuotaGroup, baseDelay: Double) -> some View {
        // Note-only sections (accounts without usable quota data) have no
        // cards to collapse; the note renders inline in the header.
        let isNoteOnly = group.quotas.isEmpty
        let isCollapsed = !isNoteOnly && collapsedQuotaGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    collapsedQuotaGroups = isCollapsed
                        ? collapsedQuotaGroups.subtracting([group.id])
                        : collapsedQuotaGroups.union([group.id])
                }
            } label: {
                HStack(spacing: 6) {
                    if !isNoteOnly {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                    }

                    Text((group.title ?? "Other").uppercased())
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer(minLength: 4)

                    if case .headerInline(let note) = group.notePlacement {
                        Text(note)
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    } else if isNoteOnly {
                        Text("No usage data")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        // Collapsed sections keep their headline number visible.
                        if isCollapsed, let lowest = group.lowestQuota {
                            Text("\(Int(lowest.percentRemaining))% left")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                                .foregroundStyle(theme.textTertiary)
                        }

                        Text(group.worstStatus.badgeText)
                            .badge(theme.statusColor(for: group.worstStatus))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isNoteOnly)

            if !isNoteOnly && !isCollapsed {
                // A note attached to a quota-bearing section (the same
                // account also reported "No usage" somewhere) is shown as
                // its own row - never silently dropped.
                if case .row(let note) = group.notePlacement {
                    Text(note)
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(group.quotas.enumerated()), id: \.element.quotaType) { index, quota in
                        WrappedStatCard(quota: quota, delay: baseDelay + Double(index) * 0.08)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statsGrid(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 10) {
            // Grouped sections cover aggregating providers even when every
            // account lacks quota data (note-only sections must still render).
            if snapshot.hasQuotaGroups {
                quotaGroupSections(snapshot: snapshot)
            } else if !snapshot.quotas.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(snapshot.quotas.enumerated()), id: \.element.quotaType) { index, quota in
                        WrappedStatCard(quota: quota, delay: Double(index) * 0.08)
                    }
                }
            }

            // Show Extra usage cost card if available (Pro with Extra usage enabled)
            if let costUsage = snapshot.costUsage {
                CostStatCard(costUsage: costUsage, delay: Double(snapshot.quotas.count) * 0.08)
            }
        }
        .padding(.top, 4)
    }

    private var loadingState: some View {
        LoadingSpinnerView()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.statusWarning.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.statusWarning)
            }

            Text("\(selectedProvider?.name ?? selectedProviderId) Unavailable")
                .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            // Show actual error message if available, otherwise generic message
            Text(selectedProvider?.lastError?.localizedDescription ?? "Install CLI or check configuration")
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            // Dashboard Button
            WrappedActionButton(
                icon: "safari.fill",
                label: "Dashboard",
                gradient: theme.accentGradient
            ) {
                if let url = selectedProvider?.dashboardURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("d")

            // Refresh Button
            let isCurrentlyRefreshing = settings.overviewModeEnabled
                ? monitor.enabledProviders.contains { $0.isSyncing }
                : selectedProvider?.isSyncing == true
            WrappedActionButton(
                icon: isCurrentlyRefreshing ? "arrow.trianglehead.2.counterclockwise.rotate.90" : "arrow.clockwise",
                label: isCurrentlyRefreshing ? "Syncing" : "Refresh",
                gradient: theme.accentGradient,
                isLoading: isCurrentlyRefreshing
            ) {
                if settings.overviewModeEnabled {
                    Task { await refreshAllEnabled() }
                } else {
                    Task { await refresh(providerId: selectedProviderId) }
                }
            }
            .keyboardShortcut("r")

            Spacer()

            // Settings Button with update indicator
            Button {
                // Avoid window resize animation glitches in MenuBarExtra.
                showSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .help(updateAvailableHelpText)
            .keyboardShortcut(",")

            // Quit Button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeBar")
            .keyboardShortcut("q")
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateIn)
    }

    // MARK: - Actions

    /// Refresh all enabled providers concurrently
    private func refreshAllEnabled() async {
        await withTaskGroup(of: Void.self) { group in
            // The `isSyncing` guard reads main-actor provider state, so evaluate
            // it here on the main actor (this closure inherits the caller's
            // isolation). Each child task then awaits `refresh()`, whose heavy
            // probe work still suspends off-main, keeping the refreshes concurrent.
            for provider in monitor.enabledProviders where !provider.isSyncing {
                group.addTask {
                    do {
                        try await provider.refresh()
                    } catch {
                        // Provider stores error in lastError
                    }
                }
            }
        }
    }

    /// Refresh a specific provider by ID
    private func refresh(providerId: String) async {
        guard let provider = monitor.provider(for: providerId) else {
            return
        }

        // Provider.isSyncing is observable - prevents duplicate refreshes
        guard !provider.isSyncing else { return }

        do {
            try await provider.refresh()
        } catch {
            // Provider stores error in lastError
        }
    }
}

// MARK: - Provider Pill

struct ProviderPill: View {
    let providerId: String
    let providerName: String
    let isSelected: Bool
    let hasData: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: providerIcon)
                    .font(.system(size: 10, weight: .semibold))

                Text(providerName)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? .white : theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                            .fill(theme.accentGradient)
                            .shadow(color: theme.accentPrimary.opacity(0.3), radius: 6, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                            .fill(isHovering ? theme.hoverOverlay : theme.glassBackground)
                    }

                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var providerIcon: String {
        ProviderVisualIdentityLookup.symbolIcon(for: providerId)
    }
}

// MARK: - Wrapped Stat Card

struct WrappedStatCard: View {
    let quota: UsageQuota
    let delay: Double

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false
    @State private var animateProgress = false
    @State private var settings = AppSettings.shared

    private var statusColor: Color {
        theme.statusColor(for: quota.status)
    }

    private var isCappedSpend: Bool {
        quota.dollarUsed != nil && quota.dollarCap != nil
    }

    private var valueCaption: String {
        if isCappedSpend { return "Spent" }
        if quota.isDollarBased { return "Remaining" }
        return "Remaining"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row with icon, type, and badge
            HStack(alignment: .top, spacing: 0) {
                // Left side: icon and type label
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(statusColor)

                    Text((quota.compactTitle ?? quota.quotaType.displayName).uppercased())
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.3)
                }

                Spacer(minLength: 4)

                // Status badge
                Text(quota.status.badgeText)
                    .badge(statusColor)
            }

            // Large value display with label (end-aligned)
            HStack(alignment: .firstTextBaseline) {
                if let dollarUsed = quota.formattedDollarUsed,
                   let dollarCap = quota.formattedDollarCap {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(dollarUsed)
                            .font(.system(size: 20, weight: .heavy, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                            .contentTransition(.numericText())

                        Text("of \(dollarCap)")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                } else if let dollarText = quota.formattedDollarRemaining {
                    Text(dollarText)
                        .font(.system(size: 18, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(quota.percentRemaining.rounded()))")
                            .font(.system(size: 32, weight: .bold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                            .contentTransition(.numericText())

                        Text("%")
                            .font(.system(size: 16, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                Text(valueCaption)
                    .font(.system(size: isCappedSpend ? 10 : 12, weight: .medium, design: theme.fontDesign))
                    .fixedSize()
                    .foregroundStyle(theme.textTertiary)
            }

            // Progress bar with gradient
            VStack(spacing: 1) {
                GeometryReader { geo in
                    let progressPercent = quota.percentRemaining
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressTrack)

                        // Fill (clamp width to 0-100%)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressGradient(for: quota.percentRemaining))
                            .frame(width: animateProgress ? geo.size.width * max(0, min(100, progressPercent)) / 100 : 0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay + 0.2), value: animateProgress)
                    }
                }
                .frame(height: 5)
            }

            // Reset info
            if let resetText = quota.resetTimestampDescription ?? quota.resetText ?? quota.resetDescription {
                HStack(spacing: 3) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 7))

                    Text(resetText)
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                }
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            animateProgress = true
        }
    }

    private var iconName: String {
        switch quota.quotaType {
        case .session: return "bolt.fill"
        case .weekly: return "calendar.badge.clock"
        case .modelSpecific: return "cpu.fill"
        case .timeLimit: return "clock.fill"
        }
    }
}

// MARK: - Loading Spinner View

struct LoadingSpinnerView: View {
    @Environment(\.appTheme) private var theme
    @State private var isSpinning = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(theme.textTertiary, lineWidth: 3)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        theme.accentGradient,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 1).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
            }

            Text("Fetching usage data...")
                .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .glassCard()
        .onAppear {
            isSpinning = true
        }
    }
}

// MARK: - Wrapped Action Button

struct WrappedActionButton: View {
    let icon: String
    let label: String
    let gradient: LinearGradient
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                        .tint(theme.textPrimary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(label)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .fixedSize()
            }
            .foregroundStyle(isHovering ? .white : theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(isHovering ? AnyShapeStyle(gradient) : AnyShapeStyle(theme.glassBackground))

                    Capsule()
                        .stroke(theme.glassBorder, lineWidth: 1)
                }
            )
            .shadow(color: isHovering ? theme.accentPrimary.opacity(0.3) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(isLoading)
    }
}

// MARK: - Visual Effect Blur (macOS) - Kept for compatibility

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Horizontal Scroll Booster

/// Converts vertical mouse wheel scroll events to horizontal scrolling.
/// Trackpads natively produce horizontal gestures, but mouse scroll wheels only
/// generate vertical deltas — this bridges the gap for horizontal ScrollViews.
///
/// Uses `NSEvent.addLocalMonitorForEvents` to intercept scroll events at the
/// app level before they reach the NSScrollView, which would otherwise ignore
/// vertical deltas in a horizontal-only scroll view.
struct HorizontalScrollBooster: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var monitor: Any?
        weak var view: NSView?

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let view = self.view,
                      let scrollView = view.enclosingScrollView else {
                    return event
                }

                // Only act on events over this scroll view
                let point = scrollView.convert(event.locationInWindow, from: nil)
                guard scrollView.bounds.contains(point) else {
                    return event
                }

                // Only convert predominantly vertical scrolls
                guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
                    return event
                }

                guard let cgEvent = event.cgEvent?.copy() else {
                    return event
                }

                // Swap vertical → horizontal
                cgEvent.setDoubleValueField(
                    .scrollWheelEventDeltaAxis2,
                    value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                )
                cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)

                cgEvent.setIntegerValueField(
                    .scrollWheelEventPointDeltaAxis2,
                    value: cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                )
                cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)

                return NSEvent(cgEvent: cgEvent) ?? event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

// MARK: - Gradient Stops Extension

extension LinearGradient {
    var stops: [Gradient.Stop] {
        // Default empty - used for animation color extraction
        []
    }
}

// MARK: - Pulsing Status Dot

/// A status dot that pulses when syncing, with proper animation lifecycle management.
struct PulsingStatusDot: View {
    let color: Color
    let isSyncing: Bool

    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Solid center dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            // Pulsing ring (only visible when syncing)
            if isSyncing {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .scaleEffect(1 + pulsePhase * 0.5)
                    .opacity(1 - pulsePhase)
            } else {
                // Static ring when not syncing
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .opacity(0.5)
            }
        }
        .onChange(of: isSyncing) { _, syncing in
            if syncing {
                startPulsing()
            } else {
                stopPulsing()
            }
        }
        .onAppear {
            if isSyncing {
                startPulsing()
            }
        }
    }

    private func startPulsing() {
        pulsePhase = 0
        withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
            pulsePhase = 1
        }
    }

    private func stopPulsing() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulsePhase = 0
        }
    }
}

// MARK: - Update Badge

/// A polished badge indicating an update is available
struct UpdateBadge: View {
    var accentColor: Color = BaseTheme.coralAccent

    private var badgeGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(badgeGradient)
                .frame(width: 18, height: 18)
                .blur(radius: 3)
                .opacity(0.5)

            // Main badge
            Circle()
                .fill(badgeGradient)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Arrow up icon
            Image(systemName: "arrow.up")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.white)
        }
    }
}
