---
name: github-actions
description: |
  QuotaBar's CI workflows (build.yml, tests.yml). Use when a CI run fails, when changing
  a workflow, or when asked what CI checks.
---

# QuotaBar CI

Two workflows in `.github/workflows/`, both on `macos-26`, triggered by pushes and pull requests to `main` and `develop`:

| Workflow | Does |
|----------|------|
| `build.yml` | `tuist install`, `tuist generate`, then `xcodebuild build` of the `QuotaBar` scheme in `QuotaBar.xcworkspace`, Debug and Release |
| `tests.yml` | the same setup, then `xcodebuild test` with coverage, and uploads the report to Codecov (`CODECOV_TOKEN` secret). Also runs on manual dispatch. |

There is no release workflow, signing, notarisation or auto-update. Releases are local Release builds (`tuist build QuotaBar -C Release`).

## Keeping CI honest

- Tests run through `xcodebuild test`, never `tuist test` (it exits 0 having run nothing). A run is real only if the log has one `Test run with N tests` line per bundle and `** TEST SUCCEEDED **`.
- Both workflows use the runner's bundled Xcode on purpose: Tuist's SwiftSyntax macro prebuilts must match that toolchain, and a separately installed Swift broke the Release build before.
- If you rename the scheme or workspace in `Project.swift`, change both workflows in the same commit.

## Debugging a failure

```bash
gh run list --limit 5
gh run view <run-id> --log-failed
```

Reproduce locally with the commands in `CLAUDE.md` (`tuist generate --no-open`, then the same `xcodebuild` line).
