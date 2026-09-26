---
name: add-provider
description: |
  Add a new usage provider to QuotaBar (a UsageProbe plus one registration line), test-first.
  Use when adding a provider such as OpenRouter, writing a UsageProbe for an HTTP API,
  or when asked "how do I add a provider".
---

# Add a provider to QuotaBar

Every provider is the one `AIProvider` class, configured with an id, a display name and a `UsageProbe`. Adding a provider is a probe, one registration line and its visual identity. Read `CLAUDE.md` first for the test command and the settings file.

Reference probes:

| Probe | Shows |
|-------|-------|
| `Sources/Infrastructure/OpenCode/OpenCodeUsageProbe.swift` | smallest case: API key from a file, one GET, a static parser |
| `Sources/Infrastructure/Codex/CodexAPIUsageProbe.swift` | OAuth refresh, a balance meter in `credits` |
| `Sources/Infrastructure/Cursor/CursorUsageProbe.swift` | units meter (`unitsUsed`/`unitsLimit`), token cached until JWT expiry |
| `Sources/Infrastructure/Claude/ClaudeAPIUsageProbe.swift` | pure parser split from the HTTP shell, snapshot cache, 429 backoff |

## Steps

Each step is done when its tests pass in the full `xcodebuild test` run (`** TEST SUCCEEDED **`, no `✘`).

### 1. Parser (red, then green)

Capture a real response body (redact ids and keys) and test a static parser in `Tests/InfrastructureTests/<Name>/<Name>UsageProbeTests.swift`:

```swift
@Test
func `parses the usage response into quotas`() throws {
    let quotas = try <Name>UsageProbe.parseUsageResponse(Data(Self.sample.utf8))
    #expect(quotas.first?.percentRemaining == 75)
    #expect(quotas.first?.resetsAt != nil)
}
```

Map the response onto `UsageQuota`:

| Source | Field |
|--------|-------|
| percent left (0–100) | `percentRemaining`; `nil` for a balance-only meter |
| window | `quotaType`: `.session`, `.weekly`, `.modelSpecific(name)`, `.timeLimit(name)` |
| reset time | `resetsAt: Date?` only; never a pre-formatted string |
| money or credits | `balanceRemaining`, `balanceUsed`, `balanceCap`, `balanceUnit` (`.usd`, `.credits`) |
| request counts | `unitsUsed`, `unitsLimit` |

Status (healthy to depleted) is derived by `UsageQuota.status`; the probe never sets it. Throw `ProbeError.parseFailed` on a body that does not decode.

### 2. Probe (red, then green)

Test `isAvailable()` and `probe()` with `MockNetworkClient` (stub `request(.any)` with `httpResponse(_:statusCode:)` from `Tests/Support/`) and credentials in a temp directory. Cover success, missing credentials (`isAvailable() == false`, `probe()` throws `.authenticationRequired`), and a 401.

Implement in `Sources/Infrastructure/<Name>/<Name>UsageProbe.swift`:

- Inject `networkClient: any NetworkClient = URLSession.shared` and a credential loader with a test seam (home directory or environment).
- Send with `networkClient.send(request, label: "<Name>")` from `Shared/ProbeHelpers.swift`; it maps non-200 to `ProbeError` and logs. Parse dates with `parseISO8601`.
- Return `UsageSnapshot(providerId: "<id>", quotas: quotas, capturedAt: Date())`.
- Log through `AppLog.probes` and never log a key or token.

### 3. Credentials

- Credentials another tool writes (a CLI's auth file): read them where that tool puts them, as the OpenCode and Codex loaders do.
- An API key the user pastes into QuotaBar (OpenRouter, Muse): store it in the Keychain with `SecItem*`, in an item QuotaBar creates (service named for QuotaBar and the provider). Never put a key in `settings.json` or UserDefaults. The first provider that needs this builds the shared Keychain store in `Sources/Infrastructure/` with a protocol seam for tests.
- A setting the user edits (other than the key) gets a sub-protocol of `ProviderSettingsRepository` in Domain, a field in `SettingsFile`, and the probe takes that sub-protocol in its initialiser. Skip this when the provider has nothing to configure.

### 4. Register

Add one line to the `providers` list in `Sources/App/QuotaBarApp.swift`:

```swift
provider("<id>", "<Display Name>", <Name>UsageProbe()),
```

The id is the settings key (`providers.<id>.isEnabled`) and the feed id; choose it once. The feed and the pi status extension (`~/work/pi-extensions/extensions/status/quota.ts`) pick the provider up with no change unless the DTO shape changes.

### 5. Visual identity

In `Sources/App/Views/ProviderVisualIdentity.swift` add a `case "<id>"` to `color`, `gradient`, `iconAssetName` and `symbolIcon`. Add an icon image set to `Sources/App/Resources/Assets.xcassets`; see [references/provider-icon-guide.md](references/provider-icon-guide.md).

A settings card is optional: add one under `Sources/App/Views/Settings/` using `ConfigCard` only when the provider has something to configure (an API key field, for example).

## Done when

- Parser and probe tests pass, and the full suite total has gone up by the tests you added.
- `tuist build QuotaBar -C Release` succeeds.
- With the app running and the feed on, `curl -s 127.0.0.1:8787/quotas` lists the new id with its quotas.
- `CLAUDE.md`'s provider table and `README.md`'s provider list include it.
