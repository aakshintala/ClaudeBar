# Strip ClaudeBar to Four Providers — Deletion Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete 12 of the 16 AI providers (keep Claude, Codex, Cursor, OpenCode), shed their dependencies, and drop the release/auto-update machinery — leaving a smaller tree that still builds green, passes tests, and runs as a personal (unsigned/ad-hoc) menu-bar app.

**Architecture:** Compiler-and-test-driven deletion. Each provider is self-contained under `Sources/Domain/Provider/<X>/` + `Sources/Infrastructure/<X>/`, but is *enumerated* in a fixed set of shared files (registration array, settings repos, notification alerter, visual identity, theme, plus their test analogues). Each task deletes a provider (or cohort), removes its entries from every enumeration point, deletes its tests, then gates on `tuist build` + `tuist test` before committing. The kept Domain/Infrastructure code (4 probes, provider classes, `QuotaMonitor`, value types, storage, network, logging) is never moved — only trimmed where it enumerates providers.

**Tech Stack:** Swift 6, Tuist, XCTest, Mockable. macOS 15 deployment target.

## Global Constraints

- **Keep exactly 4 providers:** Claude, Codex, Cursor, OpenCode. Delete: Alibaba, AmpCode, Antigravity, Bedrock, Copilot, Gemini, Kimi, Kiro, MiniMax, Mistral, Omp, Zai.
- **Green gate after every task:** `tuist build` succeeds AND `tuist test` passes before committing. No task commits red.
- **This is a fork.** Any deleted provider is recoverable from upstream: `git checkout <upstream-remote>/main -- <path>`. Nothing is lost permanently.
- **Symbol-level search, not substring.** When locating enumeration entries, match whole identifiers (e.g. `\bOmp\b`, `OmpProvider`, `"omp"`) — case-insensitive substring search produces false positives ("Component", "comparison").
- **Personal build only.** No signing/notarization/release. Local `tuist build` with existing ad-hoc `CODE_SIGN_IDENTITY = "-"` is the only build path.
- **Out of scope for this plan** (separate follow-on plans): Phase 2 — Claude CLI→API cutover + `SwiftTerm`/`ClaudeUsageProbe`/`TerminalRenderer` removal. Phase 3 — `Sources/App/` UI rewrite (needs a brainstorm first).

### Enumeration points (the files every provider deletion must touch)

**Domain/Infrastructure (kept layer — trim these):**
- `Sources/App/ClaudeBarApp.swift` — provider registration array (`AIProviders(providers: [...])`, lines ~63–119)
- `Sources/Domain/Provider/ProviderSettingsRepository.swift` — per-provider settings sub-protocols
- `Sources/Infrastructure/Storage/JSONSettingsRepository.swift` — conformances + method impls
- `Sources/Infrastructure/Storage/UserDefaultsProviderSettingsRepository.swift` — conformances + method impls
- `Sources/Infrastructure/Notifications/NotificationAlerter.swift` — per-provider alert logic
- `Sources/Domain/Provider/UsageSnapshot.swift` — Bedrock only
- `Sources/Domain/Provider/AIProvider.swift` — Gemini reference (likely doc/comment)

**App (throwaway layer, but must compile until Phase 3 — trim these):**
- `Sources/App/Settings/AppSettings.swift` — typed provider accessors
- `Sources/App/Views/SettingsView.swift` — config-card wiring
- `Sources/App/Views/Settings/<X>ConfigCard.swift` — delete per config provider
- `Sources/App/Views/ProviderVisualIdentity.swift` — icon/color map
- `Sources/App/Views/ProviderIcons.swift` — Gemini reference
- `Sources/App/Views/ComponentPreviews.swift` — Gemini preview
- `Sources/App/Views/Theme.swift` — per-provider theming
- `Sources/App/Views/MenuContentView.swift` — Bedrock reference
- `Sources/App/Resources/<X>Icon.*` + `Assets.xcassets/<X>Icon.imageset/` — delete per provider

