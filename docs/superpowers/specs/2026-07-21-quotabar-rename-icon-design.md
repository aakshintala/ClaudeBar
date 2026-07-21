# QuotaBar Rename + Icon Redesign — Design

## Context

Phase 3 (`docs/superpowers/specs/2026-07-20-app-ui-rewrite-design.md`) rebuilt `Sources/App/` around the trimmed 4-provider scope and shipped a minimal popover, static menu-bar icon, and a Quit button fix. Mid-review the user asked for two more changes: a way to quit from the popover (already fixed, `b7f3db9`) and a new name + icon — the current "ClaudeBar" name and `chart.bar.fill` SF Symbol glyph are leftovers from the pre-fork app and don't fit the redesigned, single-purpose tool.

This spec covers only the rename and icon. It was brainstormed visually: 5 icon concepts were presented (Gauge, Bars, Meter/Fuel-Gauge, Q-Monogram, Segmented Ring), the user picked the Meter/Fuel-Gauge base, then 3 ways to combine it with a robot glyph were presented, and the user picked **Meter-Mouth Robot**.

## Goals

- Rename the app from "ClaudeBar" to "QuotaBar" everywhere a user can see it.
- Replace the app icon and menu-bar glyph with the Meter-Mouth Robot design, in both a full-color Dock/Finder icon and a simplified monochrome menu-bar template glyph, sharing one design language.
- Keep the meter fill fixed/decorative (green→yellow gradient) — no live data binding, consistent with the earlier decision that the menu-bar glyph carries zero live state.

## Scope: Rename

| Location | Change |
|---|---|
| `Sources/App/Info.plist` | `CFBundleName`, `CFBundleDisplayName` → `QuotaBar` |
| `Sources/App/Views/Popover/PopoverView.swift` | Header `Text("ClaudeBar")` → `Text("QuotaBar")`; `.help("Quit ClaudeBar")` → `.help("Quit QuotaBar")` |
| Any `AppLog` startup/version strings containing "ClaudeBar" | Update to "QuotaBar" |
| Bundle identifier (`com.tddworks.ClaudeBar` or similar) | **Unchanged.** Already diverged from upstream during the Phase 1 fork; renaming again has no functional benefit and risks breaking any local trust/permission grants tied to the current identifier. |
| Settings path `~/.claudebar/settings.json` | **Unchanged.** Renaming would silently orphan existing users' settings on upgrade for a purely cosmetic reason. |
| Repo/product name (`Project.swift`, directory names) | **Unchanged** for this pass — out of scope; a full repo rename is a separate, larger decision not requested here. |

## Scope: Icon

**Concept — Meter-Mouth Robot:** a robot face (antenna with tip dot, rounded-square head outline, two circular eyes) whose mouth is a horizontal fuel-gauge meter pill, filled with a fixed green→yellow gradient. Line art in `#e8e8e8` on a black tile/background, matching the pure-black `DarkTheme` shipped in Phase 3.

**Two renderings from the same design:**
1. **Full app icon** (`Assets.xcassets/AppIcon.appiconset`) — full-color rendering (line art + gradient meter fill) at all required sizes (16–1024pt, @1x/@2x per Apple's macOS icon size set).
2. **Menu-bar glyph** (replacing `StatusBarIconDriver.swift`'s `NSImage(systemSymbolName: "chart.bar.fill", ...)`) — simplified monochrome template image (single color, `isTemplate = true` so macOS tints it correctly for light/dark menu bars): head outline + two eye dots + meter-pill mouth, gradient dropped (template images are single-alpha-channel; a gradient can't render). Matches the 18px reference rendering already validated in the `icon-robot-meter.html` mockup.

Both are static — no live quota data feeds either rendering, per the existing "truly static" menu-bar decision.

## Implementation approach

- Generate the icon as vector art (SVG, matching the mockup's proportions) once, then rasterize to PNGs at each required `AppIcon.appiconset` size.
- Generate the menu-bar glyph as a single template PNG (@1x/@2x/@3x, ~18pt base) matching macOS menu-bar glyph conventions.
- Replace `Assets.xcassets/AppIcon.appiconset` contents and add a new imageset (or a plain bundled PNG, matching how the current SF Symbol is loaded) for the menu-bar glyph.
- Update `StatusBarIconDriver.swift` to load the new bundled image instead of constructing an `NSImage(systemSymbolName:)`.
- Update `Info.plist` and the string literals listed above.
- Verify with the existing Phase 3 cycle: `rm -rf ClaudeBar.xcodeproj ClaudeBar.xcworkspace && tuist generate --no-open`, `xcodebuild build`, `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64'` (check all three test-bundle summary lines, not a truncated tail).
- No new tests needed — this is a rename + static-asset swap with no new logic branches. Existing tests (647) should be unaffected; a build success plus manual confirmation that the Dock icon and menu-bar glyph render is the acceptance bar here (screen-recording permission gap means I can't screenshot-verify myself — the user should eyeball it after `tuist generate && open`).

## Risks

- Menu-bar template-image rendering is finicky (macOS requires exact `isTemplate` flag and a flat alpha mask) — if the glyph renders as a solid black square or doesn't tint correctly in light menu bars, that's a template-flag/asset-format bug, not a design problem, and should be debugged via `superpowers:systematic-debugging` rather than iterated on visually.
- Icon asset generation happens outside Xcode's usual asset pipeline (hand-authored SVG → rasterized PNGs) — sizes must match Apple's required `AppIcon.appiconset` set exactly or `tuist generate`/`xcodebuild` will warn about missing slots.
