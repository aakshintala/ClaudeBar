# Phase 3: App UI Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the cut subsystems (hooks/session tracking, daily-usage analytics, extensions, share-pass, dead scaffolding, menu-bar live-label pipeline, CLI/Christmas/System themes, Claude API budget card) across Domain/Infrastructure/App, then rebuild a grouped-header popover, a truly static menu-bar icon with sleep-safe refresh-loop restart, a trimmed Settings screen, and a 2-theme (pure-black Dark + Light) system.

**Architecture:** Delete-first, compiler-error-driven — same pattern as Phase 1 (`2026-07-18-strip-to-four-providers.md`). Each deletion task removes one subsystem/cluster, greps for dangling consumers, fixes every compile break, then gates on build+test before committing. Rebuild tasks replace `MenuContentView` / `SettingsContentView` / `StatusItemLabelDriver` with smaller single-purpose files under `Sources/App/Views/Popover/` and rename the status-item driver. Views continue to consume `QuotaMonitor` directly (no ViewModel). `QuotaMonitor` polling and all 4 provider probes stay unchanged except where cut features were wired into them.

**Tech Stack:** Swift 6, Tuist, XCTest/Swift Testing, Mockable, SwiftUI + MenuBarExtraAccess. macOS 15 deployment target.

**Design spec:** [`docs/superpowers/specs/2026-07-20-app-ui-rewrite-design.md`](../specs/2026-07-20-app-ui-rewrite-design.md)

## Open Questions for Reviewer

Resolved by reading the repo where possible; remaining judgment calls defaulted below — override before execution if wrong:

1. **Theme import is wired, not dead.** Spec said `ThemeImportView` is never presented; current code presents `ThemeImportButton` at `SettingsView.swift:154`. Plan deletes it as a live (cut) feature.
2. **`SystemTheme` cut with CLI/Christmas.** Design keeps only Dark + Light. Plan also deletes `SystemTheme` (registered at `ThemeRegistry.swift:43`) and changes the `themeMode` default from `"system"` → `"dark"`. Orphaned stored values (`system`/`cli`/`christmas`/`imported-*`) fall back to Dark via `ThemeRegistry.resolveTheme`.
3. **No existing quota-alert enable setting.** `NotificationAlerter` always fires. Plan **adds** `app.quotaAlertsEnabled` (default `true`) during the Settings rebuild and gates alerts on it. Confirm key name / default.
4. **Hook uninstall for existing installs.** Deleting `HookInstaller` leaves `~/.claude/settings.json` ClaudeBar hook entries and `~/.claude/claudebar-hook-port` in place. Plan does **not** add a migration uninstall (recoverable manually). Say if you want a one-shot `HookInstaller.uninstall()` before deleting the file.
5. **Settings extras beyond the design's three rows.** Plan also deletes burn-rate warning, overview mode, launch-at-login, logs/about cards, and `receiveBetaUpdates` (Sparkle already gone). `CodexConfigCard` probe-mode picker is **kept** (credential/config status for Codex).
6. **App-layer tests.** There is no `AppTests` target and zero tests for SwiftUI views. New popover/Settings/driver views are **preview/manual only**, matching project convention. Domain/Infrastructure deletions delete orphaned tests alongside subjects.

## Global Constraints

- **Delete-first, then rebuild.** Sub-phase 3a (Tasks 1–11) must finish green before 3b (Tasks 12–18). Do not start rebuilding `PopoverView` while cut subsystems still compile into `MenuContentView`.
- **Green gate after every task.** Because `tuist test` (no args) has a stale-scheme quirk in this environment (reports "no tests to run" even when the scheme has testables), verify with a **clean regenerate + build + test**:

```bash
rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open && \
  xcodebuild build -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'
```

Expected: `** BUILD SUCCEEDED **`

```bash
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'
```

Expected: `** TEST SUCCEEDED **` with no failures. Never trust a bare `tuist test` "no tests to run" result as a real signal.

- **`JSONSettingsRepository` deletion order.** It implements `AppSettingsRepository` + `CodexSettingsRepository` + `HookSettingsRepository` (+ base provider methods). Never strip a protocol conformance while call sites still need those methods — remove call sites and protocol methods in the **same task**. Same rule for `UserDefaultsProviderSettingsRepository` and `AppSettings`.
- **Symbol-level search.** Before deleting, run `grep -rln "<Symbol>" Sources/ Tests/` (and again after). Match whole identifiers.
- **This is a fork.** Anything deleted is recoverable via `git log` / `git show`. Work directly on `main` (established personal-fork workflow) unless told otherwise.
- **Personal build only.** No signing/notarization/release changes.
- **Keep:** `QuotaMonitor` core polling, all 4 providers' probes, `CostUsage` + `BudgetStatus` + cost cards (restyled), `NotificationAlerter` (quota-threshold alerts), `ObservationRenderSync`, background refresh via the status-item driver, Dark + Light themes.
- **Out of scope:** Codex "rate-limit resets available" counter; Keychain migration; docs/CLAUDE.md updates (optional follow-on).

### Verification helper (paste into every task)

Unless a task says otherwise, "**VERIFY**" means the two commands in Global Constraints above.

### Target `Sources/App/` shape (after 3b)

```
ClaudeBarApp.swift
StatusBarIconDriver.swift
Settings/AppSettings.swift
Views/Popover/PopoverView.swift
Views/Popover/ProviderQuotaSection.swift
Views/Popover/QuotaBucketRow.swift
Views/Settings/SettingsView.swift          # rewritten SettingsContentView
Views/Settings/ClaudeConfigCard.swift      # auth-only (budget card gone)
Views/Settings/CodexConfigCard.swift       # kept
Views/CostStatCard.swift                   # restyled, no external budget
Theme/… (DarkTheme rewritten, LightTheme reviewed, ThemeRegistry = 2)
```

Exact file boundaries may shift slightly; no view file should balloon past a few hundred lines.

---

## Task 0: Baseline green

**Files:** none (setup only)

- [ ] **Step 1: Confirm clean tree on the working branch**

```bash
git status
git log -3 --oneline
```

- [ ] **Step 2: Establish a green baseline**

VERIFY (Global Constraints commands).
Expected: BUILD SUCCEEDED + TEST SUCCEEDED. Record the pass count mentally — later tasks reduce it as orphaned tests are deleted; it must never go from green to red mid-task.

- [ ] **Step 3: Commit nothing** — baseline only. Proceed.

---

## Task 1: Delete dead scaffolding (Live Activity + multi-account)

These are unwired. `LiveActivityManager` has zero call sites. `MultiAccountProvider` has zero adopters. `AccountPickerView` / `AccountManagementCard` are never instantiated. Safe first cut — no settings-protocol impact.

**Files:**
- Delete: `Sources/App/LiveActivity/LiveActivityManager.swift`
- Delete: `Sources/App/Views/AccountPickerView.swift`
- Delete: `Sources/App/Views/Settings/AccountManagementCard.swift`
- Delete: `Sources/Domain/Provider/ProviderAccount.swift`
- Delete: `Sources/Domain/Provider/MultiAccountSupport.swift`
- Delete: `Sources/Domain/Provider/MultiAccountSettingsRepository.swift`
- Delete: `Tests/DomainTests/Provider/ProviderAccountTests.swift`
- Delete: `Tests/DomainTests/Provider/ProviderAccountConfigTests.swift`

- [ ] **Step 1: Confirm zero production consumers**

```bash
grep -rln "LiveActivityManager\|AccountPickerView\|AccountManagementCard\|MultiAccountProvider\|MultiAccountSettingsRepository\|ProviderAccountConfig\|ProviderAccount" Sources/ Tests/ | grep -v docs
```

Expected: only the files listed above (definitions + their tests). If any other `Sources/` file appears, STOP and add it to the trim list.

- [ ] **Step 2: Delete**

```bash
git rm -r \
  Sources/App/LiveActivity \
  Sources/App/Views/AccountPickerView.swift \
  Sources/App/Views/Settings/AccountManagementCard.swift \
  Sources/Domain/Provider/ProviderAccount.swift \
  Sources/Domain/Provider/MultiAccountSupport.swift \
  Sources/Domain/Provider/MultiAccountSettingsRepository.swift \
  Tests/DomainTests/Provider/ProviderAccountTests.swift \
  Tests/DomainTests/Provider/ProviderAccountConfigTests.swift
```

- [ ] **Step 3: VERIFY**

Expected: BUILD SUCCEEDED + TEST SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove Live Activity and multi-account scaffolding

