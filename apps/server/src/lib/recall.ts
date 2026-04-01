/**
 * Recall.ai API client for meeting bot operations.
 *
 * Ported from reference/AA-MCP-MVP/src/lib/server/recall.ts,
 * adapted for our Cloudflare Worker environment.
 */

const DEFAULT_BASE_URL = 'https://us-west-2.recall.ai/api/v1';

interface CreateBotOptions {
  meetingUrl: string;
  botName?: string;
  /** ISO 8601 date-time; omit to join immediately */
  startAtISO?: string;
  metadata?: Record<string, string>;
}

interface RecallBotResponse {
  id: string;
  meeting_url: string;
  bot_name: string;
  status: string;
  join_at?: string;
  created_at: string;
  meeting_url_id?: string;
}

interface TranscriptSegment {
  id?: string;
  start_time: number;
  end_time: number;
  speaker?: { name?: string; id?: string };
  text: string;
  confidence?: number;
}

// ─── Helpers ─────────────────────────────────────────────────────────────

function getConfig(env: { RECALL_API_KEY?: string; RECALL_API_BASE_URL?: string }) {
  const apiKey = env.RECALL_API_KEY;
  const baseUrl = (env.RECALL_API_BASE_URL || DEFAULT_BASE_URL).replace(/\/$/, '');
  return { apiKey, baseUrl };
}

async function recallFetch(
  path: string,
  init: RequestInit,
  env: { RECALL_API_KEY?: string; RECALL_API_BASE_URL?: string },
): Promise<any> {
  const { apiKey, baseUrl } = getConfig(env);
  if (!apiKey) throw new Error('RECALL_API_KEY is not configured');

  const url = `${baseUrl}${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Token ${apiKey}`,
      'Content-Type': 'application/json',
      ...init.headers,
    },
  });

  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`Recall API ${res.status}: ${res.statusText} — ${text.slice(0, 300)}`);
    (err as any).status = res.status;
    throw err;
  }

  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`Recall API response is not valid JSON: ${text.slice(0, 200)}`);
  }
}

/** Simple retry with exponential backoff for 5xx and 429 errors */
async function withRetry<T>(fn: () => Promise<T>, retries = 2, baseDelay = 500): Promise<T> {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (err: any) {
      const status = err?.status;
      const retryable = status && (status >= 500 || status === 429);
      if (attempt === retries || !retryable) throw err;
      await new Promise((r) => setTimeout(r, baseDelay * Math.pow(2, attempt)));
    }
  }
  throw new Error('unreachable');
}

// ─── Public API ──────────────────────────────────────────────────────────

export async function createRecallBot(
  options: CreateBotOptions,
  env: { RECALL_API_KEY?: string; RECALL_API_BASE_URL?: string },
): Promise<RecallBotResponse> {
  const payload: Record<string, any> = {
    meeting_url: options.meetingUrl,
    bot_name: options.botName || 'Note Taker',
    recording_config: {
      transcript: {
        provider: {
          recallai_streaming: { mode: 'prioritize_low_latency', language_code: 'en' },
        },
      },
    },
  };

  if (options.startAtISO) payload.start_time = options.startAtISO;
  if (options.metadata) payload.metadata = options.metadata;

  return withRetry(() =>
    recallFetch('/bot/', { method: 'POST', body: JSON.stringify(payload) }, env),
  );
}

export async function getBotStatus(
  botId: string,
  env: { RECALL_API_KEY?: string; RECALL_API_BASE_URL?: string },
): Promise<RecallBotResponse> {
  return withRetry(() =>
    recallFetch(`/bot/${encodeURIComponent(botId)}/`, { method: 'GET' }, env),
  );
}

export async function cancelBot(
  botId: string,
  env: { RECALL_API_KEY?: string; RECALL_API_BASE_URL?: string },
): Promise<void> {
  await withRetry(() =>
    recallFetch(`/bot/${encodeURIComponent(botId)}/`, { method: 'DELETE' }, env),
  );
}

export async function getBotTranscript(
  botId: string,
  env: { RECALL_API_KEY?: string; RECALL_API_BASE_URL?: string },
): Promise<TranscriptSegment[]> {
  const result = await withRetry(() =>
    recallFetch(`/bot/${encodeURIComponent(botId)}/transcript/`, { method: 'GET' }, env),
  );
  return Array.isArray(result) ? result : result?.results || [];
}