**Tests (trim shared, delete per-provider dirs):**
- Delete wholesale: `Tests/DomainTests/Provider/<X>/`, `Tests/InfrastructureTests/<X>/`, and provider-specific `Tests/AcceptanceTests/<X>ConfigSpec.swift`.
- Trim (enumerate providers): `Tests/AcceptanceTests/ActionBarSpec.swift`, `Tests/InfrastructureTests/Notifications/NotificationAlerterTests.swift`, `Tests/InfrastructureTests/Settings/JSONSettingsRepositoryProviderTests.swift`, `Tests/InfrastructureTests/UserDefaultsProviderSettingsRepositoryTests.swift`, `Tests/DomainTests/TestHelpers/MockRepositoryFactory.swift`, `Tests/DomainTests/Provider/UsageSnapshotTests.swift`, `Tests/DomainTests/Provider/UsageQuotaTests.swift`, `Tests/DomainTests/Provider/ProbeErrorTests.swift`.

### Per-provider source inventory (exact `git rm` targets)

| Provider | Domain + Infrastructure files | ConfigCard | Icon | Settings sub-protocol? |
|---|---|---|---|---|
| AmpCode | `Domain/Provider/AmpCode/AmpCodeProvider.swift`, `Infrastructure/AmpCode/AmpCodeUsageProbe.swift` | — | `Assets.xcassets/AmpCodeIcon.imageset/` | base |
| Antigravity | `Domain/Provider/Antigravity/AntigravityProvider.swift`, `Infrastructure/Antigravity/AntigravityUsageProbe.swift` | — | `Resources/Antigravity.svg` | base |
| Kiro | `Domain/Provider/Kiro/KiroProvider.swift`, `Infrastructure/Kiro/KiroUsageProbe.swift`, `Infrastructure/Kiro/SimpleCLIExecutor.swift` | — | `Resources/KiroIcon.svg` | base |
| Mistral | `Domain/Provider/Mistral/MistralProvider.swift`, `Infrastructure/Mistral/MistralUsageProbe.swift`, `Infrastructure/Mistral/VibeSessionLogAnalyzer.swift` | — | — | base |
| Omp | `Domain/Provider/Omp/OmpProvider.swift`, `Infrastructure/Omp/OmpUsageProbe.swift` | — | — | base |
| Gemini | `Domain/Provider/Gemini/GeminiProvider.swift`, `Infrastructure/Gemini/{GeminiProjectRepository,GeminiAPIProbe,GeminiUsageProbe,GeminiProject,GeminiCLIProbe}.swift` | — | `Resources/GeminiIcon.svg` | base |
| Zai | `Domain/Provider/Zai/ZaiProvider.swift`, `Infrastructure/Zai/ZaiUsageProbe.swift` | `Views/Settings/ZaiConfigCard.swift` | `Resources/ZaiIcon.svg` | `ZaiSettingsRepository` |
| Copilot | `Domain/Provider/Copilot/{CopilotProvider,CopilotProbeMode,MonthlyResetDate}.swift`, `Infrastructure/Copilot/{CopilotUsageProbe,CopilotInternalAPIProbe}.swift` | `Views/Settings/CopilotConfigCard.swift` | `Resources/CopilotIcon.png` | `CopilotSettingsRepository` |
| Kimi | `Domain/Provider/Kimi/{KimiProbeMode,KimiProvider}.swift`, `Infrastructure/Kimi/{KimiUsageProbe,KimiTokenProvider,KimiCLIUsageProbe}.swift` | `Views/Settings/KimiConfigCard.swift` | `Assets.xcassets/KimiIcon.imageset/` | `KimiSettingsRepository` |
| MiniMax | `Domain/Provider/MiniMax/{MiniMaxRegion,MiniMaxProvider}.swift`, `Infrastructure/MiniMax/MiniMaxUsageProbe.swift` | `Views/Settings/MiniMaxConfigCard.swift` | `Resources/MiniMaxIcon.svg` | `MiniMaxSettingsRepository` |
| Alibaba | `Domain/Provider/Alibaba/{AlibabaCookieProviding,AlibabaRegion,AlibabaProvider}.swift`, `Infrastructure/Alibaba/{AlibabaBrowserCookieProvider,AlibabaUsageProbe}.swift` | `Views/Settings/AlibabaConfigCard.swift` | — | `AlibabaSettingsRepository` |
| Bedrock | `Domain/Provider/Bedrock/{BedrockProvider,BedrockModels}.swift`, `Infrastructure/Bedrock/{BedrockUsageProbe,BedrockCloudWatchClient,BedrockPricingService}.swift` | `Views/Settings/BedrockConfigCard.swift` | `Resources/BedrockIcon.svg` | `BedrockSettingsRepository` |