Unused placeholder and views with no MultiAccountProvider adopters.
EOF
)"
```

---

## Task 2: Delete custom web card

Removes `CustomWebCardView` / `CustomCardURLField` and the `customCardURL` API from `ProviderSettingsRepository` + both repository implementations. Do the protocol + call sites atomically so `JSONSettingsRepository` stays compiling.

**Files:**
- Delete: `Sources/App/Views/CustomWebCardView.swift`
- Delete: `Sources/App/Views/Settings/CustomCardURLField.swift`
- Modify: `Sources/Domain/Provider/ProviderSettingsRepository.swift:18-22` (remove `customCardURL` / `setCustomCardURL`)
- Modify: `Sources/Infrastructure/Storage/JSONSettingsRepository.swift:195-202`
- Modify: `Sources/Infrastructure/Storage/UserDefaultsProviderSettingsRepository.swift:34-44`
- Modify: `Sources/App/Views/MenuContentView.swift:646-651`
- Modify: `Sources/App/Views/SettingsView.swift:651-654`
- Modify: `Tests/DomainTests/TestHelpers/MockRepositoryFactory.swift:17-18`
- Modify: `Tests/InfrastructureTests/Settings/JSONSettingsRepositoryProviderTests.swift:65-111` (delete customCardURL tests)
- Check: `Tests/InfrastructureTests/UserDefaultsProviderSettingsRepositoryTests.swift` for customCardURL cases

- [ ] **Step 1: Grep consumers**

```bash
grep -rn "customCardURL\|CustomWebCardView\|CustomCardURLField\|setCustomCardURL" Sources/ Tests/
```

- [ ] **Step 2: Delete the two App view files**

```bash
git rm \
  Sources/App/Views/CustomWebCardView.swift \
  Sources/App/Views/Settings/CustomCardURLField.swift
```

- [ ] **Step 3: Strip `ProviderSettingsRepository`**

In `Sources/Domain/Provider/ProviderSettingsRepository.swift`, delete these protocol requirements (currently lines 18–22):

```swift
    /// Gets the custom card URL for a provider (nil if not set)
    func customCardURL(forProvider id: String) -> String?

    /// Sets the custom card URL for a provider (empty string or nil to remove)
    func setCustomCardURL(_ url: String?, forProvider id: String)
```

- [ ] **Step 4: Strip both repository implementations**

Delete the `customCardURL` / `setCustomCardURL` methods from:
- `JSONSettingsRepository.swift` (lines 195–202, keys `providers.{id}.customCardURL`)
- `UserDefaultsProviderSettingsRepository.swift` (lines 34–44)

- [ ] **Step 5: Strip UI call sites**

In `MenuContentView.swift`, delete the block at lines 646–651:

```swift
            // Show custom web card if URL is configured for this provider
            if let urlString = settings.provider.customCardURL(forProvider: snapshot.providerId),
               let url = URL(string: urlString) {
                let cardDelay = Double(snapshot.quotas.count + 2) * 0.08
                CustomWebCardView(url: url, delay: cardDelay)
            }
```

In `SettingsView.swift`, delete the block at lines 651–654:

```swift
            if provider.isEnabled {
                CustomCardURLField(providerId: provider.id)
                    .padding(.leading, 30)
            }
```

- [ ] **Step 6: Fix mocks and tests**

In `MockRepositoryFactory.swift`, remove the two `customCardURL` / `setCustomCardURL` `given(...)` lines.

Delete the `// MARK: - Custom Card URL` (or equivalent) tests covering `customCardURL` from `JSONSettingsRepositoryProviderTests.swift` (lines 65–111) and any matching cases in `UserDefaultsProviderSettingsRepositoryTests.swift`.

- [ ] **Step 7: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove custom web card and customCardURL settings

Drops the arbitrary-URL webview embed and its provider settings API.
EOF
)"
```

---

## Task 3: Delete theme import + TerminalImport

Removes `.itermcolors` import pipeline. `ThemeImportButton` **is** presented in Settings (`SettingsView.swift:154`) — cut per design. Keep `CLITheme` / `ChristmasTheme` until Task 9 (they are built-ins, not import-only).

**Files:**
- Delete: `Sources/App/Settings/ThemeImportView.swift`
- Delete: `Sources/App/Theme/ImportedThemeStore.swift`
- Delete: `Sources/App/Theme/ImportedTerminalTheme.swift`
- Delete: `Sources/Infrastructure/TerminalImport/ITermColorsParser.swift`
- Delete: `Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift`
- Delete: `Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift`
- Delete: `Tests/InfrastructureTests/TerminalImport/` (entire dir)
- Modify: `Sources/App/Theme/ThemeRegistry.swift` (drop import store + imported-themes section)
- Modify: `Sources/App/Theme/ThemeEnvironment.swift:52-64` (drop imported-theme branch)
- Modify: `Sources/App/Views/SettingsView.swift:154` and imported-theme delete UI in `ThemeOptionButton` (~1233–1274)

- [ ] **Step 1: Grep**

```bash
grep -rn "ThemeImportButton\|ImportedThemeStore\|ImportedTerminalTheme\|ITermColorsParser\|TerminalThemeGenerator\|TerminalColorScheme\|importItermcolors\|removeImportedTheme\|isImported" Sources/ Tests/
```

- [ ] **Step 2: Delete source + tests**

```bash
git rm \
  Sources/App/Settings/ThemeImportView.swift \
  Sources/App/Theme/ImportedThemeStore.swift \
  Sources/App/Theme/ImportedTerminalTheme.swift
git rm -r \
  Sources/Infrastructure/TerminalImport \
  Tests/InfrastructureTests/TerminalImport
```

- [ ] **Step 3: Rewrite `ThemeRegistry` without imports**

Replace the class body so it no longer references `ImportedThemeStore` / `TerminalThemeGenerator` / `ITermColorsParser` / `ImportedTerminalTheme`. Concretely:

- Remove `private let importedThemeStore = ImportedThemeStore()` (line 31)
- Remove `loadImportedThemes()` call from `init` (line 36)
- Delete the entire `// MARK: - Imported Themes` section (lines 94–132)

`registerBuiltInThemes()` still registers Light/Dark/System/CLI/Christmas until Task 9.

- [ ] **Step 4: Trim `ThemeEnvironment.swift`**

In `effectiveColorScheme` (lines 52–64), replace the `.none` imported-theme branch with a simple fallback to `systemColorScheme`:

```swift
    private var effectiveColorScheme: ColorScheme {
        let mode = ThemeMode(rawValue: themeModeId)
        switch mode {
        case .light: return .light
        case .dark, .cli, .christmas: return .dark
        case .system: return systemColorScheme
        case .none: return systemColorScheme
        }
    }
```

- [ ] **Step 5: Trim Settings theme UI**

Remove `ThemeImportButton()` at line 154. In `ThemeOptionButton`, remove any `isImported` / delete-imported-theme controls (grep `removeImportedTheme` / `isImported` inside `SettingsView.swift`).

- [ ] **Step 6: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove theme import and TerminalImport pipeline

Drops .itermcolors import UI, ImportedTerminalTheme, and parsers.
EOF
)"
```

---

## Task 4: Delete extensions / plugin system

Full wipe of `Sources/Domain/Extension/`, `Sources/Infrastructure/Extension/`, App cards, and `UsageSnapshot.extensionMetrics`. Do **before** daily-usage model deletion so `DailyUsageReport` is only referenced by the Claude JSONL path afterward.

**Files:**
- Delete wholesale: `Sources/Domain/Extension/`, `Sources/Infrastructure/Extension/`
- Delete: `Sources/App/Views/Settings/ExtensionConfigCard.swift`
- Delete: `Sources/App/Views/ExtensionMetricCardView.swift`
- Delete: `Tests/DomainTests/Extension/`, `Tests/InfrastructureTests/Extension/`
- Modify: `Sources/App/ClaudeBarApp.swift:97-105`
- Modify: `Sources/App/Views/SettingsView.swift:34-42, 73-79`
- Modify: `Sources/App/Views/MenuContentView.swift:629-644`
- Modify: `Sources/App/Settings/AppSettings.swift:293-296`
- Modify: `Sources/Domain/Provider/UsageSnapshot.swift` (`extensionMetrics` field + `quotaGroups` metric logic)
- Modify: `Tests/DomainTests/Provider/UsageSnapshotTests.swift` (~420–489)

- [ ] **Step 1: Grep**

```bash
grep -rln "ExtensionRegistry\|ExtensionProvider\|ExtensionConfigCard\|ExtensionMetricCardView\|ExtensionMetric\|ExtensionManifest\|ScriptProbe\|HealthCheckProbe\|JSONExtensionConfigRepository\|ExtensionConfigRepository\|ExtensionDirectoryScanner\|SectionData\|extensionConfig\|extensionMetrics" Sources/ Tests/
```

- [ ] **Step 2: Delete directories and App cards**

```bash
git rm -r \
  Sources/Domain/Extension \
  Sources/Infrastructure/Extension \
  Tests/DomainTests/Extension \
  Tests/InfrastructureTests/Extension
