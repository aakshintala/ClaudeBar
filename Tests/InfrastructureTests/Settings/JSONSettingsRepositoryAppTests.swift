import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for app-level settings in JSONSettingsRepository.
@Suite("JSONSettingsRepository App Settings Tests")
struct JSONSettingsRepositoryAppTests {

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

    // MARK: - Theme

    @Test
    func `themeMode defaults to dark`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.themeMode() == "dark")
    }

    @Test
    func `setThemeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setThemeMode("dark")
        #expect(repo.themeMode() == "dark")
    }

    @Test
    func `userHasChosenTheme defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.userHasChosenTheme() == false)
    }

    @Test
    func `setUserHasChosenTheme persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setUserHasChosenTheme(true)
        #expect(repo.userHasChosenTheme() == true)
    }

    // MARK: - Overview

    @Test
    func `overviewModeEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.overviewModeEnabled() == false)
    }

    @Test
    func `setOverviewModeEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setOverviewModeEnabled(true)
        #expect(repo.overviewModeEnabled() == true)
    }

    // MARK: - Background Sync

    @Test
    func `backgroundSyncEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.backgroundSyncEnabled() == false)
    }

    @Test
    func `backgroundSyncInterval defaults to 600`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        // Power-conscious 10-minute default for background refresh (issue #204).
        #expect(repo.backgroundSyncInterval() == 600)
    }

    @Test
    func `setBackgroundSyncInterval persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setBackgroundSyncInterval(120)
        #expect(repo.backgroundSyncInterval() == 120)
    }

    // MARK: - Updates

    @Test
    func `receiveBetaUpdates defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.receiveBetaUpdates() == false)
    }

    @Test
    func `setReceiveBetaUpdates persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setReceiveBetaUpdates(true)
        #expect(repo.receiveBetaUpdates() == true)
    }

    // MARK: - Persistence across instances

    @Test
    func `values persist across separate repository instances`() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store)
        repo1.setThemeMode("cli")
        repo1.setOverviewModeEnabled(true)

        // New repo, same store
        let repo2 = JSONSettingsRepository(store: store)
        #expect(repo2.themeMode() == "cli")
        #expect(repo2.overviewModeEnabled() == true)
    }
}