(All paths relative to `Sources/`. Icons also referenced in `Assets.xcassets`; delete both the source file and any matching `.imageset` dir.)

---

## Task 0: Branch + baseline green

**Files:** none (setup only)

- [ ] **Step 1: Create the working branch off `main`**

```bash
git fetch origin
git switch -c refactor/strip-to-four-providers origin/main
```

- [ ] **Step 2: Establish a green baseline**

Run: `tuist install && tuist generate && tuist build`
Expected: BUILD SUCCEEDED

Run: `tuist test`
Expected: all tests pass. Record the pass count — later tasks reduce it as provider tests are deleted; it must never go from green to red mid-task.

- [ ] **Step 3: Commit nothing** — baseline only. Proceed.

---

## Task 1: Delete the 5 base-settings providers (AmpCode, Antigravity, Kiro, Mistral, Omp)

These use the base `ProviderSettingsRepository` (no sub-protocol, no ConfigCard, no `AppSettings` accessor), so coupling is limited to the registration array, `NotificationAlerter`, `ProviderVisualIdentity`, `Theme`, and tests.

**Files:**
- Delete: the Domain/Infrastructure files, icons, and test dirs for AmpCode, Antigravity, Kiro, Mistral, Omp (see inventory table).
- Modify: `Sources/App/ClaudeBarApp.swift`, `Sources/Infrastructure/Notifications/NotificationAlerter.swift`, `Sources/App/Views/ProviderVisualIdentity.swift`, `Sources/App/Views/Theme.swift`, and the shared test files listed in Global Constraints.

- [ ] **Step 1: Verify `SimpleCLIExecutor` is Kiro-only before deleting it**

Run: `grep -rn "SimpleCLIExecutor" Sources/ Tests/ | grep -v "Infrastructure/Kiro/"`
Expected: only a test file `Tests/InfrastructureTests/**/SimpleCLIExecutorTests.swift` (delete it too) and nothing in kept source. If any kept `Sources/` file uses it, STOP and move `SimpleCLIExecutor.swift` to `Sources/Infrastructure/Shared/` instead of deleting it, then continue.

- [ ] **Step 2: Delete source, icons, and test dirs**

```bash
git rm -r \
  Sources/Domain/Provider/AmpCode Sources/Infrastructure/AmpCode \
  Sources/Domain/Provider/Antigravity Sources/Infrastructure/Antigravity \
  Sources/Domain/Provider/Kiro Sources/Infrastructure/Kiro \
  Sources/Domain/Provider/Mistral Sources/Infrastructure/Mistral \
  Sources/Domain/Provider/Omp Sources/Infrastructure/Omp \
  Sources/App/Resources/Antigravity.svg Sources/App/Resources/KiroIcon.svg \
  Sources/App/Resources/Assets.xcassets/AmpCodeIcon.imageset \
  Tests/DomainTests/Provider/Antigravity Tests/DomainTests/Provider/Omp \
  Tests/InfrastructureTests/AmpCode Tests/InfrastructureTests/Antigravity \
  Tests/InfrastructureTests/Kiro Tests/InfrastructureTests/Mistral \
  Tests/InfrastructureTests/Omp
```

(Delete `SimpleCLIExecutorTests.swift` too if it exists and Step 1 confirmed deletion.)

- [ ] **Step 3: Remove the 5 registration entries**

In `Sources/App/ClaudeBarApp.swift`, delete the `AmpCodeProvider(...)`, `AntigravityProvider(...)`, `KiroProvider(...)`, `MistralProvider(...)`, and `OmpProvider(...)` array entries (the blocks at lines ~91, 77, 97, 107, 115). Leave Claude, Codex, Cursor, OpenCode.