git rm \
  Sources/App/Views/Settings/ExtensionConfigCard.swift \
  Sources/App/Views/ExtensionMetricCardView.swift
```

- [ ] **Step 3: Remove wiring from `ClaudeBarApp.swift`**

Delete lines 97–105:

```swift
        // Load user extensions from ~/.claudebar/extensions/
        let extensionRegistry = ExtensionRegistry(
            settingsRepository: settingsRepository,
            configRepository: AppSettings.shared.extensionConfig
        )
        let extensionProviders = extensionRegistry.loadExtensions(into: monitor)
        if !extensionProviders.isEmpty {
            AppLog.providers.info("Loaded \(extensionProviders.count) extension provider(s): \(extensionProviders.map(\.name).joined(separator: ", "))")
        }
```

- [ ] **Step 4: Remove Settings / Menu / AppSettings references**

- `SettingsView.swift`: delete `enabledExtensionProvidersWithConfig` (34–42) and the `ForEach(ExtensionConfigCard…)` (73–79).
- `MenuContentView.swift`: delete the extension-metrics grid (629–644).
- `AppSettings.swift`: delete:

```swift
    /// Extension config repository for dynamic extension provider settings.
    public let extensionConfig: any ExtensionConfigRepository = JSONExtensionConfigRepository(
        settingsStore: .shared
    )
```

- [ ] **Step 5: Strip `UsageSnapshot.extensionMetrics`**

In `Sources/Domain/Provider/UsageSnapshot.swift`:
- Remove the `extensionMetrics` property (lines 29–30), init parameter (44), and assignment (55).
- Simplify `hasQuotaGroups` to quotas-only:

```swift
    public var hasQuotaGroups: Bool {
        quotas.contains { $0.group != nil }
    }
```

- In `quotaGroups`, delete the `notes` / `extensionMetrics` loop (lines 111–120) and pass `note: nil` (or drop the note field usage). Keep quota grouping by `quota.group` if still used; if nothing else needs groups after extensions are gone, leaving the quota-only grouping is fine.

- [ ] **Step 6: Fix `UsageSnapshotTests`**

Delete or rewrite tests that construct `ExtensionMetric` / pass `extensionMetrics:` (around lines 420–489).

- [ ] **Step 7: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove extensions/plugin system

Drops ExtensionRegistry, probes, config store, UI cards, and snapshot metrics.
EOF
)"
```

---

## Task 5: Delete daily-usage analytics

After Task 4, `DailyUsageReport` / `DailyUsageStat` are only used by the Claude JSONL path + UI. Delete the whole stack including `SessionJSONLParser` and `ModelPricing` (daily-usage-only consumers — not hooks).

**Files:**
- Delete: `Sources/Domain/DailyUsage/` (entire)
- Delete: `Sources/Infrastructure/Claude/ClaudeDailyUsageAnalyzer.swift`
- Delete: `Sources/Infrastructure/Claude/SessionJSONLParser.swift`
- Delete: `Sources/Infrastructure/Claude/ModelPricing.swift`
- Delete: `Sources/App/Views/DailyUsageCardView.swift`
- Delete: `Tests/DomainTests/DailyUsage/`
- Delete: `Tests/InfrastructureTests/Claude/ClaudeDailyUsageAnalyzerTests.swift`
- Delete: `Tests/InfrastructureTests/Claude/SessionJSONLParserTests.swift`
- Delete: `Tests/InfrastructureTests/Claude/ModelPricingTests.swift`
- Delete: `Tests/DomainTests/Provider/Claude/ClaudeProviderDailyUsageTests.swift`
- Modify: `Sources/Domain/Provider/Claude/ClaudeProvider.swift` (analyzer wiring + `attachDailyReport`)
- Modify: `Sources/App/ClaudeBarApp.swift:60`
- Modify: `Sources/Domain/Provider/UsageSnapshot.swift` (`dailyUsageReport` field)
- Modify: `Sources/Domain/Settings/AppSettingsRepository.swift:45-46`
- Modify: `Sources/Infrastructure/Storage/JSONSettingsRepository.swift:109-115`
- Modify: `Sources/App/Settings/AppSettings.swift` (`showDailyUsageCards`)
- Modify: `Sources/App/Views/MenuContentView.swift:610-627`
- Modify: `Sources/App/Views/SettingsView.swift` (daily usage toggle ~179, ~500–514)
- Modify: `Tests/InfrastructureTests/Settings/JSONSettingsRepositoryAppTests.swift` (showDailyUsageCards tests)

- [ ] **Step 1: Grep**

```bash
grep -rln "DailyUsage\|ClaudeDailyUsageAnalyzer\|DailyUsageAnalyzing\|SessionJSONLParser\|ModelPricing\|showDailyUsageCards\|dailyUsageReport\|DailyUsageCardView\|TokenUsageRecord" Sources/ Tests/
```

Confirm `SessionJSONLParser` has no remaining non-daily-usage consumers.

- [ ] **Step 2: Delete source + tests**

```bash
git rm -r Sources/Domain/DailyUsage Tests/DomainTests/DailyUsage
git rm \
  Sources/Infrastructure/Claude/ClaudeDailyUsageAnalyzer.swift \
  Sources/Infrastructure/Claude/SessionJSONLParser.swift \
  Sources/Infrastructure/Claude/ModelPricing.swift \
  Sources/App/Views/DailyUsageCardView.swift \
  Tests/InfrastructureTests/Claude/ClaudeDailyUsageAnalyzerTests.swift \
  Tests/InfrastructureTests/Claude/SessionJSONLParserTests.swift \
  Tests/InfrastructureTests/Claude/ModelPricingTests.swift \
  Tests/DomainTests/Provider/Claude/ClaudeProviderDailyUsageTests.swift
```

- [ ] **Step 3: Collapse `ClaudeProvider` daily-usage path**

Current init/wiring (lines 67–88, 108–158) — replace so the provider is probe + settings only for this concern (pass probe still present until Task 6):

```swift
    public init(
        probe: any UsageProbe,
        passProbe: (any ClaudePassProbing)? = nil,
        settingsRepository: any ProviderSettingsRepository
    ) {
        self.probe = probe
        self.passProbe = passProbe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }
```

In `refresh(_:)`, assign the probe snapshot directly (no `report(for:kind:)` / `attachDailyReport`):

```swift
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil
            return snapshot!
```

Delete `dailyUsageAnalyzer` property, `report(for:kind:)`, and `attachDailyReport(to:)`. Keep `RefreshKind` usage if the protocol still requires `refresh(_ kind:)` — just ignore the kind for attachment purposes (both paths return the probe snapshot).

- [ ] **Step 4: Update `ClaudeBarApp` registration**

Change the Claude registration block (lines 56–61) to:

```swift
            ClaudeProvider(
                probe: ClaudeAPIUsageProbe(),
                passProbe: ClaudePassProbe(),
                settingsRepository: settingsRepository
            ),
```

- [ ] **Step 5: Strip `UsageSnapshot.dailyUsageReport`**

Remove the property, init parameter, and assignment (currently lines 26–27, 43, 54).

- [ ] **Step 6: Strip `showDailyUsageCards` settings (atomically)**

Remove from:
- `AppSettingsRepository.swift` (lines 45–46)
- `JSONSettingsRepository.swift` (lines 109–115, key `app.showDailyUsageCards`)
- `AppSettings.swift` (property ~103–108 and init hydration ~234)
- `SettingsView.swift` daily-usage toggle
- `MenuContentView.swift` daily cards block (610–627)
- Matching tests in `JSONSettingsRepositoryAppTests.swift`

- [ ] **Step 7: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove daily-usage analytics and JSONL analyzer

