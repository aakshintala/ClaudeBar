import AppKit
import Domain
import Infrastructure

/// Drives the menu-bar status item imperatively (AppKit), bypassing SwiftUI's
/// `MenuBarExtra` label hosting entirely.
///
/// After system sleep, the MenuBarExtra label hosting view can permanently
/// stop receiving SwiftUI invalidations: the dropdown window keeps updating
/// while the label — and any `.task` attached to it — goes dead until relaunch
/// (issue #192). This driver owns the background-refresh lifecycle that used
/// to live on that label via `.task(id:)`, and sets a static icon on the status
/// item button so SwiftUI wipes don't leave the menu bar blank.
///
/// Lives for the app's lifetime; the closure retain cycles this creates are
/// intentional and harmless.
@MainActor
final class StatusItemLabelDriver {
    private let monitor: QuotaMonitor
    private let settings: AppSettings

    private var statusItem: NSStatusItem?
    private var loopSync: ObservationRenderSync<RefreshLoopKey>?
    private var streamConsumer: Task<Void, Never>?

    private var staticImage: NSImage?
    private var imageWipeObservation: NSKeyValueObservation?

    init(monitor: QuotaMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }

    /// Attaches to the `NSStatusItem` exposed by MenuBarExtraAccess and sets the
    /// static icon. Repeated callbacks re-assert the image (cheap, idempotent).
    func attach(_ statusItem: NSStatusItem) {
        guard self.statusItem !== statusItem else { return }
        self.statusItem = statusItem

        if staticImage == nil {
            staticImage = Self.makeStaticImage()
        }
        if let image = staticImage {
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
        }

        // SwiftUI wipes `button.image` whenever the scene re-evaluates (every
        // dropdown open/close flips the `isPresented` binding). Restore it
        // synchronously in the same runloop pass so a blank frame never
        // reaches the screen.
        imageWipeObservation?.invalidate()
        imageWipeObservation = statusItem.button?.observe(\.image, options: [.new]) { [weak self] button, _ in
            MainActor.assumeIsolated {
                guard let self, let owned = self.staticImage else { return }
                if button.image !== owned {
                    button.image = owned
                }
            }
        }
    }

    /// Defense-in-depth re-assert around dropdown open/close (the KVO observer
    /// in `attach` is the primary guard against SwiftUI's image wipes).
    func reassertPresentation() {
        guard let button = statusItem?.button, let image = staticImage else { return }
        if button.image !== image {
            button.image = image
        }
    }

    private static func makeStaticImage() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "ClaudeBar")?
            .withSymbolConfiguration(configuration)
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

    private var backgroundRefreshProviderIds: [String]? {
        nil
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
            for await _ in stream { }
        }
    }
}