- [ ] **Step 4: Compiler-guided enumeration cleanup**

Run: `tuist generate && tuist build`
Read each error. For every unresolved reference to a deleted provider, remove that entry from the offending file. Expected offenders (from the enumeration map): `NotificationAlerter.swift`, `ProviderVisualIdentity.swift`, `Theme.swift`. Repeat build until BUILD SUCCEEDED.

- [ ] **Step 5: Trim shared tests, then run tests**

Run: `tuist test`
For each failing/uncompilable shared test, remove the deleted providers' cases from: `ActionBarSpec.swift`, `NotificationAlerterTests.swift`, `MockRepositoryFactory.swift`, `UsageQuotaTests.swift`, `ProbeErrorTests.swift`. Re-run until all pass.
Expected: green, pass count reduced by the deleted providers' tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove AmpCode, Antigravity, Kiro, Mistral, Omp providers"
```

---

## Task 2: Delete Gemini

Gemini uses base settings but has extra App-layer references (`ProviderIcons`, `ComponentPreviews`) and an `AIProvider.swift` mention.

**Files:**
- Delete: Gemini Domain/Infrastructure files, `Resources/GeminiIcon.svg`, `Tests/DomainTests/Provider/Gemini/`, `Tests/InfrastructureTests/Gemini/`.
- Modify: `Sources/App/ClaudeBarApp.swift`, `Sources/App/Views/ProviderVisualIdentity.swift`, `Sources/App/Views/ProviderIcons.swift`, `Sources/App/Views/ComponentPreviews.swift`, `Sources/App/Views/Theme.swift`, `Sources/Domain/Provider/AIProvider.swift` (verify it's only a doc/comment; if `Gemini` appears in real code, remove that reference).

- [ ] **Step 1: Delete source, icon, tests**

```bash
git rm -r \
  Sources/Domain/Provider/Gemini Sources/Infrastructure/Gemini \
  Sources/App/Resources/GeminiIcon.svg \
  Tests/DomainTests/Provider/Gemini Tests/InfrastructureTests/Gemini
```

- [ ] **Step 2: Remove the registration entry**

In `Sources/App/ClaudeBarApp.swift`, delete the `GeminiProvider(probe: GeminiUsageProbe(), ...)` entry (line ~76).

- [ ] **Step 3: Compiler-guided cleanup + build**

Run: `tuist generate && tuist build`
Remove Gemini references from each offending file until BUILD SUCCEEDED. Expected offenders: `ProviderVisualIdentity.swift`, `ProviderIcons.swift`, `ComponentPreviews.swift`, `Theme.swift`, `AIProvider.swift`.

- [ ] **Step 4: Trim shared tests + run**

Run: `tuist test`
Remove Gemini cases from shared tests that enumerate providers (`QuotaMonitorTests`, `AIProviderProtocolTests`, `AIProvidersTests`, plus any from Task 1's list still referencing Gemini). Re-run until green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove Gemini provider"
```

---

## Task 3: Delete the 4 config providers without heavy deps (Zai, Copilot, Kimi, MiniMax)

These extend `ProviderSettingsRepository` with sub-protocols and add `AppSettings` accessors, `SettingsView` wiring, ConfigCards, and (Copilot/MiniMax) credential storage.

**Files:**
- Delete: Domain/Infrastructure files, ConfigCards, icons, per-provider test dirs (see table + `Tests/AcceptanceTests/{CopilotConfigSpec,ZaiConfigSpec}.swift`).
- Modify: `Sources/Domain/Provider/ProviderSettingsRepository.swift` (remove `ZaiSettingsRepository`, `CopilotSettingsRepository`, `KimiSettingsRepository`, `MiniMaxSettingsRepository`), `Sources/Infrastructure/Storage/JSONSettingsRepository.swift`, `Sources/Infrastructure/Storage/UserDefaultsProviderSettingsRepository.swift`, `Sources/App/Settings/AppSettings.swift`, `Sources/App/Views/SettingsView.swift`, `ClaudeBarApp.swift`, `ProviderVisualIdentity.swift`, `Theme.swift`, `NotificationAlerter.swift`, shared test files.