Drops DailyUsage* models, ClaudeDailyUsageAnalyzer, SessionJSONLParser, and UI cards.
EOF
)"
```

---

## Task 6: Delete share-pass / ClaudePass

Self-contained. No settings keys.

**Files:**
- Delete: `Sources/Domain/Provider/Claude/ClaudePass.swift`
- Delete: `Sources/Domain/Provider/Claude/ClaudePassProbeProtocol.swift`
- Delete: `Sources/Infrastructure/Claude/ClaudePassProbe.swift`
- Delete: `Sources/App/Views/SharePassView.swift`
- Delete: `Tests/DomainTests/Provider/Claude/ClaudePassTests.swift`
- Delete: `Tests/DomainTests/Provider/Claude/ClaudeProviderPassTests.swift`
- Delete: `Tests/InfrastructureTests/Claude/ClaudePassProbeTests.swift`
- Modify: `Sources/Domain/Provider/Claude/ClaudeProvider.swift` (guest pass API)
- Modify: `Sources/App/ClaudeBarApp.swift:58`
- Modify: `Sources/App/Views/MenuContentView.swift` (overlay + gift button + `fetchAndShowPasses`)
- Modify: `Tests/AcceptanceTests/ActionBarSpec.swift` (guest-pass expectations, if any)

- [ ] **Step 1: Grep**

```bash
grep -rln "ClaudePass\|ClaudePassProbe\|ClaudePassProbing\|SharePass\|guestPass\|fetchPasses\|supportsGuestPasses\|PassError\|shareGradient\|isFetchingPasses" Sources/ Tests/
```

- [ ] **Step 2: Delete source + tests**

```bash
git rm \
  Sources/Domain/Provider/Claude/ClaudePass.swift \
  Sources/Domain/Provider/Claude/ClaudePassProbeProtocol.swift \
  Sources/Infrastructure/Claude/ClaudePassProbe.swift \
  Sources/App/Views/SharePassView.swift \
  Tests/DomainTests/Provider/Claude/ClaudePassTests.swift \
  Tests/DomainTests/Provider/Claude/ClaudeProviderPassTests.swift \
  Tests/InfrastructureTests/Claude/ClaudePassProbeTests.swift
```

- [ ] **Step 3: Strip `ClaudeProvider` to usage-only**

Remove `guestPass`, `isFetchingPasses`, `passProbe`, guest-pass init parameter, `fetchPasses()`, `supportsGuestPasses`, and `PassError`. Final init:

```swift
    public init(
        probe: any UsageProbe,
        settingsRepository: any ProviderSettingsRepository
    ) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }
```

- [ ] **Step 4: Update `ClaudeBarApp`**

```swift
            ClaudeProvider(
                probe: ClaudeAPIUsageProbe(),
                settingsRepository: settingsRepository
            ),
```

- [ ] **Step 5: Strip MenuContentView share UI**

Remove `@State showSharePass`, the `SharePassOverlay` block (lines 101–109), the gift/share button in the action bar (~724–750), and `fetchAndShowPasses` (~830–847). Leave other action-bar buttons for now (Task 15 rebuilds the popover).

- [ ] **Step 6: Trim acceptance tests that assert guest passes; VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove Claude share-pass / guest-pass feature

Drops ClaudePass probe, SharePassOverlay, and provider pass API.
EOF
)"
```

---

## Task 7: Delete hooks + session tracking

Largest App wiring cut. Remove `HookSettingsRepository` from `JSONSettingsRepository` / `UserDefaultsProviderSettingsRepository` / `AppSettings` in the **same task** as deleting call sites. Keep `NotificationAlerter` / `SystemAlertSender` (quota alerts). Keep `SessionJSONLParser` already deleted in Task 5.

**Files:**
- Delete wholesale: `Sources/Infrastructure/Hooks/`, `Sources/Domain/Session/`
- Delete: `Sources/App/Views/SessionIndicatorView.swift`, `Sources/App/Views/SessionPhaseColor.swift`
- Delete: `Tests/InfrastructureTests/Hooks/`, `Tests/DomainTests/Session/`
- Modify: `Sources/App/ClaudeBarApp.swift` (see Step 3)
- Modify: `Sources/App/Views/MenuContentView.swift` (sessionMonitor, hooks callback, SessionIndicatorView)
- Modify: `Sources/App/Views/SettingsView.swift` (hooksCard ~1086–1194 + state)
- Modify: `Sources/App/StatusItemLabelDriver.swift` (sessionMonitor dependency)
- Modify: `Sources/Infrastructure/Storage/JSONSettingsRepository.swift` (conformance + hook methods 218–235)
- Modify: `Sources/Infrastructure/Storage/UserDefaultsProviderSettingsRepository.swift` (conformance + hook methods 59–79, keys 84–86)
- Modify: `Sources/App/Settings/AppSettings.swift:291` (`hook` accessor)
- Modify: `Tests/InfrastructureTests/Settings/JSONSettingsRepositoryProviderTests.swift:133-167`
- Optional trim: `AppLog.hooks` in `AppLogger.swift`

- [ ] **Step 1: Grep**

```bash
grep -rln "HookHTTPServer\|HookInstaller\|SessionMonitor\|HookSettingsRepository\|HookConstants\|HookEventReceiver\|SessionEvent\|ClaudeSession\|SessionIndicatorView\|SessionPhaseColor\|hookSettingsChanged\|isHookEnabled\|PortDiscovery\|SessionEventParser\|AppLog\.hooks\|sessionAlertSender\|sendSessionNotification" Sources/ Tests/
```

- [ ] **Step 2: Delete directories + App session views + tests**

```bash
git rm -r \
  Sources/Infrastructure/Hooks \
  Sources/Domain/Session \
  Tests/InfrastructureTests/Hooks \
  Tests/DomainTests/Session
git rm \
  Sources/App/Views/SessionIndicatorView.swift \
  Sources/App/Views/SessionPhaseColor.swift
```

- [ ] **Step 3: Rewrite `ClaudeBarApp.swift` without hooks/session**

Remove:
- `Notification.Name.hookSettingsChanged` (lines 6–8)
- `sessionMonitor` property + init (16–17, 84–85)
- `hookServer` / `hookServerTask` (28–32)
- `sessionAlertSender` (37–38)
- Hook startup block (107–118)
- `startHookServer` / `stopHookServer` / `sendSessionNotification` (134–191)
- Pass `sessionMonitor` into `StatusItemLabelDriver` and `MenuContentView`
- `StatusBarIcon` session branches + CLI/Christmas preview cases can stay until Tasks 9/12, or delete the entire preview-only `StatusBarIcon` struct (lines 224–321) now if it only exists for previews — prefer delete if it references `ClaudeSession` / `CLITheme` / `ChristmasTheme`

After trim, `init` should look like:

```swift
    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        AppLog.ui.info("ClaudeBar v\(version) (\(build)) initializing...")

        let settingsRepository = JSONSettingsRepository.shared

        let repository = AIProviders(providers: [
            ClaudeProvider(
                probe: ClaudeAPIUsageProbe(),
                settingsRepository: settingsRepository
            ),
            CodexProvider(
                rpcProbe: CodexUsageProbe(),
                apiProbe: CodexAPIUsageProbe(),
                settingsRepository: settingsRepository
            ),
            CursorProvider(probe: CursorUsageProbe(), settingsRepository: settingsRepository),
            OpenCodeProvider(
                probe: OpenCodeUsageProbe(),
                settingsRepository: settingsRepository
            ),
        ])
        AppLog.providers.info("Created \(repository.all.count) providers")

        let monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter
        )
        self.monitor = monitor
        AppLog.monitor.info("QuotaMonitor initialized")

        statusItemDriver = StatusItemLabelDriver(
            monitor: monitor,
            settings: AppSettings.shared
        )
        statusItemDriver.startMonitoringLifecycle()

        AppLog.ui.info("ClaudeBar initialization complete")
    }
```

And `body`:

```swift
    var body: some Scene {
        MenuBarExtra {
            Group {
                MenuContentView(monitor: monitor, quotaAlerter: quotaAlerter)
                    .appThemeProvider(themeModeId: settings.themeMode)
            }
            .onAppear { statusItemDriver.reassertPresentation() }
            .onDisappear { statusItemDriver.reassertPresentation() }
        } label: {
            Color.clear.frame(width: 1, height: 1)
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            statusItemDriver.attach(statusItem)
        }
        .menuBarExtraStyle(.window)
    }
```

Update the JSONSettingsRepository comment in `init` to drop the `HookSettingsRepository` bullet.

- [ ] **Step 4: Trim `MenuContentView` / `SettingsView` / `StatusItemLabelDriver`**

`MenuContentView`:
- Remove `sessionMonitor`, `onHookSettingsChanged`
- Remove SessionIndicatorView block (70–75)
- Remove `.onReceive(.hookSettingsChanged)` (114–117)
- Update call site signature to `MenuContentView(monitor:quotaAlerter:)`

`SettingsView`:
- Remove hook `@State` (15–19), `hooksCard` from body (82), hook load in `.onAppear` (97–99), and the entire `hooksCard` section (~1086–1194)

`StatusItemLabelDriver`:
- Remove `sessionMonitor` property/init parameter
- Remove `sessionPhase` from `LabelContent` and compose path
- Remove terminal-glyph session rendering (~196–202)

- [ ] **Step 5: Strip `HookSettingsRepository` from settings stack (atomic)**

`JSONSettingsRepository.swift`:
- Change conformance list from `AppSettingsRepository, CodexSettingsRepository, HookSettingsRepository` to `AppSettingsRepository, CodexSettingsRepository`
- Delete `// MARK: - HookSettingsRepository` methods (lines 218–235)
- Update file header comment

