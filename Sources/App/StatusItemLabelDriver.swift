import AppKit
import CoreText
import SwiftUI
import Domain
import Infrastructure

/// Drives the menu-bar status item imperatively (AppKit), bypassing SwiftUI's
/// `MenuBarExtra` label hosting entirely.
///
/// After system sleep, the MenuBarExtra label hosting view can permanently
/// stop receiving SwiftUI invalidations: the dropdown window keeps updating
/// while the label — and any `.task` attached to it — goes dead until relaunch
/// (issue #192). This driver owns both things that used to live on that label:
///
/// 1. **The pixels** — an `ObservationRenderSync` reads the same observable
///    state the SwiftUI label did (monitor, settings, session) and draws the
///    composed label into `statusItem.button.image`.
/// 2. **The background-refresh lifecycle** — a second sync watches the refresh
///    cadence/target settings and restarts `QuotaMonitor.startMonitoring`,
///    replacing the label's `.task(id:)`.
///
/// Lives for the app's lifetime; the closure retain cycles this creates are
/// intentional and harmless.
@MainActor
final class StatusItemLabelDriver {
    private let monitor: QuotaMonitor
    private let settings: AppSettings

    private var statusItem: NSStatusItem?
    private var labelSync: ObservationRenderSync<LabelContent>?
    private var loopSync: ObservationRenderSync<RefreshLoopKey>?
    private var streamConsumer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// The image currently owned by this driver, and the content it encodes.
    /// Used both to skip redundant redraws (repainting an intact image can
    /// itself flicker) and to recognize external wipes via KVO.
    private var lastImage: NSImage?
    private var lastContent: LabelContent?
    private var imageWipeObservation: NSKeyValueObservation?

    init(monitor: QuotaMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }

    // No deinit: this object lives for the app's lifetime, so the wake
    // observer is intentionally never removed (and a nonisolated deinit
    // could not touch the @MainActor-isolated observer under Swift 6).

    // MARK: - Label Rendering

    /// Everything the menu-bar pixels depend on. Reading these properties
    /// inside the sync's `read` registers observation for each of them.
    struct LabelContent: Equatable {
        var label: MenuBarLabel?
        var fallbackStatus: QuotaStatus
        var themeModeId: String
        /// Whether a dual-window label should render as two stacked smaller
        /// lines instead of one long "A | B" line (opt-in setting).
        var stacked: Bool = false
        /// The user-selected text size for the stacked lines. Carried in the
        /// content (not read at draw time) so changing the size in Settings
        /// invalidates the observation sync and repaints the label.
        var stackedSize: MenuBarStackedSize = .default
    }

