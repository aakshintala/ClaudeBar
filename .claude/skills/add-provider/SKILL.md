---
name: add-provider
description: |
  Guide for adding new AI providers to ClaudeBar using TDD patterns. Use this skill when:
  (1) Adding a new AI assistant provider (like Antigravity, Cursor, etc.)
  (2) Creating a usage probe for a CLI tool or local API
  (3) Following TDD to implement provider integration
  (4) User asks "how do I add a new provider" or "create a provider for X"
---

# Add Provider to ClaudeBar

Add new AI providers following established TDD patterns and architecture.

## Architecture Overview

> **Full architecture:** [docs/ARCHITECTURE.md](../../../docs/ARCHITECTURE.md)

| Component | Location | Purpose |
|-----------|----------|---------|
| `AIProvider` | `Sources/Domain/Provider/` | Rich domain model with isEnabled state |
| `UsageProbe` | `Sources/Infrastructure/CLI/` | Fetches quota from CLI/API |
| Tests | `Tests/InfrastructureTests/CLI/` | Parsing + behavior tests |

## TDD Workflow

### Phase 1: Parsing Tests (Red → Green)

Create `Tests/InfrastructureTests/CLI/{Provider}UsageProbeParsingTests.swift`:

```swift
import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct {Provider}UsageProbeParsingTests {

    static let sampleResponse = """
                                { /* sample API/CLI response */ }
                                """

    @Test func `parses quota into UsageQuota`() throws {
        let data = Data(Self.sampleResponse.utf8)
        let snapshot = try {Provider}UsageProbe.parseResponse(data, providerId: "{provider-id}")
        #expect(snapshot.quotas.count > 0)
    }

    @Test func `maps percentage correctly`() throws { /* ... */ }
    @Test func `parses reset time`() throws { /* ... */ }
    @Test func `extracts account email`() throws { /* ... */ }
    @Test func `handles missing data gracefully`() throws { /* ... */ }
}
```

### Phase 2: Probe Behavior Tests (Red → Green)

Create `Tests/InfrastructureTests/CLI/{Provider}UsageProbeTests.swift`:

```swift
import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct {Provider}UsageProbeTests {

    @Test func `isAvailable returns false when not detected`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).execute(...).willReturn(CLIResult(output: "", exitCode: 1))
        let probe = {Provider}UsageProbe(cliExecutor: mockExecutor)
        #expect(await probe.isAvailable() == false)
    }

    @Test func `isAvailable returns true when detected`() async { /* ... */ }
    @Test func `probe throws appropriate error when unavailable`() async { /* ... */ }
    @Test func `probe returns UsageSnapshot on success`() async { /* ... */ }
}
```

### Phase 3: Implement Probe

Create `Sources/Infrastructure/CLI/{Provider}UsageProbe.swift`:

```swift
import Foundation
import Domain

public struct {Provider}UsageProbe: UsageProbe {
    private let cliExecutor: any CLIExecutor
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    public init(
        cliExecutor: (any CLIExecutor)? = nil,
        networkClient: (any NetworkClient)? = nil,
        timeout: TimeInterval = 8.0
    ) {
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.networkClient = networkClient ?? URLSession.shared
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        // Detect if provider is available (binary exists, process running, etc.)
    }

    public func probe() async throws -> UsageSnapshot {
        // 1. Detect/authenticate
        // 2. Fetch quota data
        // 3. Parse and return UsageSnapshot
    }

    // Static parsing for testability
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        // Parse response into domain models
    }
}
```

### Phase 4: Register Provider

There is no per-provider class: every provider is one `AIProvider(id:name:probe:settingsRepository:)`.
Add one line to the `providers` list in `Sources/App/ClaudeBarApp.swift`:

```swift
provider("{provider-id}", "{Provider Name}", {Provider}UsageProbe()),
```

The id is the settings key (`providers.{id}.isEnabled`) and the feed id; never change it once shipped.
A probe that needs config takes the settings sub-protocol itself (see ISP section below):
`{Provider}UsageProbe(settingsRepository: settingsRepository)`.

Add visual identity in `Sources/App/Views/Theme.swift`:

```swift
// In AppTheme.providerColor(for:scheme:)
case "{provider-id}": return /* your color */

// In AppTheme.providerName(for:)
case "{provider-id}": return "{Provider Name}"

// In AppTheme.providerSymbolIcon(for:)
case "{provider-id}": return "/* SF Symbol name */"

// In AppTheme.providerIconAssetName(for:)
case "{provider-id}": return "{Provider}Icon"
```

## Domain Model Mapping

Map provider responses to existing domain models:

| Source Data | Domain Model |
|-------------|--------------|
| Quota percentage | `UsageQuota.percentRemaining` (0-100) |
| Model/tier name | `QuotaType.modelSpecific("name")` |
| Reset time | `UsageQuota.resetsAt` (Date) |
| Account email | `UsageSnapshot.accountEmail` |

## Error Handling

Use existing `ProbeError` enum:

```swift
ProbeError.cliNotFound("{Provider}")      // Binary/process not found
ProbeError.authenticationRequired          // Auth token missing/expired
ProbeError.executionFailed("message")      // Runtime errors
ProbeError.parseFailed("message")          // Parse errors
```

## ISP: Creating Provider-Specific Repository Sub-Protocols

If your provider needs special configuration or credentials, create a sub-protocol following ISP:

### Step 1: Define Sub-Protocol in Domain

Add to `Sources/Domain/Provider/ProviderSettingsRepository.swift`:

```swift
/// {Provider}-specific settings repository, extending base ProviderSettingsRepository.
public protocol {Provider}SettingsRepository: ProviderSettingsRepository {
    // Configuration
    func {provider}ConfigPath() -> String
    func set{Provider}ConfigPath(_ path: String)

    // Credentials (if needed)
    func save{Provider}Token(_ token: String)
    func get{Provider}Token() -> String?
    func has{Provider}Token() -> Bool
}
```

### Step 2: Implement in Infrastructure

Add to `Sources/Infrastructure/Storage/JSONSettingsRepository.swift`:

```swift
// MARK: - {Provider}SettingsRepository

extension JSONSettingsRepository: {Provider}SettingsRepository {
    public func {provider}ConfigPath() -> String {
        store.read(key: "{provider}.configPath") ?? ""
    }

    public func set{Provider}ConfigPath(_ path: String) {
        store.write(value: path, key: "{provider}.configPath")
    }
}
```

### Step 3: Give the Probe the Sub-Protocol

```swift
public init(settingsRepository: any {Provider}SettingsRepository) {
    self.settingsRepository = settingsRepository
}
```

**Existing Examples:**
- `ZaiSettingsRepository` - config path + env var
- `CopilotSettingsRepository` - env var + GitHub credentials

## Reference Implementation

See [references/antigravity-example.md](references/antigravity-example.md) for a complete working example showing:
- Full parsing test suite
- Probe behavior tests with mocking
- Probe implementation with process detection
- Provider class pattern

## Provider Icon

See [references/provider-icon-guide.md](references/provider-icon-guide.md) for creating provider icons:
- SVG template with rounded rectangle background
- PNG generation at 1x/2x/3x sizes
- Asset catalog setup
- ProviderVisualIdentity extension

## Checklist

- [ ] Parsing tests created and passing
- [ ] Probe behavior tests created and passing
- [ ] Probe implementation complete
- [ ] Provider class created
- [ ] Provider registered in ClaudeBarApp
- [ ] Visual identity added to Theme.swift (color, name, icons)
- [ ] Provider icon SVG created with rounded rect background
- [ ] Icon PNGs generated (64, 128, 192px)
- [ ] All 300+ existing tests still pass
