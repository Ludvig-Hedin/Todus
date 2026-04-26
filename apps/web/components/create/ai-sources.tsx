/**
 * Sources affordance for AI assistant messages.
 *
 * Mirrors the iOS / macOS implementations: shows up to three stacked
 * platform icons + a "Sources" label inline with the message action row,
 * and opens a right-side sheet listing every source the AI consumed —
 * web results, prompt mentions, injected memories, and tool-call results.
 *
 * Source data comes from the backend `context_sources` SSE event
 * (see `apps/server/src/lib/ai-sources.ts`).
 *
 * **Wiring status:** the web chat goes through `useAgentChat` from
 * `agents/ai-react`, which consumes the Vercel AI SDK protocol. Custom
 * SSE chunks emitted by the AI route bypass that protocol and never
 * reach the React hook. To plug this component in, the backend stream
 * needs to migrate the `context_sources` chunk onto the AI SDK `data`
 * channel (e.g. `createDataStream` / `streamData.append`) so it shows
 * up in the hook's `data: JSONValue[]` field; then key the entries to
 * the assistant message id. Native iOS / macOS already work because
 * they parse the raw SSE stream directly.
 */
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';
import { useState } from 'react';
import { cn } from '@/lib/utils';

// ── Types ───────────────────────────────────────────────────────────────────
// Mirrors apps/server/src/lib/ai-sources.ts exactly.

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
  id: string;
  kind: AISourceKind;
  platform: AISourcePlatform;
  title: string;
  subtitle?: string;
  timestamp?: string;
  url?: string;
  entityId?: string;
  snippet?: string;
  iconHint?: string;
}

// ── Component ───────────────────────────────────────────────────────────────

interface SourcesProps {
  sources: AISource[];
  onSelect?: (source: AISource) => void;
}

export function Sources({ sources, onSelect }: SourcesProps) {
  const [open, setOpen] = useState(false);

  if (sources.length === 0) return null;

  // Take the first occurrence of each distinct platform so the icon stack feels diverse.
  const seenPlatforms = new Set<AISourcePlatform>();
  const stacked = sources
    .filter((s) => {
      if (seenPlatforms.has(s.platform)) return false;
      seenPlatforms.add(s.platform);
      return true;
    })
    .slice(0, 3);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="hover:bg-muted/40 flex items-center gap-2 rounded-md px-2 py-1 text-sm font-medium transition-colors"
      >
        <span className="flex">
          {stacked.map((source, index) => (
            <span
              key={source.id}
              style={{ marginLeft: index === 0 ? 0 : -8, zIndex: stacked.length - index }}
              className="ring-background ring-2"
            >
              <SourcePlatformIcon platform={source.platform} iconHint={source.iconHint} size={20} />
            </span>
          ))}
        </span>
        <span>Sources</span>
      </button>

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="right" className="w-full sm:max-w-md p-0">
          <SheetHeader className="px-5 pt-5 pb-3">
            <SheetTitle>Sources</SheetTitle>
          </SheetHeader>
          <div className="overflow-y-auto h-full pb-12">
            {sources.map((source) => (
              <SourceRow
                key={source.id}
                source={source}
                onClick={() => {
                  if (source.kind === 'web' && source.url) {
                    window.open(source.url, '_blank', 'noopener,noreferrer');
                    return;
                  }
                  onSelect?.(source);
                  setOpen(false);
                }}
              />
            ))}
          </div>
        </SheetContent>
      </Sheet>
    </>
  );
}

// ── Row ─────────────────────────────────────────────────────────────────────

function SourceRow({ source, onClick }: { source: AISource; onClick: () => void }) {
  const formattedDate = source.timestamp
    ? (() => {
        const date = new Date(source.timestamp);
        if (!Number.isFinite(date.getTime())) return null;
        return date.toLocaleString(undefined, {
          day: '2-digit',
          month: 'short',
          year: 'numeric',
          hour: '2-digit',
          minute: '2-digit',
        });
      })()
    : null;

  return (
    <button
      type="button"
      onClick={onClick}
      className="hover:bg-muted/40 flex w-full items-start gap-3 border-b px-5 py-4 text-left transition-colors"
    >
      <div className="min-w-0 flex-1">
        <div className="text-muted-foreground flex items-baseline justify-between gap-3 text-xs">
          <span className="truncate">{source.subtitle ?? defaultSubtitle(source)}</span>
          {formattedDate ? <span className="shrink-0">{formattedDate}</span> : null}
        </div>
        <div className="mt-1 line-clamp-2 text-sm font-semibold text-foreground">
          {source.title}
        </div>
        <div className="mt-2 flex items-center gap-1.5">
          <SourcePlatformIcon platform={source.platform} iconHint={source.iconHint} size={16} />
          <span className="text-muted-foreground text-xs">{platformName(source)}</span>
        </div>
      </div>
      <span className="text-muted-foreground mt-1 shrink-0 text-xs">›</span>
    </button>
  );
}

function defaultSubtitle(source: AISource): string {
  switch (source.kind) {
    case 'email':
      return 'Email';
    case 'meeting':
      return 'Meeting';
    case 'calendar_event':
      return 'Upcoming Event';
    case 'document':
      return 'Document';
    case 'note':
      return 'Note';
    case 'thread':
      return 'Todus chat thread';
    case 'memory':
      return 'Memory';
    case 'task':
      return 'Task';
    case 'company':
      return 'Company';
    case 'web':
      return source.iconHint ?? 'Website';
  }
}

function platformName(source: AISource): string {
  switch (source.platform) {
    case 'gmail':
      return 'Gmail';
    case 'google_meet':
      return 'Google Meet';
    case 'google_calendar':
      return 'Google Calendar';
    case 'website':
      return source.iconHint ?? 'Website';
    case 'notion':
      return 'Notion';
    case 'document':
      return 'Document';
    case 'notes':
      return 'Note';
    case 'todus':
      return 'Todus';
    case 'memory':
      return 'Memory';
    case 'upsales':
      return 'Upsales';
    case 'unknown':
      return source.iconHint ?? '';
  }
}

// ── Platform Icon ───────────────────────────────────────────────────────────

interface IconProps {
  platform: AISourcePlatform;
  iconHint?: string;
  size: number;
}

function SourcePlatformIcon({ platform, iconHint, size }: IconProps) {
  const wrap = (children: React.ReactNode, bg = 'bg-white') => (
    <span
      className={cn('flex items-center justify-center overflow-hidden rounded-md shadow-sm', bg)}
      style={{ width: size, height: size }}
    >
      {children}
    </span>
  );

  if ((platform === 'website' || platform === 'unknown') && iconHint) {
    return wrap(
      <img
        src={`https://www.google.com/s2/favicons?domain=${encodeURIComponent(iconHint)}&sz=64`}
        alt=""
        className="h-3/4 w-3/4 object-contain"
      />,
    );
  }

  // Simple SF-Symbol-ish glyph fallbacks. The native clients render proper
  // brand artwork; the web build keeps the icons compact and on-brand.
  const glyph = (() => {
    switch (platform) {
      case 'gmail':
        return '✉️';
      case 'google_meet':
        return '🎥';
      case 'google_calendar':
        return '📅';
      case 'notion':
      case 'document':
        return '📄';
      case 'notes':
        return '📝';
      case 'todus':
        return '💬';
      case 'memory':
        return '🧠';
      case 'upsales':
        return '🏢';
      default:
        return '🌐';
    }
  })();

  return wrap(<span style={{ fontSize: size * 0.7, lineHeight: 1 }}>{glyph}</span>);
}