    /// Attaches to the `NSStatusItem` exposed by MenuBarExtraAccess and starts
    /// rendering. Repeated callbacks re-assert the image (cheap, idempotent).
    func attach(_ statusItem: NSStatusItem) {
        guard self.statusItem !== statusItem else {
            labelSync?.renderNow()
            return
        }
        self.statusItem = statusItem
        labelSync?.stop()

        let sync = ObservationRenderSync(
            read: { [self] in currentLabelContent() },
            render: { [self] content in render(content) }
        )
        labelSync = sync
        sync.start()

        // SwiftUI wipes `button.image` whenever the scene re-evaluates (every
        // dropdown open/close flips the `isPresented` binding). Restore it
        // synchronously in the same runloop pass so a blank frame never
        // reaches the screen — repainting from `onAppear`/`onDisappear` alone
        // leaves a visible flash.
        imageWipeObservation?.invalidate()
        imageWipeObservation = statusItem.button?.observe(\.image, options: [.new]) { [weak self] button, change in
            MainActor.assumeIsolated {
                guard let self, let owned = self.lastImage else { return }
                if button.image !== owned {
                    button.image = owned
                }
            }
        }

        if wakeObserver == nil {
            // Belt-and-braces: repaint after wake even if nothing changed,
            // in case the menu bar was rebuilt with stale content.
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.labelSync?.renderNow() }
            }
        }
    }

    /// Defense-in-depth repaint around dropdown open/close (the KVO observer
    /// in `attach` is the primary guard against SwiftUI's image wipes). A
    /// no-op when the image is intact, so it never causes extra redraws.
    func reassertPresentation() {
        labelSync?.renderNow()
    }

    private func currentLabelContent() -> LabelContent {
        let freshLabel = monitor.menuBarLabel(
            providerId: settings.menuBarPercentageProviderId,
            primaryQuotaKey: settings.menuBarPercentageQuotaKey,
            secondaryQuotaKey: settings.menuBarSecondaryQuotaKey,
            showPercentage: settings.menuBarPercentageEnabled,
            showDuration: settings.menuBarDurationEnabled,
            mode: settings.usageDisplayMode,
            burnRateWarningEnabled: settings.burnRateWarningEnabled,
            burnRateThreshold: settings.burnRateThreshold
        )

        return LabelContent(
            label: freshLabel ?? lastKnownLabel(whenFreshIsMissing: freshLabel),
            fallbackStatus: effectiveSelectedProviderStatus,
            themeModeId: settings.themeMode,
            stacked: settings.menuBarStackedEnabled,
            stackedSize: settings.menuBarStackedSize
        )
    }

    /// Bridges a momentarily-missing menu-bar label. The configured quota window
    /// can briefly vanish from a snapshot (cold start before the first success, a
    /// parse gap), which would otherwise collapse the menu bar to a lone icon. As
    /// long as the menu-bar provider is enabled and still holds a snapshot, keep
    /// the last value we showed instead of blanking the number. Returns nil when
    /// we have nothing to fall back to, so the normal "no data yet" icon shows.
    private func lastKnownLabel(whenFreshIsMissing freshLabel: MenuBarLabel?) -> MenuBarLabel? {
        guard freshLabel == nil, let previous = lastContent?.label else { return nil }
        let providerHasSnapshot = monitor.enabledProviders.contains {
            $0.id == settings.menuBarPercentageProviderId && $0.snapshot != nil
        }
        return providerHasSnapshot ? previous : nil
    }

    /// Status of the selected provider, considering the burn-rate setting.
    /// Mirrors the dropdown's status logic for the icon-only fallback.
    private var effectiveSelectedProviderStatus: QuotaStatus {
        guard let snapshot = monitor.selectedProvider?.snapshot else { return .healthy }
        if settings.burnRateWarningEnabled {
            return snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return snapshot.overallStatus
    }

    private func render(_ content: LabelContent) {
        guard let button = statusItem?.button else { return }
        // Skip when nothing changed and our image is still in place —
        // re-setting an identical image redraws the button and can flicker.
        if content == lastContent, let lastImage, button.image === lastImage {
            return
        }
        let image = Self.compose(content, theme: resolvedTheme(for: content.themeModeId))
        lastContent = content
        lastImage = image
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = content.label?.text
    }

    private func resolvedTheme(for themeModeId: String) -> any AppThemeProvider {
        let scheme: ColorScheme = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        return ThemeRegistry.shared.resolveTheme(for: themeModeId, systemColorScheme: scheme)
    }

    // MARK: - Image Composition

    /// Composes the full status-item image: optional session glyph, then the
    /// usage text — or the themed status icon when no label is configured or
    /// no quota data exists yet. Mirrors the old SwiftUI label exactly.
    static func compose(_ content: LabelContent, theme: any AppThemeProvider) -> NSImage {
        var parts: [NSImage] = []

        if let label = content.label {
            // Stacked mode only applies to a dual-window label: two windows
            // become two smaller lines (halving the width the label needs).
            // Anything else, including a dual label with stacking off, keeps
            // the classic single-line rendering. The tooltip always stays the
            // full joined text, so no information is lost either way.
            if content.stacked, label.segments.count == 2 {
                parts.append(StatusBarStackedImageRenderer.image(
                    top: (label.segments[0].text, theme.statusColor(for: label.segments[0].status)),
                    bottom: (label.segments[1].text, theme.statusColor(for: label.segments[1].status)),
                    size: content.stackedSize
                ))
            } else {
                parts.append(StatusBarPercentageImageRenderer.image(
                    text: label.text,
                    color: theme.statusColor(for: label.status)
                ))
            }
        } else {
            let symbolName = theme.statusBarIconName ?? fallbackIconName(for: content.fallbackStatus)
            parts.append(symbolImage(
                symbolName,
                color: NSColor(theme.statusColor(for: content.fallbackStatus))
            ))
        }

        return hStack(parts, spacing: 3)
    }

    private static func fallbackIconName(for status: QuotaStatus) -> String {
        switch status {
        case .depleted: "chart.bar.xaxis"
        case .critical: "exclamationmark.triangle.fill"
        case .warning, .healthy: "chart.bar.fill"
        }
    }

    /// Renders an SF Symbol tinted with a fixed color, since the status item
    /// image is non-template (theme colors must survive menu bar appearance).
    private static func symbolImage(_ name: String, color: NSColor) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(configuration) else {
            return NSImage(size: .zero)
        }
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    /// Composites images horizontally, vertically centered.
    private static func hStack(_ images: [NSImage], spacing: CGFloat) -> NSImage {
        let images = images.filter { $0.size.width > 0 }
        guard !images.isEmpty else { return NSImage(size: .zero) }

        let width = images.map(\.size.width).reduce(0, +) + spacing * CGFloat(images.count - 1)
        let height = images.map(\.size.height).max() ?? 0
        let composed = NSImage(size: NSSize(width: ceil(width), height: ceil(height)), flipped: false) { _ in
            var x: CGFloat = 0
            for image in images {
                image.draw(at: NSPoint(x: x, y: (height - image.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
                x += image.size.width + spacing
            }
            return true
        }
        composed.isTemplate = false
        return composed
    }

    // MARK: - Background Refresh Lifecycle

    /// Identity for the background-refresh loop — replaces the `.task(id:)`
    /// that lived on the (freeze-prone) SwiftUI label.
    struct RefreshLoopKey: Equatable {
        var isEnabled: Bool
        var seconds: Int
        var providerIds: [String]?
    }

    /// Starts watching the refresh cadence/target settings and (re)starts the
    /// monitoring loop whenever they change. Call once at app startup.
    func startMonitoringLifecycle() {
        guard loopSync == nil else { return }
        let sync = ObservationRenderSync(
            read: { [self] in currentRefreshLoopKey() },
            render: { [self] key in restartMonitoring(key) }
        )
        loopSync = sync
        sync.start()
    }

    private func currentRefreshLoopKey() -> RefreshLoopKey {
        let interval = settings.refreshInterval
        return RefreshLoopKey(
            isEnabled: interval.isEnabled,
            seconds: interval.seconds ?? 0,
            providerIds: backgroundRefreshProviderIds
        )
    }

    /// While the dropdown is closed we only need the menu-bar provider(s)
    /// fresh, so narrow the periodic refresh to the selected + configured
    /// menu-bar provider when a menu-bar readout is on; otherwise just the
    /// selected provider. Disabled providers are dropped (issue #67).
    private var backgroundRefreshProviderIds: [String]? {
        guard settings.menuBarPercentageEnabled || settings.menuBarDurationEnabled else { return nil }
        let enabledProviderIds = Set(monitor.enabledProviders.map(\.id))
        return [
            monitor.selectedProviderId,
            settings.menuBarPercentageProviderId,
        ].filter { enabledProviderIds.contains($0) }
    }

    private func restartMonitoring(_ key: RefreshLoopKey) {
        streamConsumer?.cancel()
        streamConsumer = nil
        guard key.isEnabled else {
            monitor.stopMonitoring()
            return
        }
        AppLog.monitor.info("Background refresh starting (interval: \(key.seconds)s, providers: \(key.providerIds?.joined(separator: ",") ?? "selected"))")
        let stream = monitor.startMonitoring(
            interval: .seconds(key.seconds),
            providerIds: key.providerIds
        )
        streamConsumer = Task {
            // Each refresh tick imperatively forces a repaint. We can't rely on
            // the @Observable chain alone: after long idle it can stop delivering
            // invalidations (issue #192), freezing the menu-bar image even while
            // probes keep succeeding. renderNow() dedupes inside render(), so this
            // is cheap and only repaints when the composed image actually changed.
            for await _ in stream {
                self.labelSync?.renderNow()
            }
        }
    }
}

/// Renders status text as an original-color image because macOS can ignore
/// `Text.foregroundStyle` inside a menu bar item.
enum StatusBarPercentageImageRenderer {
    @MainActor
    static func image(text: String, color: Color) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(color),
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let imageSize = NSSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let image = NSImage(size: imageSize, flipped: false) { _ in
            attributedText.draw(at: .zero)
            return true
        }
        image.isTemplate = false

        return image
    }
}

/// Renders a dual-window label as two vertically stacked lines in one image,
/// so the label takes roughly half the menu bar width of the joined "A | B"
/// form. Sibling of `StatusBarPercentageImageRenderer`: same original-color
/// rationale (macOS can ignore `Text.foregroundStyle` in a menu bar item, and
/// each line must keep its own window's status color), but a smaller font so
/// both lines fit inside the menu bar's usable height.
///
/// The line size is user-selectable (`MenuBarStackedSize`): Small keeps the
/// original 9pt look, Medium and Large render 10pt and 11pt. At those larger
/// sizes the two natural line boxes no longer fit inside the 22pt clamp, so
/// the renderer verifies the two lines' measured glyph ink cannot collide and
/// switches anchoring strategies when it would (see `image(top:bottom:size:)`).
enum StatusBarStackedImageRenderer {
    /// The menu bar's usable content height. Status-item images taller than
    /// this get clipped or scaled by the system, so the stack never exceeds it.
    private static let maxHeight: CGFloat = 22

    /// Vertical breathing room between the two lines. When the two natural
    /// line heights plus this gap overflow `maxHeight`, the lines keep their
    /// top/bottom anchors and the overflow is absorbed by the gap and the
    /// fonts' descender space instead of clipping a line.
    private static let lineSpacing: CGFloat = 1

    /// Safety inset above the image's bottom edge when ink anchoring engages.
    /// AppKit's string drawing rounds baselines to pixel boundaries, which can
    /// land actual glyph pixels up to ~0.4pt below the analytic glyph-path
    /// bounds (measured), so pinning ink to exactly y = 0 could shave the
    /// bottom row off descenders.
    private static let bottomInkInset: CGFloat = 0.5

    @MainActor
    static func image(
        top: (text: String, color: Color),
        bottom: (text: String, color: Color),
        size: MenuBarStackedSize = .default
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size.stackedLinePointSize, weight: .semibold)
        func attributedLine(_ line: (text: String, color: Color)) -> NSAttributedString {
            NSAttributedString(string: line.text, attributes: [
                .font: font,
                .foregroundColor: NSColor(line.color),
            ])
        }
        let topLine = attributedLine(top)
        let bottomLine = attributedLine(bottom)

        // Lines stay left-aligned: the image is as wide as the wider line and
        // both draw from x = 0, matching how the two windows read as a list.
        let width = ceil(max(topLine.size().width, bottomLine.size().width))
        let naturalHeight = topLine.size().height + lineSpacing + bottomLine.size().height
        let height = min(maxHeight, ceil(naturalHeight))

        // Default layout: line boxes anchored to the image edges, bottom line
        // at y = 0 and the top line's box against the top edge, with any clamp
        // deficit absorbed by the gap and the fonts' descender space. This is
        // the original Small rendering, byte-identical when no collision.
        var topOriginY = height - topLine.size().height
        var bottomOriginY: CGFloat = 0

        // Collision check: at 10pt a descender-bearing top line, and at 11pt
        // every realistic pairing, would let the glyphs themselves overlap
        // under box anchoring (measured -0.3 to -2.2pt of ink clearance).
        // When the measured glyph ink of the two lines would touch, switch to
        // INK anchoring: pin the bottom line's lowest ink just above y = 0 and
        // the top line's highest ink to the top edge. Line boxes may then
        // overflow the image, but a line box is mostly empty ascender and
        // descender allowance; reclaiming that padding restores over +3pt of
        // clearance at 11pt for realistic labels while nothing clips. Small
        // (9pt) always measures positive clearance here, so its rendering is
        // untouched. A line drawn at origin y has its baseline at
        // y + boxHeight - font.ascender, and ink bounds are baseline-relative.
        let topInk = inkBounds(of: topLine)
        let bottomInk = inkBounds(of: bottomLine)
        if !topInk.isNull, !bottomInk.isNull {
            let topInkBottom = topOriginY + topLine.size().height - font.ascender + topInk.minY
            let bottomInkTop = bottomOriginY + bottomLine.size().height - font.ascender + bottomInk.maxY
            if topInkBottom - bottomInkTop < 0 {
                bottomOriginY = bottomInkInset - (bottomLine.size().height - font.ascender) - bottomInk.minY
                topOriginY = height - (topLine.size().height - font.ascender) - topInk.maxY
            }
        }

        // flipped: false, so y grows upward: the bottom line sits at the
        // bottom and the top line is anchored to the image's top edge.
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            bottomLine.draw(at: NSPoint(x: 0, y: bottomOriginY))
            topLine.draw(at: NSPoint(x: 0, y: topOriginY))
            return true
        }
        image.isTemplate = false

        return image
    }

    /// Tight glyph-path bounds of the line's ink, relative to its baseline
    /// origin (CoreText convention: y = 0 is the baseline, descenders are
    /// negative). Null for a line with no ink, e.g. all whitespace.
    private static func inkBounds(of line: NSAttributedString) -> CGRect {
        CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(line), [.useGlyphPathBounds])
    }
}

extension MenuBarStackedSize {
    /// The point size each stacked line renders at. This mapping lives in the
    /// App layer (not Domain) because it is a rendering concern: Domain models
    /// the user's choice, the renderer decides what it means in points. The
    /// values are capped at 11pt because two lines of measured glyph ink must
    /// still fit inside the menu bar's 22pt content height (see
    /// `StatusBarStackedImageRenderer`).
    var stackedLinePointSize: CGFloat {
        switch self {
        case .small: 9
        case .medium: 10
        case .large: 11
        }
    }

    /// SF Symbol for the settings choice chip. Every chip in the menu bar
    /// section carries a leading icon, so the size options do too.
    var choiceIconName: String {
        switch self {
        case .small: "textformat.size.smaller"
        case .medium: "textformat.size"
        case .large: "textformat.size.larger"
        }
    }
}
