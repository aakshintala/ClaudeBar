import Foundation
import Domain

/// Everything persisted in `~/.claudebar/settings.json`.
/// A missing or mistyped key decodes to its default; keys not modelled here
/// are dropped on the next write.
public struct SettingsFile: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public var themeMode = "dark"
        public var backgroundSyncEnabled = false
        /// 10 min (issue #204): a power-conscious default for background refresh.
        public var backgroundSyncInterval: TimeInterval = 600
        public var quotaAlertsEnabled = true

        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            themeMode = c(.themeMode, themeMode)
            backgroundSyncEnabled = c(.backgroundSyncEnabled, backgroundSyncEnabled)
            backgroundSyncInterval = c(.backgroundSyncInterval, backgroundSyncInterval)
            quotaAlertsEnabled = c(.quotaAlertsEnabled, quotaAlertsEnabled)
        }
    }

    /// The localhost quota feed (`/quotas`, `/hooks`).
    public struct Feed: Codable, Equatable, Sendable {
        public var enabled = false
        public var port = 8787

        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = c(.enabled, enabled)
            port = c(.port, port)
        }
    }

    public struct Provider: Codable, Equatable, Sendable {
        public var isEnabled: Bool?
    }

    public var app = App()
    public var feed = Feed()
    public var providers: [String: Provider] = [:]

    private enum CodingKeys: String, CodingKey { case app, feed, mcp, providers }

    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = c(.app, app)
        feed = c(.feed, c(.mcp, feed))   // one-time migration from the old `mcp` section
        providers = c(.providers, providers)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(app, forKey: .app)
        try c.encode(feed, forKey: .feed)
        // ponytail: mirrors feed for installed builds that still read `mcp.*`; drop once they are gone.
        try c.encode(feed, forKey: .mcp)
        try c.encode(providers, forKey: .providers)
    }
}

private extension KeyedDecodingContainer {
    func callAsFunction<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// Settings read once from `~/.claudebar/settings.json` into memory; every
/// change rewrites the whole file atomically.
public final class JSONSettingsRepository: ProviderSettingsRepository, @unchecked Sendable {
    public static let shared = JSONSettingsRepository(
        fileURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claudebar/settings.json")
    )

    private let fileURL: URL
    private let lock = NSLock()
    private var current: SettingsFile

    public init(fileURL: URL) {
        self.fileURL = fileURL
        current = (try? JSONDecoder().decode(SettingsFile.self, from: Data(contentsOf: fileURL))) ?? SettingsFile()
    }

    public var settings: SettingsFile { lock.withLock { current } }

    public func update(_ change: (inout SettingsFile) -> Void) {
        lock.withLock {
            change(&current)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(current) else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Forgets stored state for providers the app no longer registers (in memory; persisted on the next write).
    public func keepProviders(_ ids: [String]) {
        lock.withLock { current.providers = current.providers.filter { ids.contains($0.key) } }
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        settings.providers[id]?.isEnabled ?? defaultValue
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        update { $0.providers[id, default: .init()].isEnabled = enabled }
    }
}
