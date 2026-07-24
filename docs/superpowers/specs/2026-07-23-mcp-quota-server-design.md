# MCP Quota Server Design

**Date:** 2026-07-23
**Status:** Approved, not yet implemented

## Goal

Let agents running in Claude Code read live quota headroom across all four
providers (Claude, Codex, Cursor, OpenCode) so they can make **routing
decisions** ("Claude weekly is at 12%, delegate this to Codex") and act as
**guardrails** ("don't start this expensive run, headroom is too low").

This is for local personal use. It is not packaged, published, or released.

## Non-Goals

- Historical or burn-rate analysis. Point-in-time snapshots only.
- Exposing the feed beyond `127.0.0.1`.
- Automated tests for the TypeScript layer (see Testing).
- Any change to how the menu bar UI reads quota data.

## Constraints Discovered During Design

These shaped the design and must not be silently regressed.

### Anthropic throttles `/api/oauth/usage` aggressively

`ClaudeAPIUsageProbe` wraps successful snapshots in an in-process TTL cache
(`defaultSnapshotCacheTTL`, currently `15 * 60`). The justifying comment at
`Sources/Infrastructure/Claude/ClaudeAPIUsageProbe.swift:139-147` records that
the throttle has handed out **1-hour `Retry-After` windows in response to even
one call after a quiet period** (ref: `anthropics/claude-code#30930`).

Two consequences:

1. A "refresh now" request against Claude is a no-op past the first call in any
   TTL window — it re-serves the cache. Output must be honest about data age
   rather than implying freshness it cannot deliver.
2. **A standalone MCP binary that runs the probes itself is not viable.** It
   would start with a cold cache on every invocation, make a real HTTP call per
   tool call, and trip the throttle — costing an hour of Claude visibility,
   which is precisely the failure the guardrail use case cannot tolerate. The
   MCP server must read from the long-lived app process.

### The other three probes have no caching whatsoever

`CursorUsageProbe`, `CodexAPIUsageProbe`, and `OpenCodeUsageProbe` do real
network/subprocess work on every call with nothing in front of them. Protection
for these must live in the serving layer.

### Background refresh only ever refreshed the selected provider

`StatusBarIconDriver.swift:109` returns `nil` from
`backgroundRefreshProviderIds`, so the monitoring loop refreshed only the
currently selected provider; every other provider's snapshot updated solely when
the popover opened and called `refreshAll()`.

The user has since **disabled background refresh entirely**. The app is now
purely reactive. This means:

- Nothing consumes Claude's TTL except popover opens and MCP calls, so real call
  volume is now agent-driven rather than loop-driven.
- The "~4 calls/hour" arithmetic in the `ClaudeAPIUsageProbe` comment is stale
  and must be rewritten as part of this work.
- An export-only design (write snapshots to a file, read them from MCP) would
  routinely serve hours-old data for non-selected providers, which defeats
  routing. Hence the on-demand path below.

### Entitlements are already in place

`Sources/App/entitlements.plist` already declares
`com.apple.security.network.server`. No entitlement work is required.

## Architecture

```
┌─ Claude Code agent ─────────────────────────────┐
│  calls tool: get_quotas                         │
└────────────────┬────────────────────────────────┘
                 │ stdio (MCP)
┌────────────────▼────────────────────────────────┐
│  mcp/  (TypeScript, ~120 lines)                 │
│  • one tool: get_quotas(provider?)              │
│  • GET http://127.0.0.1:<port>/quotas           │
│  • renders JSON → text layout                   │
└────────────────┬────────────────────────────────┘
                 │ HTTP, localhost only
┌────────────────▼────────────────────────────────┐
│  QuotaBar.app                                   │
│                                                 │
│  Infrastructure/Server/                         │
│   • QuotaHTTPServer   — NWListener, one route   │
│   • QuotaFeedService  — coalescing + refresh    │
│   • QuotaFeedDTO      — wire format (Codable)   │
│                                                 │
│  Domain/  (unchanged)                           │
│   • QuotaMonitor → providers → UsageSnapshot    │
└─────────────────────────────────────────────────┘
```

