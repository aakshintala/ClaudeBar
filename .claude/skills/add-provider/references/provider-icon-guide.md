# Provider icon guide

Each provider has an image set in `Sources/App/Resources/Assets.xcassets/<Name>Icon.imageset`, loaded by the name `ProviderVisualIdentityLookup.iconAssetName(for:)` returns. Two formats are in use:

| Format | Example | Use when |
|--------|---------|----------|
| One SVG, `"preserves-vector-representation": true` | `CursorIcon.imageset/CursorIcon.svg` | you have a clean vector logo (preferred: one file, sharp at every scale) |
| PNGs at 64, 128, 192 px (1x, 2x, 3x) | `ClaudeIcon.imageset/claude_64.png` … | only raster art exists; add `_dark`/`_light` variants with an appearance entry if the logo needs both (`OpenCodeIcon`) |

## Icon shape

A square canvas (256×256 for SVG) with a rounded-rectangle background in the brand colour (corner radius about 20% of the side) and the logo centred at about 75% of the canvas.

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect fill="#BRAND" width="256" height="256" rx="52" ry="52"/>
  <g transform="translate(32, 32) scale(0.75)">
    <path fill="#FFFFFF" d="..."/>
  </g>
</svg>
```

## Contents.json

Copy the one from `CursorIcon.imageset` (SVG) or `ClaudeIcon.imageset` (PNG) and change the file names.

To make PNGs from an SVG: `brew install librsvg`, then `for s in 64 128 192; do rsvg-convert -w $s -h $s <Name>Icon.svg -o <name>_$s.png; done`.

## Colours and symbol

In `Sources/App/Views/ProviderVisualIdentity.swift`, add a `case "<id>"` to:

- `color(for:scheme:)`: the brand colour, one value for dark and one for light (check contrast on both `AppTheme.dark` and `AppTheme.light`).
- `gradient(for:scheme:)`: the second gradient stop.
- `iconAssetName(for:)`: `"<Name>Icon"`.
- `symbolIcon(for:)`: an SF Symbol shown if the asset fails to load.

Done when the icon shows in the popover and in Settings in both themes.
