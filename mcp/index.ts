#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const DEFAULT_PORT = 8787;

/** The MCP tool may wait: an agent asked, and the app's own refresh deadline is
 *  20s. Kept above it so the server's graceful degradation wins the race. */
const FETCH_TIMEOUT_MS = 25_000;

/** The SessionStart hook may NOT wait — it blocks the session from starting.
 *  A cold coalescing window can trigger a full refresh, so bail fast and emit
 *  nothing rather than freeze every new session behind a probe. */
const PRINT_TIMEOUT_MS = 3_000;

type ProviderQuota = {
  key: string;
  label: string;
  percentRemaining: number;
  resetsAt: string | null;
  resetText: string | null;
  status: string;
};

type ProviderFeed = {
  id: string;
  name: string;
  tier: string | null;
  capturedAt: string | null;
  ageSeconds: number | null;
  status: string;
  unavailable: string | null;
  throttledUntil: string | null;
  quotas: ProviderQuota[];
};

type QuotaFeed = {
  generatedAt: string;
  providers: ProviderFeed[];
  disabledProviderIds: string[];
};

function port(): number {
  const raw = process.env.QUOTABAR_MCP_PORT ?? process.env.MCP_PORT;
  if (!raw) return DEFAULT_PORT;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : DEFAULT_PORT;
}