`Domain` requires no changes.

## Components

### `QuotaFeedDTO` (Infrastructure/Server)

A separate `Codable` wire struct plus a mapping function from
`[any AIProvider]`. Domain models do **not** gain `Codable`.

Rationale: `QuotaType` carries associated values
(`.modelSpecific(String)`, `.timeLimit(String)`), and `UsageQuota` /
`AccountTier` are rich behavioral types. Synthesizing `Codable` onto them would
freeze the domain shape into a public wire contract and fight the existing
design. `QuotaType` already exposes a `quotaKey` string form used by settings,
so the mapping is mechanical.

Wire shape:

```json
{
  "generatedAt": "2026-07-23T10:02:11Z",
  "providers": [{
    "id": "claude", "name": "Claude", "tier": "Max",
    "capturedAt": "2026-07-23T10:00:09Z", "ageSeconds": 122,
    "status": "critical", "unavailable": null, "throttledUntil": null,
    "quotas": [
      {"key":"session","label":"Session","percentRemaining":68,
       "resetsAt":"2026-07-23T11:44:00Z","resetText":null,"status":"healthy"},
      {"key":"weekly","label":"Weekly","percentRemaining":12,
       "resetsAt":"2026-07-26T14:00:00Z","resetText":null,"status":"critical"},
      {"key":"model:opus","label":"Opus","percentRemaining":40,
       "resetsAt":null,"resetText":"12/500 on-demand","status":"healthy"}
    ]
  }],
  "disabledProviderIds": ["opencode-go"]
}
```

`capturedAt` is `null` for a provider that has never been probed.
`unavailable` and `throttledUntil` are mutually exclusive and both `null` on the
healthy path. `resetText` carries raw probe strings (e.g. Cursor's
`326/40000 requests`, `Unlimited`) that percentages alone cannot express; omit
from the TS render when null.

Quota `key` values use `QuotaType.quotaKey` — e.g. `.modelSpecific("opus")` →
`model:opus`, `.timeLimit("Monthly")` → `time:Monthly`. `label` is
`quotaType.displayName`.

### `QuotaFeedService` (Infrastructure/Server)

`@MainActor` (it reads `QuotaMonitor`). The only component with interesting
logic. Holds the **coalescing window**: a hardcoded 60s constant on the service,
not a setting — it exists to bound a chatty agent, and exposing it invites
turning off the one protection standing in front of the three uncached probes.

On `currentFeed()`:

1. If the last refresh completed within the coalescing window → map current
   in-memory snapshots and return. No probe work.
2. Else if a refresh is already in flight → `await` that same task. Do not start
   a second.
3. Else → start one, store the handle, await it.

The refresh call is:

```swift
await monitor.refresh(providerIds: enabledIds, kind: .background)
```

This method already exists at `Sources/Domain/Monitor/QuotaMonitor.swift:124`.
`refreshAll()` is deliberately **not** used: it takes no `kind` and would force
`.interactive`.

`.background` is correct here because it skips non-glanceable work such as the
daily-usage JSONL scan, which this feed does not include. Note the naming
tension: `RefreshKind.background` is named for *who* polls, not *how much work*
is done, so an agent-triggered path passing `.background` reads slightly off.
The semantics are the ones we want; the name is not.

A **20s server-side deadline** applies to the refresh. On expiry, serve whatever
snapshots exist with honest ages rather than hanging the agent. The TypeScript
client uses a **25s** timeout — deliberately longer, so the server's graceful
degradation always wins the race and the client timeout only fires if the app
has genuinely wedged.