`UserDefaultsProviderSettingsRepository.swift`:
- Drop `HookSettingsRepository` from the conformance list (line 6)
- Delete hook methods (59–79) and `Keys.hookEnabled` / `Keys.hookPort` (84–86)

`AppSettings.swift`: delete `public var hook: HookSettingsRepository { repository }`

Delete hook tests in `JSONSettingsRepositoryProviderTests.swift` (lines 133–167).

- [ ] **Step 6: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove hooks and session-tracking subsystem

Drops HookHTTPServer/Installer, SessionMonitor, session UI, and hook.* settings.
EOF
)"
```

---

## Task 8: Delete menu-bar live-label pipeline (domain + settings + UI)

Removes live percentage/duration/stacked label composition. Within this task, gut `StatusItemLabelDriver` so it still compiles: set one static `NSImage` at attach time, keep the refresh-loop restart (issue #192). Rename to `StatusBarIconDriver` happens in Task 12.

**Files:**
- Delete: `Sources/Domain/Provider/MenuBarLabel.swift`
- Delete: `Sources/Domain/Provider/MenuBarPercentageDisplay.swift`
- Delete: `Sources/Domain/Provider/MenuBarDurationDisplay.swift`
- Delete: `Sources/Domain/Provider/MenuBarStackedSize.swift`
- Delete: `Sources/Domain/Provider/UsageDisplayMode.swift`
- Delete: `Sources/Domain/Provider/PopoverContentHeight.swift` (bounce fix replaces it in Task 15)
- Delete: `Tests/DomainTests/Provider/MenuBarDurationDisplayTests.swift`
- Delete: `Tests/DomainTests/Provider/MenuBarStackedSizeTests.swift`
- Delete: `Tests/DomainTests/Provider/UsageDisplayModeTests.swift`
- Delete: `Tests/DomainTests/Provider/PopoverContentHeightTests.swift`
- Modify: `Sources/Domain/Monitor/QuotaMonitor.swift` (delete `menuBarPercentageDisplay` / `menuBarDurationDisplay` / `menuBarLabel`, ~194–319)
- Modify: `Sources/Domain/Provider/UsageQuota.swift` — delete methods that take `UsageDisplayMode` (`displayPercent`, `displayProgressPercent`, `expectedProgressPercent`, `paceTickHelp`, and any helpers only used by those). Popover shows `percentRemaining` directly.
- Modify: `Tests/DomainTests/Monitor/QuotaMonitorTests.swift` (menu-bar sections ~150–494)
- Modify: `Tests/DomainTests/Monitor/ObservationRenderSyncTests.swift` (drop menuBarLabel integration ~154–196; keep generic sync tests)
- Modify: `Tests/DomainTests/Provider/UsageQuotaTests.swift` — remove tests for deleted display-mode methods
- Modify: `AppSettingsRepository` / `JSONSettingsRepository` / `AppSettings` — all `usageDisplayMode` + `menuBar*` APIs
- Modify: `SettingsView.swift` — delete `displayModeCard` and `MenuBar*ChoiceButton` helpers
- Modify: `MenuContentView.swift` / `QuotaCardView.swift` — drop `UsageDisplayMode` / `PopoverContentHeight` usage (literal `maxHeight` e.g. `500`; hardcode remaining % until Task 15 deletes these views)
- Modify: `StatusItemLabelDriver.swift` — static icon + lifecycle only
- Modify: `JSONSettingsRepositoryAppTests.swift` — remove menuBar/usageDisplayMode tests

- [ ] **Step 1: Grep**

```bash
grep -rln "MenuBarLabel\|MenuBarPercentageDisplay\|MenuBarDurationDisplay\|MenuBarStackedSize\|UsageDisplayMode\|PopoverContentHeight\|menuBarLabel\|menuBarPercentage\|menuBarDuration\|menuBarStacked\|StatusBarPercentageImageRenderer\|StatusBarStackedImageRenderer\|MenuBarProviderChoiceButton\|MenuBarQuotaChoiceButton" Sources/ Tests/
```

- [ ] **Step 2: Delete domain types + their unit tests**

```bash
git rm \
  Sources/Domain/Provider/MenuBarLabel.swift \
  Sources/Domain/Provider/MenuBarPercentageDisplay.swift \
  Sources/Domain/Provider/MenuBarDurationDisplay.swift \
  Sources/Domain/Provider/MenuBarStackedSize.swift \
  Sources/Domain/Provider/UsageDisplayMode.swift \
  Sources/Domain/Provider/PopoverContentHeight.swift \
  Tests/DomainTests/Provider/MenuBarDurationDisplayTests.swift \
  Tests/DomainTests/Provider/MenuBarStackedSizeTests.swift \
  Tests/DomainTests/Provider/UsageDisplayModeTests.swift \
  Tests/DomainTests/Provider/PopoverContentHeightTests.swift
```

- [ ] **Step 3: Strip `QuotaMonitor` menu-bar methods + `UsageQuota` display-mode API**

Delete `menuBarPercentageDisplay`, `menuBarDurationDisplay`, and `menuBarLabel` (approximately lines 194–319). Keep `overallStatus`, selection, monitoring, etc.

In `UsageQuota.swift`, delete every method whose signature takes `UsageDisplayMode` (at least `displayPercent(mode:)`, `displayProgressPercent(mode:)`, `expectedProgressPercent(mode:)`, `paceTickHelp(mode:)` around lines 136–246). Leave `percentRemaining`, `status`, `compactResetTime`, etc.

Delete corresponding tests in `QuotaMonitorTests.swift` and `UsageQuotaTests.swift`. In `ObservationRenderSyncTests.swift`, remove the test that calls `monitor.menuBarLabel(...)`; keep pure `ObservationRenderSync` unit tests.

In still-living App views (`MenuContentView`, `QuotaCardView`) that referenced `settings.usageDisplayMode`, switch to `quota.percentRemaining` / `quota.status` so they compile until Task 15 deletes them.

- [ ] **Step 4: Strip menu-bar settings atomically**

From `AppSettingsRepository.swift`, delete the Display section methods for:
- `usageDisplayMode` / `setUsageDisplayMode`
- all `menuBarPercentage*` / `menuBarDuration*` / `menuBarStacked*` / `menuBarSecondaryQuotaKey` getters/setters

Mirror-delete implementations in `JSONSettingsRepository.swift` and properties/init hydration in `AppSettings.swift`.

Remove matching tests from `JSONSettingsRepositoryAppTests.swift`.

- [ ] **Step 5: Strip Settings UI menu-bar controls**

Delete `displayModeCard` and everything it contains (display mode toggle, menu-bar percentage/duration toggles, provider/quota pickers, stacked controls, daily-usage toggle if still present). Delete helper types `DisplayModeButton`, `MenuBarProviderChoiceButton`, `MenuBarQuotaChoiceButton`, `MenuBarChoiceButton` at the bottom of `SettingsView.swift`.

Remove `displayModeCard` from the settings body list.

- [ ] **Step 6: Gut `StatusItemLabelDriver` to static icon + lifecycle**

Replace the file's label-rendering half with a static SF Symbol image; keep `RefreshLoopKey`, `startMonitoringLifecycle`, `restartMonitoring`, KVO image-wipe guard, and `reassertPresentation`. Concretely:

- Remove `LabelContent`, `labelSync`, `currentLabelContent`, `compose`, `StatusBarPercentageImageRenderer`, `StatusBarStackedImageRenderer`, session/theme-dependent drawing
- In `attach(_:)`, create one `NSImage` via `NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "ClaudeBar")` (or template-rendered once), assign to `button.image`, and keep the KVO restore observer so SwiftUI wipes don't blank the icon
- `restartMonitoring`: drop `self.labelSync?.renderNow()` inside the stream consumer (stream can be consumed with an empty loop body, or the Task can simply keep the stream alive — `for await _ in stream { }` is enough; polling still runs inside `QuotaMonitor`)
- `backgroundRefreshProviderIds`: always return `nil` (refresh selected provider only — menu-bar provider narrowing is gone)
- Remove wakeObserver if it only existed to repaint live pixels; optional keep as `reassertPresentation()` on wake for the static image — either is fine

Do **not** rename the type yet (Task 12).

- [ ] **Step 7: Temporary `MenuContentView` height**

Replace `contentMaxHeight` / `PopoverContentHeight` with a literal so the file still compiles:

```swift
    private var contentMaxHeight: CGFloat { 500 }
```

Bounce fix comes in Task 15.

- [ ] **Step 8: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove menu-bar live label pipeline

Drops MenuBar* domain types, settings, and Settings pickers; status item is static.
EOF
)"
```

