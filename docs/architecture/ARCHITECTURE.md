# QuotaBar architecture

How the pieces fit and how a refresh flows. Build, test, settings keys and logging live in [`CLAUDE.md`](../../CLAUDE.md).

## Layers

```
App (Sources/App)                 SwiftUI; reads QuotaMonitor directly, no view model
  QuotaBarApp                     composition root: builds providers, monitor, feed, status item
  PopoverView, SettingsView       menu bar dropdown and its settings page
  StatusBarIconDriver             static status-item icon + background refresh lifecycle
  AppSettings                     @Observable facade over the settings file
  AppTheme (.dark, .light)        colours, passed through the environment
        │
Domain (Sources/Domain)           no I/O; protocols are @Mockable
  QuotaMonitor                    single source of truth: providers, refresh, alerts, background loop
  AIProvider                      one class for every provider: id, name, probe, isEnabled, snapshot, lastError
  UsageProbe                      protocol: isAvailable(), probe() -> UsageSnapshot
  UsageSnapshot, UsageQuota       quotas with status, reset time, balance or units
  QuotaStatus                     healthy < warning < critical < depleted
  ProviderSettingsRepository      per-provider isEnabled
  QuotaAlerter, Clock, PowerStateProvider
        │
Infrastructure (Sources/Infrastructure)
  Claude/ Codex/ Cursor/ OpenCode/   one UsageProbe + credential loader per provider
  Storage/JSONSettingsRepository     SettingsFile <-> ~/.quotabar/settings.json
  Server/                            QuotaHTTPServer, FeedServerController, QuotaFeedService, QuotaFeedDTO, QuotaHooks, QuotaFeedText
  Notifications/NotificationAlerter  QuotaAlerter -> UNUserNotificationCenter
  Shared/                            NetworkClient over URLSession, ProbeHelpers, runProcess, system clock and power state
  Logging/                           AppLog: OSLog + ~/Library/Logs/QuotaBar/QuotaBar.log
```

## Refresh flow

```
popover open / refresh button (force) / background tick / GET /quotas
        │
QuotaMonitor.refresh(force:)
        │  for each enabled provider, concurrently:
        │    skip if snapshot < 60 s old and not forced
        │    join the in-flight Task if one exists
        ▼
AIProvider.refresh()  ── isSyncing, snapshot, lastError (main actor)
        │
UsageProbe.probe()    ── off the main actor; HTTP via NetworkClient
        │
QuotaMonitor compares snapshot.overallStatus with the last one
        └── changed → QuotaAlerter.alert(...) (if app.quotaAlertsEnabled)
```

- The background loop runs every `app.backgroundSyncInterval` (floor 60 s, doubled on battery) and pauses while the Mac sleeps.
- `ClaudeAPIUsageProbe` keeps its own 300 s snapshot cache, which also holds on a forced refresh, and backs off on 429 `Retry-After`.
- `GET /quotas` waits at most 20 s for the refresh, then serves whatever snapshots exist. The Claude Code hooks never refresh; they render the cached feed.

## Quota status

`UsageQuota.status` is the one rule the popover, alerts and feed share:

- At 0% it is depleted.
- With no reset time: critical below 20%, warning below 50%, otherwise healthy.
- With a reset time it is pace-aware, and otherwise healthy. Burn rate = percent used ÷ percent of the window elapsed. Below 20% left, critical only when the burn rate exceeds 1 (it will run out before reset). Below 50% left, warning when the burn rate exceeds 1.5.
- A balance-only quota (no percentage) is always healthy.

## Design rules

- Domain types own their behaviour (status, pace, formatting helpers); views and the feed read them rather than recomputing.
- New external dependencies enter as a `@Mockable` protocol in Domain or a small injectable seam (`NetworkClient`, `Clock`, `PowerStateProvider`).
- Tests assert on resulting state (Chicago school). Mocks stub data; `verify()` is for real boundaries only.