- [ ] **Step 1: Delete source, cards, icons, tests**

```bash
git rm -r \
  Sources/Domain/Provider/Zai Sources/Infrastructure/Zai \
  Sources/Domain/Provider/Copilot Sources/Infrastructure/Copilot \
  Sources/Domain/Provider/Kimi Sources/Infrastructure/Kimi \
  Sources/Domain/Provider/MiniMax Sources/Infrastructure/MiniMax \
  Sources/App/Views/Settings/ZaiConfigCard.swift \
  Sources/App/Views/Settings/CopilotConfigCard.swift \
  Sources/App/Views/Settings/KimiConfigCard.swift \
  Sources/App/Views/Settings/MiniMaxConfigCard.swift \
  Sources/App/Resources/ZaiIcon.svg Sources/App/Resources/CopilotIcon.png \
  Sources/App/Resources/MiniMaxIcon.svg \
  Sources/App/Resources/Assets.xcassets/KimiIcon.imageset \
  Tests/DomainTests/Provider/Zai Tests/DomainTests/Provider/Copilot \
  Tests/DomainTests/Provider/Kimi Tests/DomainTests/Provider/MiniMax \
  Tests/InfrastructureTests/Zai Tests/InfrastructureTests/Copilot \
  Tests/InfrastructureTests/Kimi Tests/InfrastructureTests/MiniMax \
  Tests/AcceptanceTests/CopilotConfigSpec.swift Tests/AcceptanceTests/ZaiConfigSpec.swift
```

Also delete any matching `Assets.xcassets/*Icon.imageset` dirs for Zai/Copilot/MiniMax if present.

- [ ] **Step 2: Remove the 4 settings sub-protocols**

In `Sources/Domain/Provider/ProviderSettingsRepository.swift`, delete the `ZaiSettingsRepository`, `CopilotSettingsRepository`, `KimiSettingsRepository`, and `MiniMaxSettingsRepository` protocol declarations. Keep base, `ClaudeSettingsRepository`, `CodexSettingsRepository`, and `AlibabaSettingsRepository`/`BedrockSettingsRepository` (removed in later tasks).

- [ ] **Step 3: Remove the 4 registration entries**

In `ClaudeBarApp.swift`, delete `ZaiProvider(...)`, `CopilotProvider(...)`, `KimiProvider(...)`, `MiniMaxProvider(...)` entries.

- [ ] **Step 4: Compiler-guided cleanup + build**

Run: `tuist generate && tuist build`
The two settings repositories (`JSONSettingsRepository.swift`, `UserDefaultsProviderSettingsRepository.swift`) will fail to compile — remove the deleted sub-protocols from their conformance lists and delete the corresponding method implementations (`zaiConfigPath`, `copilot*`, `kimiProbeMode`, `minimax*`, credential methods). Then fix `AppSettings.swift` (remove `settings.zai/.copilot/.kimi/.minimax` accessors), `SettingsView.swift` (remove the card wiring), `ProviderVisualIdentity.swift`, `Theme.swift`, `NotificationAlerter.swift`. Repeat until BUILD SUCCEEDED.

- [ ] **Step 5: Trim shared tests + run**