---

## Task 9: Delete CLI + Christmas + System themes

Leaves Dark + Light only. Trim `ThemeMode`, `ThemeRegistry`, seasonal Christmas auto-switch in `AppSettings`, and theme-environment cases.

**Files:**
- Delete: `Sources/App/Theme/Themes/CLITheme.swift`
- Delete: `Sources/App/Theme/Themes/ChristmasTheme.swift`
- Modify: `Sources/App/Theme/ThemeRegistry.swift` (`registerBuiltInThemes` + delete `SystemTheme` struct at bottom)
- Modify: `Sources/App/Views/Theme.swift` (`ThemeMode` enum — keep only `light`/`dark`)
- Modify: `Sources/App/Theme/ThemeEnvironment.swift` (`effectiveColorScheme`)
- Modify: `Sources/App/Settings/AppSettings.swift` (delete `applySeasonalTheme` / `isChristmasPeriod`; default orphaned modes)
- Modify: `Sources/Infrastructure/Storage/JSONSettingsRepository.swift` (`themeMode()` default `"system"` → `"dark"`)
- Modify: any remaining previews referencing CLI/Christmas (`ClaudeBarApp` StatusBarIcon preview if still present)

- [ ] **Step 1: Grep**

```bash
grep -rln "CLITheme\|ChristmasTheme\|SystemTheme\|ThemeMode\.cli\|ThemeMode\.christmas\|ThemeMode\.system\|\"cli\"\|\"christmas\"\|isChristmasPeriod\|applySeasonalTheme\|ChristmasBackgroundOrbs\|snowfall\|statusBarIconName" Sources/ Tests/
```

- [ ] **Step 2: Delete theme files**

```bash
git rm \
  Sources/App/Theme/Themes/CLITheme.swift \
  Sources/App/Theme/Themes/ChristmasTheme.swift
```

- [ ] **Step 3: Trim `ThemeRegistry.registerBuiltInThemes`**

```swift
    private func registerBuiltInThemes() {
        register(LightTheme())
        register(DarkTheme())
    }
```

Delete the entire `SystemTheme` struct (lines 135–172). Simplify `resolveTheme` to ignore `"system"` specially (unknown ids → `defaultTheme`):

```swift
    public func resolveTheme(for id: String, systemColorScheme: ColorScheme) -> any AppThemeProvider {
        _ = systemColorScheme
        return themes[id] ?? defaultTheme
    }
```

(Or keep a soft map: if `id == "system"`, pick dark/light from `systemColorScheme` — but design says 2 themes only and no System option in Settings. Prefer hard fallback to Dark for unknown ids including `"system"`.)

- [ ] **Step 4: Collapse `ThemeMode`**

In `Theme.swift`:

```swift
enum ThemeMode: String, CaseIterable {
    case light
    case dark

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
}
```

Delete `isChristmas` / `isCLI`. Update `ThemeModeKey.defaultValue` to `.dark`.

- [ ] **Step 5: Trim `ThemeEnvironment.effectiveColorScheme`**

```swift
    private var effectiveColorScheme: ColorScheme {
        switch ThemeMode(rawValue: themeModeId) {
        case .light: return .light
        case .dark, .none: return .dark
        }
    }
```

- [ ] **Step 6: Strip seasonal theme from `AppSettings`**

Delete `isChristmasPeriod`, `applySeasonalTheme`, and the `applySeasonalTheme()` call in `init`. Change `JSONSettingsRepository.themeMode()` default from `"system"` to `"dark"`.

- [ ] **Step 7: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: keep only Dark and Light themes

Removes CLI, Christmas, and System themes plus seasonal auto-switch.
EOF
)"
```

---

## Task 10: Delete Claude API budget settings card

Removes the dollar-budget Settings UI and `app.claudeApiBudget*` keys. Keep domain `BudgetStatus` / `CostUsage.budgetStatus(budget:)` for server-provided caps (extra usage). Strip `CostStatCard`'s `externalBudget` path.

**Files:**
- Modify: `Sources/App/Views/Settings/ClaudeConfigCard.swift` (delete `budgetCard` and related state; keep auth `configCard`)
- Modify: `AppSettingsRepository` / `JSONSettingsRepository` / `AppSettings` — `claudeApiBudgetEnabled` / `claudeApiBudget`
- Modify: `Sources/App/Views/MenuContentView.swift:605-607` (stop passing settings budget)
- Modify: `Sources/App/Views/CostStatCard.swift` (drop `externalBudget`)
- Modify: `JSONSettingsRepositoryAppTests.swift` budget tests

- [ ] **Step 1: Grep**

```bash
grep -rn "claudeApiBudget\|budgetCard\|externalBudget\|Claude API Budget\|budgetInput" Sources/ Tests/
```

- [ ] **Step 2: Strip `ClaudeConfigCard` to auth-only**

Delete `@State claudeBudgetExpanded`, `budgetInput`, `budgetCard`, `budgetHeader`, `budgetForm`, and the `budgetCard` from `body`. Keep `configCard` showing OAuth credential status. `body` becomes just `configCard`.

- [ ] **Step 3: Strip settings keys atomically**

Remove from protocol, JSON repo, AppSettings, and tests:
- `claudeApiBudgetEnabled` / `setClaudeApiBudgetEnabled`
- `claudeApiBudget` / `setClaudeApiBudget`

- [ ] **Step 4: Strip `CostStatCard` external budget**

Change initializer to `init(costUsage: CostUsage, delay: Double = 0)`. Remove `externalBudget`. `effectiveBudget` becomes:

```swift
    private var effectiveBudget: Decimal? {
        costUsage.budget
    }
```

Update `MenuContentView` call site from:

```swift
                let budget = settings.claudeApiBudgetEnabled ? settings.claudeApiBudget : nil
                CostStatCard(costUsage: costUsage, budget: budget, delay: ...)
```

to:

```swift
                CostStatCard(costUsage: costUsage, delay: ...)
```

- [ ] **Step 5: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: remove Claude API dollar-budget settings

Keeps CostUsage server caps; drops user-configured monthly budget UI.
EOF
)"
```

---

## Task 11: Strip leftover Settings settings (burn rate, overview, beta, launch-at-login)

Design Settings keep only provider toggles, quota alerts, refresh interval (+ theme picker in rebuild). Clear dead settings now so Task 17 starts from a small surface.

**Files:**
- Modify: `AppSettingsRepository` / `JSONSettingsRepository` / `AppSettings`
- Modify: `SettingsView.swift` — delete `overviewModeCard`, `burnRateCard`, `launchAtLoginCard`, `logsCard`, `aboutCard` (and body references)
- Modify: `MenuContentView.swift` — remove `overviewModeEnabled` branches (always show single-provider list path for now; Task 15 rebuilds)
- Modify: tests in `JSONSettingsRepositoryAppTests.swift`
- Check: `QuotaCardView.swift` burn-rate usage — if `QuotaCardView` still used, stop reading burn-rate settings (use absolute `quota.status`)

- [ ] **Step 1: Grep**

```bash
grep -rln "burnRateWarning\|burnRateThreshold\|overviewMode\|receiveBetaUpdates\|launchAtLogin\|betaUpdatesSettingChanged" Sources/ Tests/
```

- [ ] **Step 2: Remove settings APIs + UI cards + MenuContentView overview branches**

Atomic protocol/repo/AppSettings deletion for:
- `burnRateWarningEnabled` / `burnRateThreshold`
- `overviewModeEnabled`
- `receiveBetaUpdates`

Remove `launchAtLogin` from `AppSettings` (SMAppService-backed; not in JSON). Delete the corresponding Settings cards from the body.

In views that called `paceAwareStatus(burnRateThreshold:)`, use `quota.status` / `snapshot.overallStatus` instead.

- [ ] **Step 3: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: strip burn-rate, overview, beta, and launch-at-login settings

Narrows settings surface ahead of the Settings UI rebuild.
EOF
)"
```

---

# Sub-phase 3b — Rebuild

---

## Task 12: Rename `StatusItemLabelDriver` → `StatusBarIconDriver`

**Files:**
- Rename: `Sources/App/StatusItemLabelDriver.swift` → `Sources/App/StatusBarIconDriver.swift`
- Modify: `Sources/App/ClaudeBarApp.swift` (type name + comments)

**Interfaces:**
- Produces: `@MainActor final class StatusBarIconDriver` with `init(monitor:settings:)`, `attach(_:)`, `reassertPresentation()`, `startMonitoringLifecycle()`

- [ ] **Step 1: Rename file and type**

```bash
git mv Sources/App/StatusItemLabelDriver.swift Sources/App/StatusBarIconDriver.swift
```

Inside the file, rename `StatusItemLabelDriver` → `StatusBarIconDriver`. Update the doc comment to state: static icon + sleep-safe background-refresh-loop restart only (issue #192).

- [ ] **Step 2: Update `ClaudeBarApp` references**

Replace property type, initializer type, and comments that say `StatusItemLabelDriver`.

- [ ] **Step 3: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: rename StatusItemLabelDriver to StatusBarIconDriver

Matches the static-icon + refresh-lifecycle responsibility.
EOF
)"
```