function formatAge(seconds: number | null): string {
  if (seconds == null) return "no data yet";
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m old`;
  if (seconds < 86_400) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return m > 0 ? `${h}h${m}m old` : `${h}h old`;
  }
  const d = Math.floor(seconds / 86_400);
  const h = Math.floor((seconds % 86_400) / 3600);
  return h > 0 ? `${d}d${h}h old` : `${d}d old`;
}

function formatUntil(iso: string | null): string | null {
  if (!iso) return null;
  const ms = new Date(iso).getTime() - Date.now();
  if (ms <= 0) return "soon";
  const totalMinutes = Math.floor(ms / 60_000);
  const days = Math.floor(totalMinutes / (24 * 60));
  const hours = Math.floor((totalMinutes % (24 * 60)) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) return `${days}d${hours > 0 ? hours + "h" : ""}`;
  if (hours > 0) return `${hours}h${minutes > 0 ? minutes + "m" : ""}`;
  if (minutes > 0) return `${minutes}m`;
  return "soon";
}

function formatClock(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
}

function padLabel(label: string, width = 8): string {
  return label.length >= width ? label : label + " ".repeat(width - label.length);
}

/** `resetText` is overloaded upstream: Cursor puts real usage counts in it
 *  ("21479/27222 requests") while Claude and Codex put a reset description
 *  ("Resets in 1h 24m"). The latter duplicates the reset we compute from
 *  `resetsAt` — and disagrees by a minute, which reads as a bug. Keep only the
 *  variants that carry information the percentage cannot. */
function informativeResetText(quota: ProviderQuota): string | null {
  const text = quota.resetText?.trim();
  if (!text) return null;
  return /^resets?\b/i.test(text) ? null : text;
}

/** Buckets that warrant detail: the reset time is what turns a number into a
 *  decision ("session resets in an hour, wait" vs "weekly resets in days,
 *  move the work"). Healthy buckets don't need it, so they stay on one line. */
function needsDetail(q: ProviderQuota): boolean {
  return q.status !== "healthy";
}

function renderProvider(p: ProviderFeed): string[] {
  const lines: string[] = [];
  const tier = p.tier ? ` (${p.tier})` : "";

  if (p.throttledUntil) {
    lines.push(
      `${p.id}${tier} - throttled until ${formatClock(p.throttledUntil)}, ` +
        `showing last known data (${formatAge(p.ageSeconds)})`
    );
  } else if (p.unavailable) {
    return [`${p.id}${tier} - unavailable: ${p.unavailable}`];
  } else if (p.capturedAt == null) {
    return [`${p.id}${tier} - no data yet`];
  }

  const detailed = p.quotas.filter(needsDetail);

  // Everything healthy and nothing to explain: collapse the provider to a
  // single scannable line so a routine session start stays ~1 line/provider.
  if (detailed.length === 0 && !p.throttledUntil) {
    const summary = p.quotas
      .map((q) => {
        const extra = informativeResetText(q);
        return `${q.label.toLowerCase()} ${Math.round(q.percentRemaining)}%` +
          (extra ? ` (${extra})` : "");
      })
      .join(" · ");
    return [`${p.id}${tier} - ${summary || "no quotas reported"}`];
  }

  if (!p.throttledUntil) {
    lines.push(`${p.id}${tier} - data ${formatAge(p.ageSeconds)}`);
  }

  for (const q of p.quotas) {
    const pct = Math.round(q.percentRemaining);
    const extra = informativeResetText(q);
    const textPart = extra ? ` (${extra})` : "";

    if (!needsDetail(q)) {
      lines.push(`  ${padLabel(q.label)} ${pct}% left${textPart}`);
      continue;
    }

    const reset = formatUntil(q.resetsAt);
    const resetPart = reset ? `, resets in ${reset}` : "";
    lines.push(
      `  ${padLabel(q.label)} ${pct}% left${textPart}${resetPart}  [${q.status}]`
    );
  }

  return lines;
}

function renderFeed(feed: QuotaFeed, filter?: string): string {
  const knownIds = [
    ...feed.providers.map((p) => p.id),
    ...feed.disabledProviderIds,
  ];
  const lines: string[] = [];

  if (filter) {
    const provider = feed.providers.find((p) => p.id === filter);
    if (!provider) {
      return `unknown provider '${filter}'; known: ${knownIds.join(", ")}`;
    }
    lines.push(...renderProvider(provider));
    return lines.join("\n");
  }

  for (const provider of feed.providers) {
    lines.push(...renderProvider(provider));
    lines.push("");
  }

  while (lines.length > 0 && lines[lines.length - 1] === "") {
    lines.pop();
  }

  if (feed.disabledProviderIds.length > 0) {
    lines.push("");
    lines.push(
      `(disabled in QuotaBar: ${feed.disabledProviderIds.join(", ")})`
    );
  }

  return lines.join("\n");
}

async function fetchFeed(timeoutMs = FETCH_TIMEOUT_MS): Promise<QuotaFeed> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`http://127.0.0.1:${port()}/quotas`, {
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return (await response.json()) as QuotaFeed;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException)?.code;
    const refused =
      code === "ECONNREFUSED" ||
      (error instanceof TypeError && String(error).includes("fetch failed"));
    if (refused) {
      throw new Error("APP_NOT_RUNNING");
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

// `--print` renders the same feed for the SessionStart hook, so the hook and the
// MCP tool can never drift apart. Emits the documented hook envelope rather than
// bare text, since `additionalContext` is what actually reaches the model.
// Any failure produces no output and exits 0: a hook that errors or stalls would
// degrade every session it runs in.
if (process.argv.includes("--print")) {
  try {
    const feed = await fetchFeed(PRINT_TIMEOUT_MS);
    const text = renderFeed(feed);
    if (text.trim()) {
      process.stdout.write(
        JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: `Quota headroom (QuotaBar):\n${text}`,
          },
        }) + "\n"
      );
    }
  } catch {
    // Intentionally silent — no output is better than noise at session start.
  }
  process.exit(0);
}

const server = new McpServer({
  name: "quotabar",
  version: "1.0.0",
});

server.tool(
  "get_quotas",
  "Read live AI provider quota headroom from QuotaBar for routing and guardrail decisions",
  {
    provider: z
      .string()
      .optional()
      .describe(
        "Optional provider id filter (claude, codex, cursor, opencode-go)"
      ),
  },
  async ({ provider }) => {
    try {
      const feed = await fetchFeed();
      const text = renderFeed(feed, provider);
      return { content: [{ type: "text", text }] };
    } catch (error) {
      if (error instanceof Error && error.message === "APP_NOT_RUNNING") {
        return {
          content: [
            {
              type: "text",
              text: "QuotaBar isn't running — no quota data available",
            },
          ],
        };
      }
      const message =
        error instanceof Error ? error.message : "Failed to fetch quota feed";
      return {
        content: [
          {
            type: "text",
            text: `QuotaBar feed unavailable (${message}) — try again shortly`,
          },
        ],
      };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