**Time source:** `Clock` (`Sources/Domain/Monitor/Clock.swift`) exposes only
`sleep(for:)` and `sleep(nanoseconds:)` — it has no `now`. Rather than widen the
protocol and update every conformer and test fake, `QuotaFeedService` takes an
injected `now: @Sendable () -> Date`. This matches an existing idiom:
`ClaudeBarApp.swift:21` already injects `NotificationAlerter` with a closure.

### `QuotaHTTPServer` (Infrastructure/Server)

`NWListener` bound to loopback via `NWParameters.acceptLocalOnly` on the
configured port. One route: `GET /quotas`. No third-party dependency — for a single GET with no request
body this is read-until-`\r\n\r\n`, match the request line, write a
fixed-shape response. An HTTP framework is not worth the dependency for one
localhost endpoint.

Must handle a request arriving split across multiple TCP reads.

### `mcp/index.ts`

Stdio MCP server, one tool, no state.

```
get_quotas(provider?: string)
```

`provider` filters the rendered output to one provider by id. Filtering happens
**client-side in the TS layer** — the endpoint always returns the full feed, so
there is no second code path on the Swift side. When filtered, the trailing
disabled-providers line is omitted. An unknown provider id renders as
"unknown provider 'x'; known: claude, codex, cursor, opencode" rather than an
error, so the agent can self-correct.

Renders the JSON as text rather than passing JSON through, because the consumer
is an LLM making a judgement call:

```
claude (Max) - data 2m old
  session  68% left, resets in 1h42m  [healthy]
  weekly   12% left, resets in 3d4h   [critical]
  Opus     40% left (12/500 on-demand)  [healthy]

codex (Plus) - data 2m old
  weekly   81% left, resets in 5d     [healthy]

cursor - unavailable: no credentials found

(opencode-go disabled in QuotaBar)
```

Wired via `.mcp.json` pointing at a local `node` invocation. Not packaged.

### Settings

New keys in the existing `JSONSettingsStore` dot-notation namespacing:

| Key | Default | Purpose |
|---|---|---|
| `mcp.enabled` | `false` | Whether the listener runs at all |
| `mcp.port` | `8787` | Listener port |
| `claude.snapshotCacheTTL` | `300` | Claude probe TTL, in seconds |

`mcp.enabled` defaults **off**: an always-on local listener should not appear
without the user asking for it. A toggle goes in `SettingsView`.

### Claude TTL change

`ClaudeBarApp.swift:41` passes `snapshotCacheTTL` read from
`claude.snapshotCacheTTL` (default 300) instead of relying on
`ClaudeAPIUsageProbe.defaultSnapshotCacheTTL`.

The comment block at `ClaudeAPIUsageProbe.swift:139-147` must be rewritten. Its
"~4 calls/hour" reasoning assumed a 60s monitor loop consuming the TTL, which no
longer exists now that background refresh is disabled.

**This is a calculated risk, not a free win.** The downside is asymmetric: a 429
throws `ProbeError.rateLimited` and yields *zero* Claude data for up to an hour.
It is mitigated by (a) the coalescing window capping agent-driven call volume,
(b) the existing 429 handler and `RateLimitState`, (c) `AppLog.probes` logging
of the rate-limited path, and (d) reverting being a one-line settings change.

## Error Handling

The governing rule: **every failure degrades to labeled-stale data rather than
an error.** An agent making a routing decision is better served by
"codex: 40m old, 80% left" than by an exception.

| Case | Behavior |
|---|---|
| App not running | `ECONNREFUSED` → tool returns "QuotaBar isn't running — no quota data available" as **content, not an MCP error**, so the agent proceeds |
| Probe threw (no creds, CLI missing) | `unavailable` populated from `lastError`; renders as `cursor - unavailable: …` |
| Claude throttled (`ProbeError.rateLimited`) | `throttledUntil` populated. Rendered distinctly from "unavailable": "throttled until 11:04, showing last known data (47m old)". The guardrail needs to know this is transient **and** that the numbers are stale |
| Enabled but never probed | `capturedAt: null` → "no data yet" |
| Refresh exceeds 20s deadline | Serve existing snapshots with honest ages |
| Port already bound | Listener fails, logged via `AppLog`, surfaced in the Settings toggle |