---

## Task 13: Rewrite `DarkTheme` to pure black (mockup palette)

**Files:**
- Modify: `Sources/App/Theme/Themes/DarkTheme.swift`
- Optionally adjust `BaseTheme` status defaults in `AppThemeProvider.swift` if Dark should own the mockup status colors directly

**Design palette (from spec):**
- Background `#000000`
- Text `#e8e8e8` / `#888888` / `#666666`
- Status `#22c55e` / `#eab308` / `#ef4444` (critical + depleted)

- [ ] **Step 1: Replace `DarkTheme` implementation**

```swift
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
```

Spacing/radii are intentionally light-touch — mockups are directional.

- [ ] **Step 2: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(theme): rewrite DarkTheme to pure-black mockup palette

Replaces purple-pink glassmorphism with #000 background and status greens/yellows/reds.
EOF
)"
```

---

## Task 14: Review `LightTheme` + finish 2-theme registry polish

**Files:**
- Modify: `Sources/App/Theme/Themes/LightTheme.swift` (read through; only change if contrast/status colors clearly broken against the new popover)
- Modify: `Sources/App/Theme/ThemeRegistry.swift` (confirm only 2 registrations from Task 9)
- Modify: `Sources/App/Theme/AppThemeProvider.swift` — if `shareGradient` is now unused, leave it (protocol requirement) unless you want a follow-on protocol slim

- [ ] **Step 1: Read `LightTheme.swift` end-to-end**

Confirm text/status contrast is acceptable on light backgrounds. Only edit if something is clearly unreadable; do not redesign.

- [ ] **Step 2: Confirm registry**

`registerBuiltInThemes` must be exactly Light + Dark. `allThemes.count == 2`.

- [ ] **Step 3: VERIFY + commit** (even if LightTheme is unchanged, commit registry comment cleanup if any)

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(theme): confirm two-theme registry after Dark rewrite

LightTheme reviewed; registry remains Light + Dark only.
EOF
)"
```

If there is truly no diff, skip the commit and note it in the task checkbox.

---

## Task 15: Build popover views (`QuotaBucketRow`, `ProviderQuotaSection`, `PopoverView`)

Replaces `MenuContentView`. Pin window height (drop vertical `.fixedSize`); scroll absorbs content growth — bounce-bug fix.

**Files:**
- Create: `Sources/App/Views/Popover/QuotaBucketRow.swift`
- Create: `Sources/App/Views/Popover/ProviderQuotaSection.swift`
- Create: `Sources/App/Views/Popover/PopoverView.swift`
- Modify: `Sources/App/ClaudeBarApp.swift` (swap `MenuContentView` → `PopoverView`)
- Modify: `Sources/App/Views/CostStatCard.swift` (restyle to match list language — no progress bar required)
- Delete (once unused): `MenuContentView.swift`, `QuotaCardView.swift`, `ProviderSectionView.swift`, `Session*` already gone, `ComponentPreviews.swift` if broken, etc. — only after grep shows zero references
- No new App-layer unit tests (project convention)

**Interfaces:**
- `QuotaBucketRow(quota: UsageQuota)` — label, colored %, reset time
- `ProviderQuotaSection(provider: any AIProvider)` — name header + rows + optional `CostStatCard`
- `PopoverView(monitor: QuotaMonitor, quotaAlerter: QuotaAlerter)` — settings swap, refresh, provider sections for enabled providers

- [ ] **Step 1: Create `QuotaBucketRow.swift`**

```swift
import SwiftUI
import Domain

/// Single quota bucket row: name, colored percentage, reset time.
struct QuotaBucketRow: View {
    let quota: UsageQuota
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(quota.quotaType.displayName)
                .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 8)

            Text(percentageText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.statusColor(for: quota.status))

            Text(resetText)
                .font(.system(size: 12, weight: .regular, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
    }

    private var percentageText: String {
        // Show remaining percent to match prior default UsageDisplayMode.remaining.
        "\(Int(quota.percentRemaining.rounded()))%"
    }

    private var resetText: String {
        quota.compactResetTime ?? "—"
    }
}
```

Confirm `AppThemeProvider.statusColor(for:)` exists (it does via protocol extension in `AppThemeProvider.swift`). Confirm `UsageQuota.percentRemaining` exists — if the property name differs, use the actual remaining-percent API on `UsageQuota` (read the file; common names: `percentRemaining`, `remainingPercent`).

- [ ] **Step 2: Create `ProviderQuotaSection.swift`**

```swift
import SwiftUI
import Domain

/// Provider header + indented quota bucket rows + optional cost card.
struct ProviderQuotaSection: View {
    let provider: any AIProvider
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.name)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            if let snapshot = provider.snapshot {
                // UsageQuota is not Identifiable — key by quotaType (Hashable).
                ForEach(snapshot.quotas, id: \.quotaType) { quota in
                    QuotaBucketRow(quota: quota)
                }

                if let costUsage = snapshot.costUsage {
                    CostStatCard(costUsage: costUsage)
                        .padding(.top, 4)
                }
            } else if provider.isSyncing {
                Text("Refreshing…")
                    .font(.system(size: 12, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.leading, 12)
            } else if let error = provider.lastError {
                Text(error.localizedDescription)
                    .font(.system(size: 12, design: theme.fontDesign))
                    .foregroundStyle(theme.statusWarning)
                    .padding(.leading, 12)
            } else {
                Text("No data yet")
                    .font(.system(size: 12, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.leading, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: Create `PopoverView.swift`**

Key bounce-bug requirements: **fixed height**, **no** `.fixedSize(horizontal: false, vertical: true)`, scroll inside.

```swift
import SwiftUI
import Domain
import Infrastructure

/// Main menu-bar popover content (replaces MenuContentView).
struct PopoverView: View {
    let monitor: QuotaMonitor
    let quotaAlerter: QuotaAlerter

    @Environment(\.appTheme) private var theme
    @State private var showSettings = false
    @State private var settings = AppSettings.shared
    @State private var hasRequestedNotificationPermission = false

    /// Pinned window height — content scrolls inside (popover bounce fix).
    private let popoverHeight: CGFloat = 420

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            if showSettings {
                SettingsContentView(showSettings: $showSettings, monitor: monitor)
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(monitor.enabledProviders, id: \.id) { provider in
                                ProviderQuotaSection(provider: provider)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }

                    Divider().overlay(theme.glassBorder)

                    footer
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
        }
        .frame(width: 360, height: popoverHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
            .task {
            if !hasRequestedNotificationPermission {
                hasRequestedNotificationPermission = true
                // Task 16 adds settings.quotaAlertsEnabled; until then always request.
                _ = await quotaAlerter.requestPermission()
            }
            await refreshAll()
        }
    }

