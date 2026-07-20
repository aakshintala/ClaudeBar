import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for provider-level settings in JSONSettingsRepository.
@Suite("JSONSettingsRepository Provider Settings Tests")
struct JSONSettingsRepositoryProviderTests {

    private func makeRepository() -> (JSONSettingsRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)
        let repo = JSONSettingsRepository(store: store)
        return (repo, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Provider Enabled State

    @Test
    func `isEnabled defaults to true`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isEnabled(forProvider: "claude") == true)
    }

    @Test
    func `isEnabled with custom default returns that default`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isEnabled(forProvider: "cursor", defaultValue: false) == false)
    }

    @Test
    func `setEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        #expect(repo.isEnabled(forProvider: "claude") == false)
    }

    @Test
    func `providers have independent enabled state`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        repo.setEnabled(true, forProvider: "codex")

        #expect(repo.isEnabled(forProvider: "claude") == false)
        #expect(repo.isEnabled(forProvider: "codex") == true)
    }

    // MARK: - Custom Card URL

    @Test
    func `customCardURL defaults to nil`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `setCustomCardURL persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == "https://claude.owo.nz/")
    }

    @Test
    func `setCustomCardURL nil removes value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL(nil, forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `setCustomCardURL empty string removes value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL("", forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `customCardURL is per provider`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL("https://codex.example.com/", forProvider: "codex")

        #expect(repo.customCardURL(forProvider: "claude") == "https://claude.owo.nz/")
        #expect(repo.customCardURL(forProvider: "codex") == "https://codex.example.com/")
        #expect(repo.customCardURL(forProvider: "gemini") == nil)
    }

    // MARK: - Codex Settings

    @Test
    func `codexProbeMode defaults to rpc`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.codexProbeMode() == .rpc)
    }

    @Test
    func `setCodexProbeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCodexProbeMode(.api)
        #expect(repo.codexProbeMode() == .api)
    }

    // MARK: - Hook Settings

    @Test
    func `isHookEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isHookEnabled() == false)
    }

    @Test
    func `setHookEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setHookEnabled(true)
        #expect(repo.isHookEnabled() == true)
    }

    @Test
    func `hookPort defaults to 19847`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.hookPort() == HookConstants.defaultPort)
    }

    @Test
    func `setHookPort persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setHookPort(8080)
        #expect(repo.hookPort() == 8080)
    }

}