## Testing

Chicago School, per repo convention: mock at the boundary, real objects above
it. The seam already exists — `QuotaMonitor.init` takes `providers`, `clock`,
and `powerStateProvider`, and `UsageProbe` is `@Mockable`. Tests build a **real**
`QuotaMonitor` with **real** providers wired to `MockUsageProbe`.

### `InfrastructureTests/Server/QuotaFeedDTOTests`

Pure mapping, fast:

- `.modelSpecific("opus")` → key `model:opus`, label `Opus`
- `snapshot == nil` with no error → `capturedAt: null`
- `lastError` present → populated `unavailable`
- `ProbeError.rateLimited(retryAt:)` → `throttledUntil` shape, **not** the
  `unavailable` shape
- disabled providers appear in `disabledProviderIds`, absent from `providers`

### `InfrastructureTests/Server/QuotaFeedServiceTests`

The coalescing window, verified by **state, not call counts**. `MockUsageProbe`
returns a snapshot whose `capturedAt` advances on each call, so repeat probing
is observable as a state change:

- two `currentFeed()` calls inside the window → identical `capturedAt`
- a call after advancing injected `now` past the window → different `capturedAt`
- N concurrent calls during an in-flight refresh → all N share one `capturedAt`
- a probe that throws → feed still returns, `unavailable` populated

The last case is the "degrade to labeled data, never error" rule under test.

### `InfrastructureTests/Server/QuotaHTTPServerTests`

Request parsing against the raw byte stream:

- `GET /quotas HTTP/1.1` → 200
- unknown path → 404
- malformed request line → 400
- request split across two TCP reads still parses

### `AcceptanceTests/MCPFeedSpec`

Bind an ephemeral port, real `URLSession` GET, assert the decoded JSON.
Follows existing `*Spec.swift` naming.

### Explicitly not tested

**The TypeScript server.** Local-only and not for release, so it gets manual
verification: `curl` the endpoint, then `claude mcp add` and confirm the tool
renders. Adding a Node test toolchain to a pure-Swift repo to cover ~120 lines
of string rendering is not worth it. This is a decision, not an oversight.

**Whether Anthropic tolerates a 5-minute TTL.** An empirical question about a
third party. Mitigation is the existing 429 handler plus `AppLog` visibility.

## Rejected Alternatives

**Snapshot file export, read-only MCP.** The app writes
`~/.claudebar/snapshots.json` on each refresh; MCP just reads it. Simplest by
far and needs no server. Rejected because background refresh only ever touched
the selected provider — and is now off entirely — so non-selected providers
would routinely be hours stale, defeating cross-provider routing.

**Standalone Swift MCP binary linking Domain + Infrastructure.** Runs probes
itself, works with the app closed. Rejected on the cold-cache throttle argument
above: a real HTTP call per tool invocation trips Anthropic's throttle and costs
an hour of Claude visibility.

**Unix domain socket instead of localhost HTTP.** No port to allocate or
collide, no TCP surface. Rejected in favour of HTTP for debuggability (`curl`)
and simpler Node client code, which matters more for a local-only tool.

**A `force` flag on `get_quotas`.** Rejected: it is the most direct route to an
hour-long 429 lockout, and honest data-age labelling gives the agent what it
needs to reason about staleness without one.

**Adding `now` to the `Clock` protocol.** Rejected: would require updating every
conformer and test fake for one consumer. Closure injection matches existing
practice.

## Open Risk

The 5-minute Claude TTL is the one genuinely uncertain decision here. If 429s
start appearing in `~/Library/Logs/ClaudeBar/ClaudeBar.log`, raise
`claude.snapshotCacheTTL` back toward 900 — no code change required.