    private var header: some View {
        HStack {
            Text("ClaudeBar")
                .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button {
                Task { await refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
    }

    private var footer: some View {
        HStack {
            Text(syncLabel)
                .font(.system(size: 11, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
    }

    private var syncLabel: String {
        if monitor.enabledProviders.contains(where: \.isSyncing) {
            return "Refreshing…"
        }
        return settings.refreshInterval.label
    }

    private func refreshAll() async {
        for provider in monitor.enabledProviders {
            _ = try? await provider.refresh()
        }
    }
}
```

Note: `QuotaMonitor.enabledProviders` exists at `QuotaMonitor.swift:165`. Wire permission gating to `settings.quotaAlertsEnabled` in Task 16 (this task always requests permission).

Check `refresh()` vs `refresh(_ kind:)` on providers — call the public API that exists after Phase 2 (`refresh()` is fine).

- [ ] **Step 4: Restyle `CostStatCard` lightly**

Remove progress-bar chrome if still present; show dollar amount + optional server cap text using theme text/status colors. Keep file under ~200 lines.

- [ ] **Step 5: Wire `ClaudeBarApp` to `PopoverView`**

```swift
                PopoverView(monitor: monitor, quotaAlerter: quotaAlerter)
                    .appThemeProvider(themeModeId: settings.themeMode)
```

- [ ] **Step 6: Delete orphaned old views**

```bash
grep -rln "MenuContentView\|QuotaCardView\|ProviderSectionView\|ProviderPill\|WrappedStatCard\|ComponentPreviews" Sources/
```

`git rm` every file with zero remaining references (at least `MenuContentView.swift`; likely `QuotaCardView.swift`, `ProviderSectionView.swift`, `ComponentPreviews.swift` if unused).

- [ ] **Step 7: VERIFY + commit**

VERIFY. Manually launch once if possible and confirm: pinned height, scroll works, no bounce when data loads.

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(ui): replace MenuContentView with grouped-header PopoverView

Pinned popover height with internal scroll; quota buckets as indented rows.
EOF
)"
```

---

## Task 16: Add `quotaAlertsEnabled` + rebuild Settings

Trimmed Settings: provider enable/disable + credential status, quota-alert toggle, refresh interval, Dark/Light theme picker.

**Files:**
- Modify: `Sources/Domain/Settings/AppSettingsRepository.swift` — add `quotaAlertsEnabled` APIs; ensure burn-rate/overview/menu-bar/budget already gone
- Modify: `Sources/Infrastructure/Storage/JSONSettingsRepository.swift` — `app.quotaAlertsEnabled` default `true`
- Modify: `Sources/App/Settings/AppSettings.swift` — observable property
- Modify: `Sources/Infrastructure/Notifications/NotificationAlerter.swift` — gate `alert(...)` on an injected `isEnabled` closure **or** check via a new protocol method; simplest approach below
- Rewrite: `Sources/App/Views/SettingsView.swift` (replace monolith with a short `SettingsContentView`)
- Keep/trim: `ClaudeConfigCard.swift`, `CodexConfigCard.swift`
- Test: add round-trip tests in `JSONSettingsRepositoryAppTests.swift` for `quotaAlertsEnabled`

**Recommended alert gating (keeps Domain free of AppSettings):**

Change `NotificationAlerter` to:

```swift
public final class NotificationAlerter: QuotaAlerter, @unchecked Sendable {
    private let alertSender: AlertSender
    private let isEnabled: @Sendable () -> Bool

    public init(isEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.alertSender = SystemAlertSender()
        self.isEnabled = isEnabled
    }

    public func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async {
        guard isEnabled() else { return }
        // ... existing body ...
    }
}
```

In `ClaudeBarApp.init`:

```swift
    private let quotaAlerter = NotificationAlerter {
        // AppSettings.shared is MainActor; NotificationAlerter may call from async context.
        // Prefer reading the JSON repo directly for Sendable safety:
        JSONSettingsRepository.shared.quotaAlertsEnabled()
    }
```

(If actor-isolation fights you, store the enabled flag on a small `Sendable` box updated from `AppSettings.didSet`, or make `alert` check a `OSAllocatedUnfairLock<Bool>`. Pick the approach that compiles cleanly under Swift 6.)

- [ ] **Step 1: Add failing settings tests**

In `JSONSettingsRepositoryAppTests.swift`:

```swift
    @Test
    func `quotaAlertsEnabled defaults to true`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        #expect(repo.quotaAlertsEnabled() == true)
    }

    @Test
    func `setQuotaAlertsEnabled persists value`() {
        let (repo1, dir) = makeRepository()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("settings.json")
        repo1.setQuotaAlertsEnabled(false)
        let repo2 = JSONSettingsRepository(store: JSONSettingsStore(fileURL: fileURL))
        #expect(repo2.quotaAlertsEnabled() == false)
    }
```

Match the existing `makeRepository()` / `cleanup(_:)` helpers already in `JSONSettingsRepositoryAppTests.swift` (lines 10–17).

- [ ] **Step 2: Run tests — expect compile failure** (method missing)

```bash
rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open && \
  xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:InfrastructureTests/JSONSettingsRepositoryAppTests
```

- [ ] **Step 3: Implement settings APIs**

Protocol:

```swift
    // MARK: - Quota Alerts

    func quotaAlertsEnabled() -> Bool
    func setQuotaAlertsEnabled(_ enabled: Bool)
```

JSON:

```swift
    public func quotaAlertsEnabled() -> Bool {
        store.read(key: "app.quotaAlertsEnabled") ?? true
    }

    public func setQuotaAlertsEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.quotaAlertsEnabled")
    }
```

`AppSettings` property with `didSet` → repository, hydrated in `init`.

- [ ] **Step 4: Gate `NotificationAlerter` + wire `ClaudeBarApp`**

As above.

- [ ] **Step 5: Rewrite `SettingsContentView`**

Replace the 1445-line file with a focused view (~200–300 lines) containing:
1. Theme picker (Light / Dark only) — `ForEach(ThemeRegistry.shared.allThemes)`
2. Providers list — toggle `provider.isEnabled` for each of `monitor.allProviders`; under Claude/Codex when enabled, show `ClaudeConfigCard` / `CodexConfigCard`
3. Toggle bound to `$settings.quotaAlertsEnabled` labeled e.g. "Quota alerts"
4. `Picker` bound to `$settings.refreshInterval` (reuse existing `RefreshInterval` cases)
5. Back/Done button setting `showSettings = false`

Delete leftover cards (theme import, display mode, hooks, burn rate, logs, about, launch at login, overview).

Also update `PopoverView`'s `.task` permission gate to:

```swift
                if settings.quotaAlertsEnabled {
                    _ = await quotaAlerter.requestPermission()
                }
```

- [ ] **Step 6: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(settings): trim Settings UI and add quotaAlertsEnabled

Providers, theme, refresh interval, and gated quota-threshold notifications.
EOF
)"
```

---

## Task 17: Final App cleanup + orphan sweep

**Files:** anything still referencing cut features; dead helpers in `Theme.swift` / `ProviderVisualIdentity` if unused; `AppLog.hooks` if still present.

- [ ] **Step 1: Orphan grep**

```bash
grep -rln "MenuContentView\|SessionMonitor\|HookInstaller\|ExtensionRegistry\|ClaudePass\|DailyUsage\|CLITheme\|ChristmasTheme\|menuBarLabel\|UsageDisplayMode\|customCardURL\|showDailyUsageCards\|claudeApiBudget\|overviewMode\|burnRateWarning\|ThemeImport\|ImportedTerminal\|LiveActivity\|AccountPicker\|SharePass\|PopoverContentHeight\|StatusItemLabelDriver" Sources/ Tests/ || true
```

Expected: no matches (or only historical comments/docs outside `Sources/`). Fix any remaining hits.

- [ ] **Step 2: Optional — slim `Theme.swift`**

If the legacy `AppTheme` static palette / glass modifiers are unused, delete dead code. Don't spend more than ~15 minutes; leave if tightly coupled to remaining modifiers.

- [ ] **Step 3: VERIFY + commit**

VERIFY.

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: sweep orphans after Phase 3 UI rewrite

Removes leftover references to deleted subsystems.
EOF
)"
```

---

## Task 18: Manual verification checklist (no code)

- [ ] **Step 1: Launch the app** (`tuist generate && open ClaudeBar.xcworkspace`, run ClaudeBar).

- [ ] **Step 2: Popover**
  - Grouped provider headers with indented quota rows
  - Colored % (green/yellow/red) + reset times; no progress bars on quota rows
  - Cost cards for Claude/Codex when `costUsage` present
  - Window height stays fixed when data loads / providers refresh (no bounce)
  - Internal scroll works if content exceeds height

- [ ] **Step 3: Menu-bar icon**
  - Always the same glyph/color regardless of quota status
  - Put Mac to sleep and wake; background refresh still runs (check logs / quota updates after interval)

- [ ] **Step 4: Settings**
  - Enable/disable providers; Claude/Codex credential status visible
  - Quota alerts toggle stops/starts desktop alerts
  - Refresh interval changes restart background loop
  - Theme switches between Dark (pure black) and Light only

- [ ] **Step 5: Commit nothing** unless you found and fixed bugs (then fix in a focused follow-up commit).

---

## Done criteria

- [ ] Every cut feature from the design spec's "What's Cut" table is gone across Domain / Infrastructure / App (and orphaned tests deleted).
- [ ] `Sources/App` popover is the new grouped-header list (`PopoverView` / `ProviderQuotaSection` / `QuotaBucketRow`), not `MenuContentView`.
- [ ] Menu-bar icon is static via `StatusBarIconDriver`, still restarting background refresh after sleep (issue #192).
- [ ] Settings shows only providers + credential status, quota alerts, refresh interval, and Dark/Light theme.
- [ ] Themes: Dark (pure black mockup palette) + Light only; CLI/Christmas/System/import gone.
- [ ] `JSONSettingsRepository` still compiles and only implements surviving settings protocols.
- [ ] Full suite green via the Global Constraints `xcodebuild build` + `xcodebuild test` sequence on a freshly generated workspace.
- [ ] Manual checks in Task 18 pass (popover bounce fixed; sleep/wake refresh OK).