Run: `tuist test`
Trim deleted-provider cases from `NotificationAlerterTests.swift`, `JSONSettingsRepositoryProviderTests.swift`, `UserDefaultsProviderSettingsRepositoryTests.swift`, `MockRepositoryFactory.swift`, `ActionBarSpec.swift`, `QuotaDisplaySpec.swift`, `UsageSnapshotTests.swift`. Re-run until green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove Zai, Copilot, Kimi, MiniMax providers + their settings protocols"
```

---

## Task 4: Delete Alibaba + drop SweetCookieKit

**Files:**
- Delete: Alibaba Domain/Infrastructure files, `AlibabaConfigCard.swift`, `Tests/InfrastructureTests/Alibaba/`.
- Modify: `ProviderSettingsRepository.swift` (remove `AlibabaSettingsRepository`), `JSONSettingsRepository.swift`, `UserDefaultsProviderSettingsRepository.swift`, `AppSettings.swift`, `SettingsView.swift`, `ClaudeBarApp.swift`, `ProviderVisualIdentity.swift`, `Theme.swift`, `Project.swift` (drop `SweetCookieKit` external), `Tuist/Package.swift` (drop `SweetCookieKit` package).

- [ ] **Step 1: Confirm SweetCookieKit is Alibaba-only**

Run: `grep -rn "SweetCookieKit\|CookieProvid" Sources/ | grep -v "Alibaba"`
Expected: no hits in kept source. If any, STOP and reassess. (`SweetCookieKit` powers `AlibabaBrowserCookieProvider` — should be the only consumer.)

- [ ] **Step 2: Delete source, card, tests**

```bash
git rm -r \
  Sources/Domain/Provider/Alibaba Sources/Infrastructure/Alibaba \
  Sources/App/Views/Settings/AlibabaConfigCard.swift \
  Tests/InfrastructureTests/Alibaba
```

- [ ] **Step 3: Remove sub-protocol + registration entry**

Delete `AlibabaSettingsRepository` from `ProviderSettingsRepository.swift`. Delete the `AlibabaProvider(...)` entry from `ClaudeBarApp.swift`.

- [ ] **Step 4: Drop the SweetCookieKit dependency**

In `Project.swift`, remove `.external(name: "SweetCookieKit"),` from the Infrastructure target's dependencies (line ~60). In `Tuist/Package.swift`, remove the `SweetCookieKit` `.package(...)` line (line ~34).

- [ ] **Step 5: Compiler-guided cleanup + build**

Run: `tuist install && tuist generate && tuist build`
Fix `JSONSettingsRepository.swift`, `UserDefaultsProviderSettingsRepository.swift` (remove Alibaba conformance + methods), `AppSettings.swift`, `SettingsView.swift`, `ProviderVisualIdentity.swift`, `Theme.swift` until BUILD SUCCEEDED.

- [ ] **Step 6: Trim shared tests + run**

Run: `tuist test`
Trim Alibaba cases from `ProbeErrorTests.swift`, `NotificationAlerterTests.swift`, `JSONSettingsRepositoryProviderTests.swift`. Re-run until green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: remove Alibaba provider and drop SweetCookieKit dependency"
```

---

## Task 5: Delete Bedrock + drop aws-sdk-swift

The heaviest removal: 3 Infra files, AWS SDK across 4 targets, plus `MenuContentView` and `UsageSnapshot` references.

**Files:**
- Delete: Bedrock Domain/Infrastructure files, `BedrockConfigCard.swift`, `Resources/BedrockIcon.svg`, `Tests/InfrastructureTests/Bedrock/`, `Tests/AcceptanceTests/BedrockConfigSpec.swift`.
- Modify: `ProviderSettingsRepository.swift` (remove `BedrockSettingsRepository`), `JSONSettingsRepository.swift`, `UserDefaultsProviderSettingsRepository.swift`, `AppSettings.swift`, `SettingsView.swift`, `MenuContentView.swift`, `UsageSnapshot.swift`, `ClaudeBarApp.swift`, `ProviderVisualIdentity.swift`, `Theme.swift`, `NotificationAlerter.swift`, `Project.swift` (drop 6 AWS externals from **4 targets**), `Tuist/Package.swift` (drop `aws-sdk-swift`).

- [ ] **Step 1: Confirm AWS SDK is Bedrock-only**

Run: `grep -rn "import AWS\|AWSCloudWatch\|AWSSTS\|AWSPricing\|AWSSSO" Sources/ | grep -v "Bedrock"`
Expected: no hits in kept source.

- [ ] **Step 2: Delete source, card, icon, tests**

```bash
git rm -r \
  Sources/Domain/Provider/Bedrock Sources/Infrastructure/Bedrock \
  Sources/App/Views/Settings/BedrockConfigCard.swift \
  Sources/App/Resources/BedrockIcon.svg \
  Tests/InfrastructureTests/Bedrock Tests/AcceptanceTests/BedrockConfigSpec.swift
```

