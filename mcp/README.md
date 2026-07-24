# QuotaBar MCP quota server

A stdio MCP server exposing one tool, `get_quotas`, so Claude Code agents can
read live quota headroom across Claude, Codex, Cursor and OpenCode — for routing
decisions and pre-flight guardrails.

It is a thin client. All the work happens in QuotaBar.app, which serves the feed
over loopback HTTP; this process only fetches and renders. See
`docs/superpowers/specs/2026-07-23-mcp-quota-server-design.md` for why.

## Setup

**1. Enable the server in QuotaBar** — Settings → "MCP Quota Server" → "Enable
MCP server". Default port 8787, bound to `127.0.0.1` only. Nothing listens until
this is on.

**2. Install dependencies**

```bash
cd mcp && npm install
```

Requires Node 22.6+ for `--experimental-strip-types`.

**3. Register the server — at user scope**

```bash
claude mcp add quotabar --scope user \
  -e QUOTABAR_MCP_PORT=8787 \
  -- node --experimental-strip-types /absolute/path/to/ClaudeBar/mcp/index.ts
```

Use **user** scope with an **absolute path**. A project-scoped `.mcp.json` with a
relative path only works while Claude Code runs inside this repo — which defeats
the point, since routing decisions are wanted in every project.

## Optional: quota at session start

`--print` emits the same rendering as a `SessionStart` hook envelope, so every
session starts knowing the numbers without spending a tool call:

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "node --experimental-strip-types /absolute/path/to/ClaudeBar/mcp/index.ts --print 2>/dev/null || true",
        "timeout": 10
      }]
    }]
  }
}
```

It uses a 3s budget (vs. the tool's 25s) because a `SessionStart` hook blocks the
session from starting. Any failure — app not running, slow probe — produces no
output and exits 0.

## Behaviour worth knowing

- **Output adapts to severity.** All-healthy providers collapse to one line each;
  reset times appear only on buckets that need attention, because that is what
  distinguishes "session resets in an hour, wait it out" from "weekly resets in
  days, move the work".
- **Data can be a few minutes stale.** Claude's probe holds a 5-minute snapshot
  cache to stay clear of Anthropic's `/api/oauth/usage` throttle, and the app
  coalesces refreshes to once per 60s. Repeated calls inside that window return
  identical data — re-polling achieves nothing.
- **`throttled` is not `depleted`.** It means the quota can't be *seen* right now;
  the numbers shown are last-known.
- **Failures degrade, never throw.** If QuotaBar isn't running the tool returns a
  plain message so the agent can carry on.

## Development

Editing `index.ts` has no effect until the MCP server process restarts — restart
Claude Code, or `/mcp` → reconnect.
