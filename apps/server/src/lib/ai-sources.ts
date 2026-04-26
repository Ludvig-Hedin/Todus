// Shared AI source types — surfaced via the `context_sources` SSE event so clients
// (iOS, macOS, web) can render a unified "Sources" affordance on assistant messages.
//
// A source represents one piece of context the model consumed for this turn:
// a web result, an @-mentioned entity, an injected memory, or a tool-call result.
// Tool-call sources are appended client-side after the tool runs; everything the
// server enriches the prompt with is emitted from the AI route.

export type AISourceKind =
  | 'web'
  | 'email'
  | 'meeting'
  | 'calendar_event'
  | 'document'
  | 'note'
  | 'thread'
  | 'memory'
  | 'task'
  | 'company';

export type AISourcePlatform =
  | 'gmail'
  | 'google_meet'
  | 'google_calendar'
  | 'website'
  | 'notion'
  | 'document'
  | 'notes'
  | 'todus'
  | 'memory'
  | 'upsales'
  | 'unknown';

export interface AISource {
  /** Stable per turn. UUID for backend-emitted sources; `tool:<callId>` for client-built ones. */
  id: string;
  kind: AISourceKind;
  platform: AISourcePlatform;
  /** Headline row text — e.g. "InnovateTech Summit 2026 - Exploring collaboration opportunities". */
  title: string;
  /** Small grey row above the title — e.g. "Email sent to Lisa Tran". */
  subtitle?: string;
  /** ISO timestamp; clients format as "14 Nov, 2025 09:10". */
  timestamp?: string;
  /** Openable web link, if any. */
  url?: string;
  /** App-navigation target (thread id, event id, …). */
  entityId?: string;
  /** Detail-sheet preview text. */
  snippet?: string;
  /** Domain hint for favicons / brand override. */
  iconHint?: string;
}

export interface ContextSourcesEvent {
  type: 'context_sources';
  sources: AISource[];
}

// ── Builders ─────────────────────────────────────────────────────────────────
// Tiny adapters that turn each enrichment input (web search results, resolved
// mentions, injected memories) into a `AISource`. Kept here so the AI route
// stays declarative.

interface WebLikeSource {
  url: string;
  title: string;
  snippet: string;
}

const hostname = (url: string): string | undefined => {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return undefined;
  }
};

export function webSourceToAISource(source: WebLikeSource): AISource {
  const host = hostname(source.url);
  return {
    id: `web:${source.url}`,
    kind: 'web',
    platform: 'website',
    title: source.title || host || source.url,
    subtitle: host,
    url: source.url,
    snippet: source.snippet,
    iconHint: host,
  };
}

interface MentionLike {
  id: string;
  kind: 'task' | 'thread' | 'event' | 'person';
  title: string;
  subtitle?: string | null;
}

export function mentionToAISource(mention: MentionLike): AISource {
  // `thread` mentions resolve to email threads (see
  // apps/server/src/trpc/routes/mentions.ts), not Todus chat threads.
  // Use kind=email + platform=gmail so the row reads correctly.
  const map: Record<MentionLike['kind'], { kind: AISourceKind; platform: AISourcePlatform; subtitle: string }> = {
    task: { kind: 'task', platform: 'todus', subtitle: 'Task' },
    thread: { kind: 'email', platform: 'gmail', subtitle: 'Email thread' },
    event: { kind: 'calendar_event', platform: 'google_calendar', subtitle: 'Calendar event' },
    person: { kind: 'company', platform: 'unknown', subtitle: 'Person' },
  };
  const m = map[mention.kind];
  return {
    id: `mention:${mention.kind}:${mention.id}`,
    kind: m.kind,
    platform: m.platform,
    title: mention.title,
    subtitle: mention.subtitle || m.subtitle,
    entityId: mention.id,
  };
}

/**
 * Memories are surfaced as a single grouped row when the prompt-injection
 * uses ≥1 memory. Mem0's cached fast-path returns just text strings, so we
 * don't have per-memory ids/timestamps here — combine them into one source
 * with a representative snippet. Use `getAllMemories` directly if you need
 * per-entry rows in a future iteration.
 */
export function memoriesToAISource(memories: string[]): AISource | null {
  if (memories.length === 0) return null;
  const preview = memories.slice(0, 3).map((m) => `• ${m}`).join('\n');
  return {
    id: 'memory:injected',
    kind: 'memory',
    platform: 'memory',
    title: memories.length === 1 ? 'Memory from past conversations' : `${memories.length} memories from past conversations`,
    subtitle: 'Memory',
    snippet: preview,
  };
}