- [ ] **Step 3: Remove sub-protocol + registration entry**

Delete `BedrockSettingsRepository` from `ProviderSettingsRepository.swift`. Delete the `BedrockProvider(...)` entry from `ClaudeBarApp.swift`.

- [ ] **Step 4: Drop the AWS SDK dependency from all 4 targets**

In `Project.swift`, remove these 6 externals — `AWSCloudWatch`, `AWSSTS`, `AWSPricing`, `AWSSDKIdentity`, `AWSSSO`, `AWSSSOOIDC` — from the dependency lists of the **Infrastructure**, **DomainTests**, **InfrastructureTests**, and **AcceptanceTests** targets (lines ~54–59, ~117–122, ~143–148, ~169–174). In `Tuist/Package.swift`, remove the `aws-sdk-swift` `.package(...)` line (line ~33).

- [ ] **Step 5: Compiler-guided cleanup + build**

Run: `tuist install && tuist generate && tuist build`
Fix `JSONSettingsRepository.swift`, `UserDefaultsProviderSettingsRepository.swift` (remove Bedrock conformance + methods), `AppSettings.swift`, `SettingsView.swift`, `MenuContentView.swift`, `UsageSnapshot.swift`, `ProviderVisualIdentity.swift`, `Theme.swift`, `NotificationAlerter.swift` until BUILD SUCCEEDED.

- [ ] **Step 6: Trim shared tests + run**

Run: `tuist test`
Trim Bedrock cases from `JSONSettingsRepositoryProviderTests.swift`, `JSONSettingsStoreTests.swift`, `UsageSnapshotTests.swift`, `NotificationAlerterTests.swift`, `ActionBarSpec.swift`. Re-run until green.

- [ ] **Step 7: Verify all 12 providers are gone + commit**

Run: `grep -rn "Provider(" Sources/App/ClaudeBarApp.swift`
Expected: exactly 4 entries — `ClaudeProvider`, `CodexProvider`, `CursorProvider`, `OpenCodeProvider`.

Run: `ls Sources/Domain/Provider/*/ -d && ls Sources/Infrastructure/ | grep -iE "alibaba|amp|antigrav|bedrock|copilot|gemini|kimi|kiro|minimax|mistral|omp|zai"`
Expected: only Claude/Codex/Cursor/OpenCode provider dirs; no doomed infra dirs.

```bash
git add -A
git commit -m "refactor: remove Bedrock provider and drop aws-sdk-swift dependency"
```

---

## Task 6: Drop Sparkle auto-update (personal build)

**Files:**
- Delete: `Sources/App/SparkleUpdater.swift`.
- Modify: `Sources/App/ClaudeBarApp.swift` (remove `#if ENABLE_SPARKLE` blocks + `import Sparkle`), `Project.swift` (remove `Sparkle` external from ClaudeBar target + `ENABLE_SPARKLE` from `SWIFT_ACTIVE_COMPILATION_CONDITIONS`), `Tuist/Package.swift` (remove `Sparkle` package), `Sources/App/Info.plist` (remove `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` keys).

- [ ] **Step 1: Find every Sparkle touch-point**

Run: `grep -rn "Sparkle\|ENABLE_SPARKLE\|SUFeedURL\|SUPublicEDKey\|SUEnableAutomatic" Sources/ Project.swift Tuist/Package.swift`
Note every hit; each gets removed below.

- [ ] **Step 2: Delete the updater + remove wiring**

```bash
git rm Sources/App/SparkleUpdater.swift
```

