# Phase 3: `Sources/App` UI Rewrite — Design

## Context

[Phase 1](../plans/2026-07-18-strip-to-four-providers.md) stripped the provider roster down to Claude, Codex, Cursor, and OpenCode. Phase 2 cut Claude over to API-only probing. Both left `Sources/App/` untouched — it's still built for the original ~15-provider app: a 1400-line `MenuContentView.swift`, a 1445-line `SettingsView.swift`, four themes, and several features (hooks/session tracking, daily-usage analytics, a plugin system, referral sharing, live activity, multi-account switching, custom web embeds) that predate the fork's narrower scope.

Phase 3 rewrites `Sources/App/` for this smaller app, and — per the discussion behind this spec — treats the shrink as a real opportunity to simplify, not just restructure the same feature set. It also fixes the menu-bar popover "bounce" bug as a side effect, since that bug's root cause lives entirely in the view code being replaced (see `menubar-popover-bounce-rootcause` project memory: a `.window`-style `MenuBarExtra` hugging data-dependent content instead of pinning window height).

**Scope note:** several of the cut features are backed by real Domain/Infrastructure subsystems, not just views. This is not a pure `Sources/App` rewrite — it has two halves: **(a)** delete the subsystems behind cut features across all three layers, **(b)** rebuild the surviving UI.

## Goals

- Shrink `Sources/App/` to match the 4-provider surface: fewer, smaller, single-purpose view files instead of two 1400-line monoliths.
- Redesign the popover and menu-bar icon from scratch around what the user actually looks at, rather than preserving the current visual design.
- Cut every feature the user doesn't use, including its underlying subsystem, not just its UI card.
- Fix the popover bounce bug as a consequence of the rewrite (pin window height, absorb variation in an internal scroll region — see prior diagnosis).

## Scope: What's Cut

Each of these is a full deletion — UI, and the Domain/Infrastructure code that backs it, not just hiding a card:

| Feature | What goes |
|---|---|
| Hooks / session tracking | `HookHTTPServer`, `HookInstaller`, `SessionMonitor`, session start/end desktop notifications, `HookSettingsRepository` + `hook.*` settings, `SessionIndicatorView`, `SessionPhaseColor` |
| Daily usage analytics | `ClaudeDailyUsageAnalyzer`, `DailyUsageReport`, `DailyUsageCardView` |
| Extensions/plugin system | `ExtensionRegistry`, `ScriptProbe`, `HealthCheckProbe`, `ExtensionProvider`, `~/.claudebar/extensions/` loading, `ExtensionConfigCard`, `ExtensionMetricCardView` |
| Share pass (referral link) | `ClaudePass`, `ClaudePassProbe`, `SharePassView` |
| Live Activity | `LiveActivityManager` — already a 36-line no-op placeholder (ActivityKit isn't available on macOS); zero behavior loss |
| Account picker / management | `AccountPickerView`, `AccountManagementCard` — `MultiAccountProvider` has no adopters today; unused scaffolding |
| Theme import | `ThemeImportView`, `ImportedThemeStore`, `ImportedTerminalTheme` — `ThemeImportView` is never presented anywhere (dead), and it only existed to support the CLI theme, which is also being cut |
| Custom web card | `CustomWebCardView`, `CustomCardURLField` — arbitrary-URL webview embed |
| CLI theme, Christmas theme | `Theme/Themes/CLITheme.swift`, `Theme/Themes/ChristmasTheme.swift` |
| Menu-bar live label pipeline | `QuotaMonitor.menuBarLabel` + its helpers, the Settings menu-bar provider/quota picker (`MenuBarProviderChoiceButton`, `MenuBarQuotaChoiceButton`), stacked-mode settings |
| Claude API budget threshold | Settings card for a dollar budget + warning toggle — not applicable to the user's account (Claude Max, not API billing) |

## Scope: What's Kept (and rebuilt)

- **Quota polling** — `QuotaMonitor` as single source of truth, unchanged. All 4 providers' probes unchanged.
- **Cost stat cards** — dollar spend cards for Claude and Codex (both populate `CostUsage`), rebuilt to match the new visual language.
- **Quota-threshold notifications** — `NotificationAlerter` desktop alerts when a provider crosses warning/critical/depleted. Independent of the (now-cut) session-hooks notifications.
- **Provider enable/disable + credential status** in Settings.
- **Refresh interval** setting.
- **Two themes** — Dark and Light, down from four.

## Design: Popover

Layout direction (validated via mockup, chosen over a bars-based list and a card-grid): a **grouped-header list**. Provider name is a small label; its quota buckets are indented rows below it. No progress bars — each row shows the bucket name, a colored percentage (green/yellow/red by status), and time-to-reset, right-aligned. Always fully expanded (no collapse/primary-bucket logic needed) — with 4 providers × 2-3 buckets each, that's ~9-10 rows total, which fits without collapsing.

Buckets are driven directly by `UsageSnapshot.quotas: [UsageQuota]` (already an array — no domain model change needed). Concretely, per provider:
- **Claude**: session, weekly, and however many `modelSpecific` buckets are present (opus/sonnet/fable/etc. — already dynamic in the API response).
- **Codex**: session, weekly. (A "rate-limit resets available" counter was discussed but doesn't exist in the domain model today — explicitly out of scope for this rewrite; would need new probe work.)
- **Cursor**: plan (monthly included), on-demand, and team if present (not literally "First-Party vs API" — that's `plan` vs `onDemand`/`team` in the actual API).
- **OpenCode**: session/weekly/monthly per its existing probe.

Cost cards (Claude, Codex) render per-provider alongside the quota buckets, restyled to match.

Visual palette validated in mockups: `#000000` background, text tiers `#e8e8e8` / `#888888` / `#666666`, status colors `#22c55e` (healthy) / `#eab308` (warning) / `#ef4444` (critical/depleted).

**Bounce-bug fix**: pin the popover's window height (drop the vertical `.fixedSize`), let the internal scroll region absorb content-height variation instead of the window itself.

## Design: Menu-Bar Icon

Truly static: one fixed glyph and color, always, regardless of any provider's status. No live percentage, no live color, no per-refresh rendering. Click still opens the popover for the real breakdown.

`StatusItemLabelDriver` survives in drastically reduced form — renamed `StatusBarIconDriver` — because it has two responsibilities today and only one goes away:
1. ~~Composing per-refresh label content (pixels)~~ → replaced by setting one static `NSImage` once, at attach time.
2. **Restarting the background quota-refresh loop after system sleep** (issue #192: `MenuBarExtra`'s SwiftUI label hosting can permanently stop receiving invalidations after sleep) — this is unrelated to whether the icon shows live content, so it's still needed to keep background polling reliable.

## Design: Settings

Trimmed to three things:
1. Per-provider enable/disable toggle + credential/auth status (e.g. "OAuth credentials found").
2. Quota-threshold notification toggle (desktop alerts on status degradation).
3. Refresh interval.

Everything else in the current 1445-line `SettingsView.swift` (menu-bar picker, theme import, extension config, account management, hook toggle, daily-usage toggle, Claude budget) is cut per the scope table above.

## Design: Themes

Two themes remain: Dark and Light. Dark is rewritten to pure black (see palette above) rather than the current purple-pink glassmorphism. Light is reviewed but not redesigned — it was already judged "mostly okay." `ThemeRegistry` shrinks to these two entries; the pluggable theme-import mechanism goes with it (see Scope: What's Cut).

## New File Structure (`Sources/App/`)

```
ClaudeBarApp.swift                        — trimmed init: no hook wiring, no session monitor, no extension loading
StatusBarIconDriver.swift                 — static icon + sleep-safe refresh-loop restart only
Views/Popover/PopoverView.swift           — replaces MenuContentView
Views/Popover/ProviderQuotaSection.swift  — provider header + its bucket rows + cost card
Views/Popover/QuotaBucketRow.swift        — single row: label, colored %, reset time
Views/Settings/SettingsView.swift         — provider rows + notification toggle + refresh interval
Theme/Themes/DarkTheme.swift              — rewritten pure black
Theme/Themes/LightTheme.swift             — kept, reviewed
Theme/ThemeRegistry.swift                 — trimmed to 2 entries
```

Exact file boundaries may shift during planning/implementation as long as the SRP goal holds: no return to 1000+ line view files.

## Execution Approach

Delete-first, compiler-driven rebuild — the same pattern Phase 1 used successfully in this repo. Delete the cut subsystems wholesale across Domain/Infrastructure/App, let the compiler's error trail become the task list, then rebuild the surviving UI from scratch guided by the mockups above. Directly on `main`, no PR flow (established workflow for this personal fork).

Two sub-phases:
- **3a — Delete.** Remove every subsystem in the "What's Cut" table, across all three layers, fixing compile errors as they surface. Green build+test gate at the end.
- **3b — Rebuild.** Build the new popover, static icon, trimmed Settings, and two-theme system per the design above. Green build+test gate on each task.

## Testing

- Domain/Infrastructure deletions: remove the now-orphaned test files alongside their subjects (per-provider test dirs, shared enumerating test files — same pattern Phase 1 already navigated for the provider cuts).
- New `Sources/App` views: this layer has historically had light test coverage (SwiftUI views consuming `QuotaMonitor` directly, per the architecture's "no ViewModel" pattern) — follow existing project convention for what's tested vs. eyeballed in previews, rather than inventing new test scaffolding for views.
- Manual verification: the popover's actual rendering (layout, colors, bounce-bug fix) needs to be checked by running the app, not just compiling — mockups are a design reference, not a substitute for seeing the real `MenuBarExtra` window behave correctly after sleep/wake and content-height changes.

## Risks / Open Questions

- Codex's "rate-limit resets available" counter doesn't exist in the domain model — explicitly deferred, not part of this rewrite.
- Deleting `HookSettingsRepository`/`hook.*` and other settings namespaces touches `JSONSettingsRepository`, which implements multiple protocols — deletion order matters to keep the repository compiling at each step (handled during planning).
- Exact Dark-theme values beyond the validated mockup palette (spacing, corner radii, card backgrounds) aren't pinned down yet — left to implementation, consistent with "mockups are directional, not pixel-spec."