In `ClaudeBarApp.swift`, remove `import Sparkle` (line ~5–7 `#if`), the `@State private var sparkleUpdater` block (lines ~43–46), and every other `#if ENABLE_SPARKLE ... #endif` block (keep whatever's in the `#else`/outside, if any — verify the menu still builds without an "Check for Updates" item, or delete that item).

- [ ] **Step 3: Remove dep + compilation condition**

In `Project.swift`: remove `.external(name: "Sparkle"),` from the ClaudeBar target (line ~85); remove `ENABLE_SPARKLE` from both the debug and release `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (lines ~97, ~100), leaving `DEBUG` (debug) and empty/removed (release). In `Tuist/Package.swift`: remove the `Sparkle` `.package(...)` line (line ~30).

- [ ] **Step 4: Strip Info.plist appcast keys**

In `Sources/App/Info.plist`, remove the `SUFeedURL`, `SUPublicEDKey`, and `SUEnableAutomaticChecks` entries (and any other `SU*` Sparkle keys found in Step 1).

- [ ] **Step 5: Build + test**

Run: `tuist install && tuist generate && tuist build`
Expected: BUILD SUCCEEDED with no Sparkle references.

Run: `tuist test`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: drop Sparkle auto-update for personal build"
```

---

## Task 7: Delete release/CI machinery

**Files:**
- Delete: `.github/workflows/release.yml`, any appcast file (`appcast.xml`), any Sparkle key/notarization helper scripts.

- [ ] **Step 1: Inventory release machinery**

Run: `ls .github/workflows/ && find . -name "appcast*.xml" -not -path "./.git/*" && grep -rln "notariz\|APPLE_CERTIFICATE\|SUFeedURL\|productbuild" .github/ scripts/ 2>/dev/null`

- [ ] **Step 2: Delete the release workflow + appcast**

```bash
git rm .github/workflows/release.yml
```

Delete any `appcast*.xml` and Sparkle-key/notarization scripts found in Step 1. Keep `tests.yml` only if you still want CI to run `tuist test`; otherwise `git rm` it too (personal build — your call, default keep).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove release/notarization workflow for personal build"
```

---

## Task 8: Rename bundle identifier (optional, personal)

Prevents your build from colliding with an installed upstream ClaudeBar. Replace `com.tddworks.claudebar` with your own reverse-DNS prefix (example uses `com.<you>.claudebar`).

**Files:**
- Modify: `Project.swift` (5 `bundleId:` lines), `Sources/App/entitlements.plist`, `Sources/App/entitlements.mas.plist`, `Sources/App/Info.plist` (any hardcoded bundle id), `Sources/App/ClaudeBarApp.swift:10` (the `hookSettingsChanged` notification name — cosmetic, safe to leave or rename).

- [ ] **Step 1: Find every occurrence**

Run: `grep -rn "com.tddworks.claudebar" Sources/ Project.swift`

- [ ] **Step 2: Rename**

In `Project.swift`, change the app bundle id `com.tddworks.claudebar` and the four sub-target ids (`.domain`, `.infrastructure`, `.domain-tests`, `.infrastructure-tests`, `.acceptance-tests`) to your prefix. Update `entitlements*.plist` and `Info.plist` if they hardcode the id. (Leave the `hookSettingsChanged` notification string unless you want full consistency.)

- [ ] **Step 3: Build + test**

Run: `tuist generate && tuist build && tuist test`
Expected: green. Launch once to confirm the app runs under the new identity.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: rename bundle identifier for personal build"
```

---

## Done criteria

- `Sources/App/ClaudeBarApp.swift` registers exactly 4 providers.
- No `Sources/Domain/Provider/` or `Sources/Infrastructure/` directory for any of the 12 deleted providers.
- `Tuist/Package.swift` no longer lists `aws-sdk-swift`, `SweetCookieKit`, or `Sparkle` (SwiftTerm remains — Phase 2).
- `tuist build` and `tuist test` both green.
- App launches and shows Claude / Codex / Cursor / OpenCode.

## Follow-on (separate plans, not this one)

- **Phase 2 — Claude CLI→API cutover:** default Claude to `ClaudeProbeMode.api`, delete `ClaudeUsageProbe` + `TerminalRenderer`, drop `SwiftTerm` from `Project.swift`/`Package.swift` (incl. the `productTypes`/`targetSettings` SwiftTerm entries). Touches `ClaudeProvider` internals + tests — behavioral, not pure deletion. Needs its own small plan.
- **Phase 3 — `Sources/App/` UI rewrite:** requires a brainstorm first (menu bar / popover / per-provider display / which App subsystems survive). Fixes the popover-bounce bug as a side effect.
