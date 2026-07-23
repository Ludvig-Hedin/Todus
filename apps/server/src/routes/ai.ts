import {
  getCachedMemories,
  formatMemoriesForPrompt,
  addMemories,
  invalidateMemoryCache,
  preloadMemories,
} from '../lib/mem0';
import {
  type AISource,
  webSourceToAISource,
  mentionToAISource,
  memoriesToAISource,
} from '../lib/ai-sources';
import { injectMentionContextIntoMessages, mentionRefSchema } from '../lib/mentions';
import { resolveModel, isLocalInference } from '../lib/ai-model-resolver';
import { systemPrompt } from '../services/call-service/system-prompt';
import { GENERATIVE_UI_PROMPT } from '../lib/generative-ui-contract';
import { getSharedAIProfilePromptForUser } from '../lib/ai-profile';
import { getSecondBrainDigest } from '../lib/assistant-digest';
import { hasAiCredits, trackAiUsage } from '../lib/billing';
import { serializedFileSchema } from '../lib/schemas';
import { perplexity } from '@ai-sdk/perplexity';
import type { HonoContext } from '../ctx';
import { tools } from './agent/tools';
import { generateText } from 'ai';
import { Tools } from '../types';
import { createDb } from '../db';
import { env } from '../env';
import { Hono } from 'hono';
import { z } from 'zod';

type ToolsReturnType = Awaited<ReturnType<typeof tools>>;

/** Constant-time string comparison. Prevents timing attacks against secret
 *  comparisons (e.g. `===` short-circuits on first mismatched character). */
function timingSafeEqual(a: string | undefined, b: string | undefined): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export const aiRouter = new Hono<HonoContext>();

aiRouter.get('/', (c) => c.text('Twilio + ElevenLabs + AI Phone System Ready'));

const trustedOrigins = new Set(
  [
    'https://app.todus.app',
    'https://api.todus.app',
    'https://todus.app',
    'https://todus-production.ludvighedin15.workers.dev',
    'https://todus-server-v1-production.ludvighedin15.workers.dev',
    'https://zero-server-v1-production.ludvighedin15.workers.dev',
    'http://localhost:3000',
    'http://localhost:8787',
    env.VITE_PUBLIC_APP_URL,
    env.VITE_PUBLIC_BACKEND_URL,
  ].filter((origin): origin is string => Boolean(origin)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Web Search — heuristic detection + Perplexity search + source injection
// ─────────────────────────────────────────────────────────────────────────────

interface WebSearchSource {
  url: string;
  title: string;
  snippet: string;
}

type OpenRouterChatResponse = {
  choices?: Array<{
    message?: {
      content?: unknown;
    };
  }>;
  [key: string]: unknown;
};

type ProviderMetadataResult = {
  experimental_providerMetadata?: {
    perplexity?: {
      citations?: string[];
    };
  };
};

type GeminiClientTurn = {
  parts?: Array<{
    text?: unknown;
  }>;
};

type GeminiClientFrame = {
  realtimeInput?: {
    audio?: { data?: unknown };
    media?: { data?: unknown };
  };
  clientContent?: {
    turns?: GeminiClientTurn[];
  };
};

/** Heuristic: does this user message likely need current web information?
 *  Two-tier check: time-sensitive keywords trigger immediately,
 *  factual questions only trigger if they don't look like task/email/calendar commands. */
function shouldSearchWeb(content: string): boolean {
  // Skip search for obvious task/email/calendar management commands
  const taskPatterns =
    /\b(create|add|delete|remove|update|mark|complete|schedule|send|reply|forward|draft|compose|remind)\b.*\b(task|email|event|meeting|reminder|calendar)\b/i;
  if (taskPatterns.test(content)) return false;

  // Tier 1: Time-sensitive — always search (evaluated before shortCommand so
  // short queries like "weather today" or "stock price" still trigger search)
  const timeSensitive =
    /\b(latest|current|today|yesterday|news|price|who won|what happened|recent|update|2025|2026|stock|weather|score|trending|this week|this month)\b/i;
  if (timeSensitive.test(content)) return true;

  // Short commands (≤3 words) that aren't time-sensitive are likely task/action commands
  const shortCommand = content.trim().split(/\s+/).length <= 3;
  if (shortCommand) return false;

  // Tier 2: Factual questions — search unless they're about the user's own data
  const factualQuestion =
    /\b(what is|who is|how to|how does|where is|when did|why did|tell me about|explain|compare|difference between|pros and cons)\b/i;
  const aboutOwnData = /\b(my task|my email|my calendar|my event|my schedule|my inbox)\b/i;
  if (factualQuestion.test(content) && !aboutOwnData.test(content)) return true;

  return false;
}

/** Call Tavily Search API and return structured sources + a summary context string.
 *  Tavily is preferred: it's a pure search API (faster, cheaper, returns real snippets).
 *  Falls back to Perplexity sonar if no TAVILY_API_KEY is configured. */
async function performWebSearch(
  query: string,
  env: { TAVILY_API_KEY?: string; PERPLEXITY_API_KEY?: string },
): Promise<{ text: string; sources: WebSearchSource[] }> {
  if (env.TAVILY_API_KEY) {
    return searchWithTavily(query, env.TAVILY_API_KEY);
  }
  if (env.PERPLEXITY_API_KEY) {
    return searchWithPerplexity(query);
  }
  // Neither key configured — return empty (AI will answer from its own knowledge)
  return { text: '', sources: [] };
}

/** Tavily: fast structured search, returns title + url + content snippet per result. */
async function searchWithTavily(
  query: string,
  apiKey: string,
): Promise<{ text: string; sources: WebSearchSource[] }> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 8000);

  let response: Response;
  try {
    response = await fetch('https://api.tavily.com/search', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key: apiKey,
        query,
        search_depth: 'basic', // 'basic' uses 1 credit, 'advanced' uses 2
        include_answer: true, // Tavily's own short answer — useful for the summary
        include_raw_content: false,
        max_results: 5,
      }),
      signal: controller.signal,
    });
  } catch (err: unknown) {
    if (err instanceof Error && err.name === 'AbortError') {
      throw new Error('Tavily API request timed out');
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    throw new Error(`Tavily API error: ${response.status}`);
  }

  const data = (await response.json()) as {
    answer?: string;
    results?: { url: string; title: string; content: string; score: number }[];
  };

  const sources: WebSearchSource[] = (data.results ?? []).map((r) => ({
    url: r.url,
    title: r.title,
    snippet: r.content?.slice(0, 300) ?? '', // Cap snippet length
  }));

  // Use Tavily's concise answer as the summary injected into the LLM prompt
  const text = data.answer ?? '';
  return { text, sources };
}

/** Perplexity sonar fallback: LLM-powered search, returns citations but no per-source snippets. */
async function searchWithPerplexity(
  query: string,
): Promise<{ text: string; sources: WebSearchSource[] }> {
  const result = await generateText({
    model: perplexity('sonar'),
    system: 'You are a research assistant. Provide factual, well-sourced answers.',
    messages: [{ role: 'user', content: query }],
    maxTokens: 1024,
  });

  // Perplexity returns citation URLs in experimental provider metadata
  const rawCitations: string[] =
    (result as ProviderMetadataResult).experimental_providerMetadata?.perplexity?.citations ?? [];
  const sources: WebSearchSource[] = rawCitations.map((url: string) => ({
    url,
    title: (() => {
      try {
        return new URL(url).hostname.replace('www.', '');
      } catch {
        return url;
      }
    })(),
    snippet: '',
  }));

  return { text: result.text, sources };
}

/** Inject search results into the message array as a system message before the last user message. */
function injectSearchContext<T extends { role: string }>(
  messages: T[],
  searchText: string,
  sources: WebSearchSource[],
): T[] {
  if (sources.length === 0) return messages;

  const sourcesBlock = sources
    .map(
      (s, i) => `[${i + 1}] "${s.title}" — ${s.url}\n${s.snippet || '(see search summary below)'}`,
    )
    .join('\n\n');

  const searchContext = `## Web Search Results
The following web sources are relevant to the user's question.
You MUST cite sources inline using [1], [2] etc. Every factual claim MUST include a citation number.
Do NOT list sources at the end — the app renders source cards separately.

${sourcesBlock}

## Search Summary
${searchText}`;

  // Insert as a system message right before the last user message
  const lastUserIdx = messages.map((m) => m.role).lastIndexOf('user');
  if (lastUserIdx === -1) return messages;

  const result = [...messages];
  result.splice(lastUserIdx, 0, { role: 'system', content: searchContext } as unknown as T);
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mobile AI Chat — SSE streaming proxy to OpenRouter
// Authenticates via Bearer token (set by main middleware → c.var.sessionUser).
// The iOS app sends the same payload format as the old Supabase edge function.
// ─────────────────────────────────────────────────────────────────────────────

const toolCallSchema = z.object({
  id: z.string(),
  type: z.literal('function').optional(),
  function: z.object({
    name: z.string(),
    arguments: z.string(),
  }),
});

// Allow assistant messages with tool_calls and tool role messages with tool_call_id.
// content is optional for assistant-with-tool-calls, string for user/system/tool.
const chatMessageSchema = z
  .object({
    role: z.string(),
    content: z.union([z.string(), z.null()]).optional(),
    tool_calls: z.array(toolCallSchema).optional(),
    tool_call_id: z.string().optional(),
    name: z.string().optional(),
  })
  .passthrough();

type ChatMessage = z.infer<typeof chatMessageSchema>;

const chatRequestSchema = z.object({
  messages: z.array(chatMessageSchema),
  mentions: z.array(mentionRefSchema).optional(),
  tasks: z.array(z.any()).optional(),
  model: z.string().optional(),
  stream: z.boolean().optional().default(true),
  /** Base64-encoded files from the client; merged into the last user message for the model */
  attachments: z.array(serializedFileSchema).optional(),
  /**
   * Whether the requesting client can render generative-UI inline cards
   * (InlineComposeCard, TaskListCard, EmailListCard, …). When false we skip
   * injecting the ~21KB GENERATIVE_UI_PROMPT, saving tokens for clients that
   * only render plain markdown. Defaults to true for backward compatibility
   * with existing clients that don't send this flag.
   */
  supportsGenerativeUI: z.boolean().optional().default(true),
});

const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024;
const MAX_TOTAL_ATTACHMENT_BYTES = 12 * 1024 * 1024;

type OpenAIContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string } };

function isTextLikeMime(mime: string, filename: string): boolean {
  const m = mime.toLowerCase();
  if (m.startsWith('text/')) return true;
  if (
    m === 'application/json' ||
    m === 'application/xml' ||
    m === 'application/javascript' ||
    m === 'application/x-sh' ||
    m === 'application/sql' ||
    m === 'application/yaml' ||
    m === 'application/x-yaml'
  ) {
    return true;
  }
  const ext = filename.includes('.') ? (filename.split('.').pop() ?? '').toLowerCase() : '';
  return [
    'txt',
    'md',
    'markdown',
    'csv',
    'log',
    'json',
    'xml',
    'yaml',
    'yml',
    'swift',
    'ts',
    'tsx',
    'js',
    'jsx',
    'mjs',
    'cjs',
    'html',
    'htm',
    'css',
    'scss',
    'sass',
    'less',
    'sql',
    'sh',
    'bash',
    'zsh',
    'env',
    'toml',
    'ini',
    'cfg',
    'conf',
    'properties',
    'plist',
    'rss',
    'svg',
  ].includes(ext);
}

/** Merge chat file attachments into the last user message (OpenAI multimodal + text inlining). */
function mergeAttachmentsIntoLastUserMessage(
  messages: Record<string, unknown>[],
  attachments: z.infer<typeof serializedFileSchema>[] | undefined,
): Record<string, unknown>[] {
  if (!attachments?.length) return messages;

  let totalBytes = 0;
  const filtered: { att: z.infer<typeof serializedFileSchema>; buf: Buffer }[] = [];
  for (const att of attachments) {
    const buf = Buffer.from(att.base64, 'base64');
    if (buf.length > MAX_ATTACHMENT_BYTES) continue;
    if (totalBytes + buf.length > MAX_TOTAL_ATTACHMENT_BYTES) break;
    totalBytes += buf.length;
    filtered.push({ att, buf });
  }
  if (!filtered.length) return messages;

  const lastUserIdx = messages.map((m) => m.role).lastIndexOf('user');
  if (lastUserIdx === -1) return messages;

  const userMsg = messages[lastUserIdx];
  const rawContent = userMsg.content;

  const parts: OpenAIContentPart[] = [];
  if (typeof rawContent === 'string') {
    if (rawContent.trim().length) {
      parts.push({ type: 'text', text: rawContent });
    }
  } else if (Array.isArray(rawContent)) {
    for (const part of rawContent as OpenAIContentPart[]) {
      parts.push(part);
    }
  }

  for (const { att, buf } of filtered) {
    const mime = (att.type || 'application/octet-stream').toLowerCase();

    if (mime.startsWith('image/')) {
      parts.push({
        type: 'image_url',
        image_url: { url: `data:${mime};base64,${att.base64}` },
      });
    } else if (isTextLikeMime(mime, att.name)) {
      const text = buf.toString('utf8');
      const capped = text.length > 400_000 ? `${text.slice(0, 400_000)}\n…(truncated)` : text;
      parts.push({
        type: 'text',
        text: `\n\n---\nFile: ${att.name}\n---\n${capped}\n`,
      });
    } else {
      parts.push({
        type: 'text',
        text: `\n\n[Attached file: ${att.name} (${mime}, ${buf.length} bytes). This file is not fully inlined; use the user's message and filename for context.]\n`,
      });
    }
  }

  if (parts.length === 0) return messages;

  const hasImage = parts.some((p) => p.type === 'image_url');
  if (!hasImage && parts.length === 1 && parts[0].type === 'text') {
    const out = [...messages];
    out[lastUserIdx] = { ...userMsg, content: parts[0].text };
    return out;
  }

  const out = [...messages];
  out[lastUserIdx] = { ...userMsg, content: parts };
  return out;
}

aiRouter.post('/chat', async (c) => {
  const user = c.var.sessionUser;
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const body = await c.req.json();
  const parsed = chatRequestSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid request' }, 400);

  const apiKey = env.OPENROUTER_API_SECRET ?? env.OPENROUTER_API_KEY;
  if (!apiKey) return c.json({ error: 'AI not configured' }, 503);

  const model = parsed.data.model || env.DEFAULT_MODEL || 'openai/gpt-4.1-mini';

  // On-device requests (Ollama-routed apps/web flows, defensive coverage for any
  // local model id that leaks through from the native apps) are never billed —
  // the user is paying for their own compute. Skip both pre-flight and the
  // post-stream usage track. Local runtimes on iOS/macOS bypass this route
  // entirely, so this branch is purely defensive.
  const skipBilling = isLocalInference({ modelId: model });

  if (!skipBilling) {
    // Pre-flight: block if the user has exhausted their AI credits.
    // Cached read (~1ms). Fails open if the lookup itself errors — we never want
    // a billing-cache hiccup to take chat down.
    try {
      const allowed = await hasAiCredits(user.id);
      if (!allowed) {
        return c.json(
          { error: 'ai_credits_exhausted', message: 'Out of AI credits. Wait for the next reset.' },
          402,
        );
      }
    } catch (error) {
      console.error('[ai/chat] hasAiCredits check failed (allowing through)', error);
    }
  }

  // ── Mem0: Inject cached memories into the message stream ─────────────────
  // Reads from KV cache (<5ms) or in-memory (0ms). Mem0 API is only hit on
  // full cache miss — preload should have warmed the cache on prior requests.
  const mem0Key = env.MEM0_API_KEY;
  let enrichedMessages = parsed.data.messages;
  let injectedMemories: string[] = [];

  if (mem0Key && user.id) {
    try {
      const memories = await getCachedMemories(user.id, env.prompts_storage, mem0Key);
      const memoryBlock = formatMemoriesForPrompt(memories);
      if (memoryBlock) {
        injectedMemories = memories;
        // Find the existing system message and append memory, or prepend a new one
        const systemIdx = enrichedMessages.findIndex((m) => m.role === 'system');
        if (systemIdx >= 0) {
          enrichedMessages = [...enrichedMessages];
          enrichedMessages[systemIdx] = {
            ...enrichedMessages[systemIdx],
            content: memoryBlock + '\n\n' + enrichedMessages[systemIdx].content,
          };
        } else {
          enrichedMessages = [{ role: 'system', content: memoryBlock }, ...enrichedMessages];
        }
      }
    } catch (error) {
      // Mem0 failure must never block the AI flow
      console.warn('[Mem0] Failed to inject memories into /ai/chat:', error);
    }
  }

  // Detect follow-up step: the client appends `tool` role messages (and optionally
  // an `assistant_with_tool_calls` message) after executing tools, then re-calls
  // /api/ai/chat to get a natural-language reply. On follow-up steps we MUST skip:
  //   - Web search   (already injected on step 1; would otherwise burn credits)
  //   - Mention injection  (already injected on step 1; would otherwise duplicate the block)
  //   - Attachment merge   (already inlined on step 1; would otherwise re-send images)
  // Detection: the last message is a `tool` role, OR any message has tool_calls/tool_call_id.
  const lastMsg = parsed.data.messages[parsed.data.messages.length - 1];
  const isFollowUpStep =
    lastMsg?.role === 'tool' ||
    parsed.data.messages.some((m) => m.role === 'tool' || Boolean(m.tool_calls));

  if (!isFollowUpStep) {
    const mentionMessages = enrichedMessages.map((message) => ({
      ...message,
      content: typeof message.content === 'string' ? message.content : '',
    }));
    enrichedMessages = injectMentionContextIntoMessages(mentionMessages, parsed.data.mentions);
  }

  // ── Web Search: detect, search, inject sources ──────────────────────────
  // Check if the user's last message would benefit from current web information.
  // If so, call Perplexity sonar and inject results + citation instructions.
  const rawLastUserMsg = parsed.data.messages.filter((m) => m.role === 'user').pop();
  const searchQuery = typeof rawLastUserMsg?.content === 'string' ? rawLastUserMsg.content : '';
  const needsSearch = !isFollowUpStep && searchQuery ? shouldSearchWeb(searchQuery) : false;
  let searchSources: WebSearchSource[] = [];

  if (needsSearch && searchQuery) {
    try {
      const searchResult = await performWebSearch(searchQuery, env);
      searchSources = searchResult.sources;
      if (searchSources.length > 0) {
        enrichedMessages = injectSearchContext<ChatMessage>(
          enrichedMessages,
          searchResult.text,
          searchSources,
        );
      }
    } catch (error) {
      // Web search failure must never block the AI flow — proceed without sources
      console.warn('[WebSearch] Perplexity search failed:', error);
    }
  }

  // ── Context sources: union of every piece of context this turn used ──────
  // Surfaced to the client via the `context_sources` SSE event so the UI can
  // render a unified Sources affordance. Tool-call sources are appended
  // client-side after each tool runs.
  const contextSources: AISource[] = [];
  if (!isFollowUpStep && parsed.data.mentions?.length) {
    for (const m of parsed.data.mentions) {
      contextSources.push(mentionToAISource(m));
    }
  }
  const memorySource = memoriesToAISource(injectedMemories);
  if (memorySource) contextSources.push(memorySource);
  for (const s of searchSources) {
    contextSources.push(webSourceToAISource(s));
  }

  try {
    const sharedAIProfilePrompt = await getSharedAIProfilePromptForUser(user.id, {
      name: user.name,
      email: user.email,
    });
    if (sharedAIProfilePrompt) {
      const systemIdx = enrichedMessages.findIndex((m) => m.role === 'system');
      if (systemIdx >= 0) {
        enrichedMessages = [...enrichedMessages];
        // Append profile AFTER base system instructions so core rules take precedence
        enrichedMessages[systemIdx] = {
          ...enrichedMessages[systemIdx],
          content: `${enrichedMessages[systemIdx].content}\n\n${sharedAIProfilePrompt}`,
        };
      } else {
        enrichedMessages = [
          { role: 'system', content: sharedAIProfilePrompt },
          ...enrichedMessages,
        ];
      }
    }
  } catch (error) {
    console.warn('[AIProfile] Failed to inject AI profile into /ai/chat for user:', user.id, error);
  }

  // ── Second-brain digest: open loops + active workstreams ─────────────────
  // Native clients execute tools locally, so they can't reach the ZeroAgent
  // memory tools (getPersonContext etc.). Inject a compact ambient digest
  // instead. Empty (and skipped) until the briefing sync has populated the
  // assistant_* tables. Failure must never block the chat flow.
  try {
    const digest = await getSecondBrainDigest(user.id);
    if (digest) {
      const systemIdx = enrichedMessages.findIndex((m) => m.role === 'system');
      if (systemIdx >= 0) {
        enrichedMessages = [...enrichedMessages];
        enrichedMessages[systemIdx] = {
          ...enrichedMessages[systemIdx],
          content: `${enrichedMessages[systemIdx].content}\n\n${digest}`,
        };
      } else {
        enrichedMessages = [{ role: 'system', content: digest }, ...enrichedMessages];
      }
    }
  } catch (error) {
    console.warn('[SecondBrain] Failed to inject digest into /ai/chat for user:', user.id, error);
  }

  // Inject the generative-UI catalog so the AI knows which inline cards it can render
  // (InlineComposeCard, TaskListCard, EmailListCard, etc.). Without this, clients only see
  // plain markdown — no rich card UI. Append to the existing system message so client-side
  // base rules still take precedence.
  //
  // Gated by the client's capability flag (B-025): only clients that can actually
  // render these cards pay the ~21KB prompt cost. Defaults to true so existing
  // clients are unaffected.
  if (parsed.data.supportsGenerativeUI) {
    const systemIdx = enrichedMessages.findIndex((m) => m.role === 'system');
    if (systemIdx >= 0) {
      enrichedMessages = [...enrichedMessages];
      enrichedMessages[systemIdx] = {
        ...enrichedMessages[systemIdx],
        content: `${enrichedMessages[systemIdx].content}\n\n${GENERATIVE_UI_PROMPT}`,
      };
    } else {
      enrichedMessages = [{ role: 'system', content: GENERATIVE_UI_PROMPT }, ...enrichedMessages];
    }
  }

  // Skip attachment merge on follow-up steps — they were already inlined on step 1
  // and re-merging would duplicate images/text inside an already-multimodal user message.
  if (!isFollowUpStep) {
    enrichedMessages = mergeAttachmentsIntoLastUserMessage(
      enrichedMessages as Record<string, unknown>[],
      parsed.data.attachments,
    ) as typeof parsed.data.messages;
  }

  // Respect the `stream` flag from the request — non-streaming mode is used by
  // NotificationDigestService (and any other caller that needs a plain JSON response).
  const shouldStream = parsed.data.stream !== false;

  const upstreamRequestBody = {
    model,
    messages: enrichedMessages,
    stream: shouldStream,
    // Ask OpenRouter to include token usage in the final SSE chunk so we can
    // bill the user for actual cost. No-op for non-streaming responses
    // (which include `usage` on the response object directly).
    ...(shouldStream ? { stream_options: { include_usage: true } } : {}),
    // Include tool definitions for task mutations
    tools: [
      {
        type: 'function',
        function: {
          name: 'create_task',
          description: 'Create a new task for the user',
          parameters: {
            type: 'object',
            properties: {
              title: { type: 'string', description: 'Task title' },
              dueDate: { type: 'string', description: 'ISO 8601 due date (optional)' },
              folderName: { type: 'string', description: 'Folder name (optional)' },
              priority: {
                type: 'string',
                // 'urgent' excluded — server schema only accepts ['none','low','medium','high']
                enum: ['none', 'low', 'medium', 'high'],
                description: 'Task priority',
              },
            },
            required: ['title'],
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'update_task',
          description: 'Update an existing task',
          parameters: {
            type: 'object',
            properties: {
              id: { type: 'string', description: 'Task UUID' },
              title: { type: 'string' },
              status: { type: 'string', enum: ['todo', 'doing', 'done'] },
              priority: { type: 'string', enum: ['none', 'low', 'medium', 'high'] },
              dueDate: { type: 'string' },
            },
            required: ['id'],
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'delete_task',
          description: 'Delete a task',
          parameters: {
            type: 'object',
            properties: {
              id: { type: 'string', description: 'Task UUID to delete' },
            },
            required: ['id'],
          },
        },
      },
      // ── Calendar ──────────────────────────────────────────────────────────
      {
        type: 'function',
        function: {
          name: 'create_calendar_event',
          description: "Create a new calendar event on the user's device calendar",
          parameters: {
            type: 'object',
            properties: {
              title: { type: 'string', description: 'Event title' },
              startDate: {
                type: 'string',
                description: 'ISO 8601 start datetime, e.g. 2025-04-01T09:00:00',
              },
              endDate: {
                type: 'string',
                description: 'ISO 8601 end datetime (optional, defaults to 1 hour after start)',
              },
              notes: { type: 'string', description: 'Optional notes or description for the event' },
            },
            required: ['title', 'startDate'],
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'update_calendar_event',
          description:
            'Update an existing calendar event. Use the event identifier from the calendar context.',
          parameters: {
            type: 'object',
            properties: {
              id: { type: 'string', description: 'Event identifier' },
              title: { type: 'string' },
              startDate: { type: 'string', description: 'ISO 8601 start datetime' },
              endDate: { type: 'string', description: 'ISO 8601 end datetime' },
              notes: { type: 'string' },
            },
            required: ['id'],
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'delete_calendar_event',
          description: 'Delete a calendar event by its identifier',
          parameters: {
            type: 'object',
            properties: {
              id: { type: 'string', description: 'Event identifier to delete' },
            },
            required: ['id'],
          },
        },
      },
      // ── Email ──────────────────────────────────────────────────────────────
      {
        type: 'function',
        function: {
          name: 'send_email',
          description: 'Send an email or reply to an existing thread on behalf of the user',
          parameters: {
            type: 'object',
            properties: {
              to: {
                type: 'array',
                items: { type: 'string' },
                description: 'Array of recipient email addresses',
              },
              subject: { type: 'string', description: 'Email subject line' },
              body: { type: 'string', description: 'Email body in plain text or simple HTML' },
              threadId: {
                type: 'string',
                description: 'Thread ID to reply to (omit for new email)',
              },
            },
            required: ['to', 'subject', 'body'],
          },
        },
      },
    ],
  };

  // Forward the inbound abort signal so that when a client disconnects (e.g. iOS
  // force-quit during a long completion) we tear down the upstream OpenRouter
  // request instead of continuing to read tokens and bill against the API key.
  const upstreamAbortController = new AbortController();
  const clientAbortSignal = c.req.raw.signal;
  if (clientAbortSignal) {
    if (clientAbortSignal.aborted) {
      upstreamAbortController.abort(clientAbortSignal.reason);
    } else {
      clientAbortSignal.addEventListener(
        'abort',
        () => upstreamAbortController.abort(clientAbortSignal.reason),
        { once: true },
      );
    }
  }

  const fetchUpstreamResponse = () =>
    fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://todus.app',
        'X-Title': 'Todus AI',
      },
      body: JSON.stringify(upstreamRequestBody),
      signal: upstreamAbortController.signal,
    });

  const mem0LastUserMsg = parsed.data.messages.filter((m) => m.role === 'user').pop();
  let assistantText = '';
  const userId = user.id;
  const persistConversationMemory = async (assistantContent: string) => {
    if (!mem0Key || !userId || !mem0LastUserMsg || assistantContent.length <= 10) return;

    await addMemories(mem0Key, userId, [
      {
        role: 'user',
        content: typeof mem0LastUserMsg.content === 'string' ? mem0LastUserMsg.content : '',
      },
      { role: 'assistant', content: assistantContent },
    ]);
    await invalidateMemoryCache(userId, env.prompts_storage);
    await preloadMemories(userId, env.prompts_storage, mem0Key);
  };

  if (!shouldStream) {
    const upstreamResponse = await fetchUpstreamResponse();
    if (!upstreamResponse.ok || !upstreamResponse.body) {
      const errorText = await upstreamResponse.text().catch(() => 'Unknown error');
      return c.json(
        { error: `AI provider error: ${upstreamResponse.status}`, details: errorText },
        502,
      );
    }

    const responseData = (await upstreamResponse.json()) as OpenRouterChatResponse;
    const assistantContent =
      typeof responseData?.choices?.[0]?.message?.content === 'string'
        ? responseData.choices[0].message.content
        : '';

    if (assistantContent) {
      const storePromise = persistConversationMemory(assistantContent).catch((error) => {
        console.warn('[Mem0] Non-stream memory storage failed:', error);
      });
      c.executionCtx?.waitUntil?.(storePromise);
    }

    return c.json({
      ...responseData,
      searchSources,
      contextSources,
    });
  }

  // ── Build SSE response stream ────────────────────────────────────────────
  // We use a custom ReadableStream to:
  // 1. Open the SSE response immediately so native clients don't time out
  //    while waiting for the upstream provider to produce headers
  // 2. Write web search custom events (search_status, sources) before the LLM response
  // 3. Pipe upstream OpenRouter SSE through unchanged
  // 4. Capture assistant text for Mem0 memory storage (fire-and-forget)
  const encoder = new TextEncoder();

  // Hoisted so the stream's `cancel()` (fired by the runtime when the client
  // disconnects) can release it and stop draining the upstream.
  let upstreamReader: ReadableStreamDefaultReader<Uint8Array> | null = null;

  const responseStream = new ReadableStream({
    async start(controller) {
      try {
        // Emit a tiny bootstrap event immediately so the client receives bytes even
        // if the upstream model spends a long time planning tools before first token.
        controller.enqueue(
          encoder.encode(
            `data: ${JSON.stringify({ type: 'stream_status', status: 'connecting' })}\n\n`,
          ),
        );

        // 1. Write web search custom events before the LLM answer.
        //    Already gated by needsSearch (which is false on follow-up steps),
        //    so this block won't fire on round-2+ tool-result replays.
        if (needsSearch && searchQuery) {
          controller.enqueue(
            encoder.encode(
              `data: ${JSON.stringify({ type: 'search_status', status: 'searching', queries: [searchQuery] })}\n\n`,
            ),
          );
        }
        if (searchSources.length > 0) {
          controller.enqueue(
            encoder.encode(
              `data: ${JSON.stringify({ type: 'sources', sources: searchSources })}\n\n`,
            ),
          );
        } else if (needsSearch && searchQuery) {
          controller.enqueue(
            encoder.encode(
              `data: ${JSON.stringify({ type: 'search_status', status: 'idle', queries: [searchQuery] })}\n\n`,
            ),
          );
        }

        // Unified context sources (web + mentions + memories). Web sources
        // are duplicated here on purpose — clients dedupe by `id` and use
        // the legacy `sources` event only for `[n]` citation numbering.
        if (contextSources.length > 0) {
          controller.enqueue(
            encoder.encode(
              `data: ${JSON.stringify({ type: 'context_sources', sources: contextSources })}\n\n`,
            ),
          );
        }

        const upstreamResponse = await fetchUpstreamResponse();
        if (!upstreamResponse.ok || !upstreamResponse.body) {
          const errorText = await upstreamResponse.text().catch(() => 'Unknown error');
          controller.enqueue(
            encoder.encode(
              `data: ${JSON.stringify({
                type: 'error',
                message: `AI provider error (${upstreamResponse.status}).`,
                details: errorText,
              })}\n\n`,
            ),
          );
          controller.close();
          return;
        }

        // 2. Pipe upstream OpenRouter SSE through, capturing content for Mem0
        if (!upstreamResponse.body) {
          controller.close();
          return;
        }
        const reader = upstreamResponse.body.getReader();
        upstreamReader = reader;
        const decoder = new TextDecoder();
        let reasoningStartTime = 0;
        let hasReasoning = false;
        // OpenRouter emits usage on the final chunk when stream_options.include_usage=true.
        let usagePromptTokens = 0;
        let usageCompletionTokens = 0;
        // Buffer SSE bytes across reads. OpenRouter routinely emits 1–2 KB events
        // that don't align with HTTP chunk boundaries; splitting per chunk drops
        // the trailing usage event (silently zero-billing the turn) and partial
        // reasoning tokens. SSE event terminator is a blank line: \n\n.
        let buffer = '';

        const parseEvent = (rawLines: string[]): void => {
          // An event is one or more `data: ...` lines. Concatenate per spec.
          const dataLines = rawLines.filter((l) => l.startsWith('data: '));
          if (dataLines.length === 0) return;
          const json = dataLines.map((l) => l.slice(6)).join('\n');
          if (json === '[DONE]') return;
          let sseChunk: unknown;
          try {
            sseChunk = JSON.parse(json);
          } catch {
            // Genuinely malformed payload — skip but don't kill the stream.
            return;
          }
          const obj = sseChunk as {
            usage?: { prompt_tokens?: number; completion_tokens?: number };
            choices?: {
              delta?: { content?: string; reasoning?: string; reasoning_content?: string };
            }[];
          };
          const delta = obj.choices?.[0]?.delta;

          if (obj.usage) {
            usagePromptTokens = Number(obj.usage.prompt_tokens ?? 0);
            usageCompletionTokens = Number(obj.usage.completion_tokens ?? 0);
          }

          if (delta?.content) assistantText += delta.content;

          const reasoningToken = delta?.reasoning_content ?? delta?.reasoning;
          if (reasoningToken) {
            if (!hasReasoning) {
              reasoningStartTime = Date.now();
              hasReasoning = true;
            }
            try {
              controller.enqueue(
                encoder.encode(
                  `data: ${JSON.stringify({ type: 'reasoning', content: reasoningToken })}\n\n`,
                ),
              );
            } catch {
              // Controller closed (client gone). Stop trying to enqueue.
            }
          }

          if (hasReasoning && delta?.content && reasoningStartTime > 0) {
            const durationMs = Date.now() - reasoningStartTime;
            try {
              controller.enqueue(
                encoder.encode(
                  `data: ${JSON.stringify({ type: 'reasoning_done', duration_ms: durationMs })}\n\n`,
                ),
              );
            } catch {
              // Controller closed.
            }
            reasoningStartTime = 0;
          }
        };

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          // Pass raw bytes through to the client unchanged.
          controller.enqueue(value);

          // Append decoded text to buffer; flush all complete events (\n\n-separated).
          buffer += decoder.decode(value, { stream: true });
          let sepIdx: number;
          while ((sepIdx = buffer.indexOf('\n\n')) !== -1) {
            const eventBlock = buffer.slice(0, sepIdx);
            buffer = buffer.slice(sepIdx + 2);
            const lines = eventBlock.split('\n');
            parseEvent(lines);
          }
        }

        // Flush any trailing event that didn't end with \n\n.
        if (buffer.trim().length > 0) {
          parseEvent(buffer.split('\n'));
          buffer = '';
        }

        // 3. Mem0: store conversation memory after stream completes (fire-and-forget)
        if (mem0Key && userId && mem0LastUserMsg && assistantText.length > 10) {
          const storePromise = persistConversationMemory(assistantText).catch((error) => {
            console.warn('[Mem0] Post-stream memory storage failed:', error);
          });
          c.executionCtx?.waitUntil?.(storePromise);
        }

        // 4. Bill the user for actual cost. Fire-and-forget — never block the
        // close. If usage was missing from the stream (some models don't emit
        // it), we skip — better than charging a guess. Local-inference
        // requests (Ollama / on-device curated models) are exempt — see
        // `isLocalInference` and `skipBilling` above.
        if (!skipBilling && userId && (usagePromptTokens > 0 || usageCompletionTokens > 0)) {
          c.executionCtx?.waitUntil?.(
            trackAiUsage({
              userId,
              model,
              inputTokens: usagePromptTokens,
              outputTokens: usageCompletionTokens,
            }).catch((error) => {
              console.error('[ai/chat] trackAiUsage failed', error);
            }),
          );
        }

        controller.close();
      } catch (error) {
        // Aborts (client disconnect) are an expected unwind path — bail without
        // emitting a fake "stream failed" payload to a socket that's already gone.
        if (
          (error as { name?: string })?.name === 'AbortError' ||
          upstreamAbortController.signal.aborted
        ) {
          try {
            controller.close();
          } catch {
            /* already closed */
          }
          return;
        }
        const message = error instanceof Error ? error.message : 'Unknown stream error';
        controller.enqueue(
          encoder.encode(
            `data: ${JSON.stringify({ type: 'error', message: 'AI stream failed before completion.', details: message })}\n\n`,
          ),
        );
        controller.close();
      }
    },
    cancel(reason) {
      // Client disconnected. Abort the upstream fetch so OpenRouter stops
      // generating tokens we're no longer reading (and that we'd be billed for).
      try {
        upstreamReader?.cancel(reason).catch(() => {});
      } catch {
        /* noop */
      }
      try {
        upstreamAbortController.abort(reason);
      } catch {
        /* noop */
      }
    },
  });

  return new Response(responseStream, {
    status: 200,
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    },
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Voice WebSocket Proxy — transparent bidirectional relay to Gemini Live.
// The Gemini API key NEVER leaves the server. Clients authenticate with their
// normal Bearer token (same as all other API calls). The proxy forwards every
// WebSocket message between client ↔ Gemini without inspecting or modifying
// the payload, so all Gemini wire-protocol logic stays in the iOS provider.
// ─────────────────────────────────────────────────────────────────────────────

// Diagnostic endpoint — checks if Gemini Live is reachable without requiring a WS upgrade.
// Useful for confirming the API key and BidiGenerateContent endpoint are working.
aiRouter.get('/voice-ping', async (c) => {
  const user = c.var.sessionUser;
  if (!user) return c.json({ ok: false, error: 'Unauthorized' }, 401);

  const apiKey = env.GOOGLE_GENERATIVE_AI_API_KEY;
  if (!apiKey) return c.json({ ok: false, error: 'GOOGLE_GENERATIVE_AI_API_KEY not set' }, 503);

  // Use https:// — Cloudflare Workers outbound WebSocket requires https/http scheme.
  // Pass the API key via the x-goog-api-key header instead of a query string so it does
  // not end up in proxy/access logs or echoed back inside upstream error bodies.
  const geminiUrl =
    'https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  try {
    const resp = await fetch(geminiUrl, {
      headers: { Upgrade: 'websocket', 'x-goog-api-key': apiKey },
    });
    if (resp.webSocket) {
      resp.webSocket.accept();
      resp.webSocket.close(1000, 'ping');
      return c.json({ ok: true, status: 101 });
    }
    const body = await resp.text().catch(() => '');
    console.error('[voice-ping] Gemini returned non-WS response', { status: resp.status, body });
    return c.json({ ok: false, status: resp.status, body }, 502);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[voice-ping] fetch error', msg);
    return c.json({ ok: false, error: msg }, 502);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// /voice/system-prompt — single source of truth for the Gemini Live system
// instruction used by the macOS app and (later) the Pi voice daemon.
//
// Centralizing here means:
//   • Mem0 cache stays warm in one place
//   • AI profile (name/email/locale/custom instructions) is identical across
//     voice and text chat
//   • The voice persona block can evolve without shipping a new app build
//
// The route is intentionally read-only and idempotent — clients may call it
// once per session, or every connect, with sub-5ms latency in the warm path.
// ─────────────────────────────────────────────────────────────────────────────
aiRouter.get('/voice/system-prompt', async (c) => {
  const user = c.var.sessionUser;
  if (!user) {
    return c.json({ error: 'unauthenticated' }, 401);
  }

  // Voice persona — kept short on purpose. Gemini Live latency is sensitive to
  // setup payload size, and the model handles "be concise / spoken not written"
  // better with terse rules than with paragraphs.
  const PERSONA = [
    'You are Todus, a calm, capable voice assistant.',
    'This is a spoken conversation — keep replies short and natural, not written prose.',
    'No bullet lists, no markdown, no "as an AI" filler.',
    'Confirm only when useful. Ask a clarifying question if the request is ambiguous.',
    'For destructive actions (delete, send, cancel) confirm before running the tool.',
    'If a tool call fails, say so plainly and offer the next step.',
  ].join('\n');

  const mem0Key = env.MEM0_API_KEY;
  let memories: string[] = [];
  if (mem0Key) {
    try {
      memories = await getCachedMemories(user.id, env.prompts_storage, mem0Key);
    } catch (error) {
      // Memory failure must never block voice — log and proceed without it.
      console.warn('[voice/system-prompt] getCachedMemories failed:', error);
    }
  }
  const memoryBlock = formatMemoriesForPrompt(memories);

  let aiProfile = '';
  try {
    aiProfile = await getSharedAIProfilePromptForUser(user.id, {
      name: user.name,
      email: user.email,
    });
  } catch (error) {
    console.warn('[voice/system-prompt] getSharedAIProfilePromptForUser failed:', error);
  }

  const sections = [PERSONA, aiProfile, memoryBlock]
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  const systemInstruction = sections.join('\n\n');

  return c.json({
    systemInstruction,
    persona: PERSONA,
    memoriesCount: memories.length,
    generatedAt: new Date().toISOString(),
  });
});

aiRouter.get('/voice-ws', async (c) => {
  // Validate the upgrade header BEFORE creating a WebSocket pair — if the client didn't ask
  // for a WebSocket, returning 101 with a webSocket would be malformed.
  const upgradeHeader = c.req.header('Upgrade');
  if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
    return c.text('Expected WebSocket upgrade', 426);
  }

  // Create the WebSocket pair up-front so all subsequent failure modes (auth, missing key,
  // credits, Gemini rejecting upstream) can surface to the client as a real WS close
  // with a descriptive reason. Returning a non-101 HTTP response here makes URLSession
  // bubble up an opaque -1011 "bad server response" with zero context.
  const pair = new WebSocketPair();
  const [clientWs, serverWs] = Object.values(pair);
  serverWs.accept();

  const wsResponse = new Response(null, {
    status: 101,
    webSocket: clientWs,
  } as ResponseInit & { webSocket: WebSocket });

  // Helper: surface an error to the client over the WS, then close. The client parses
  // the JSON message in its receive loop and shows a real reason. close() reasons are
  // capped at 123 bytes by the WS spec.
  const fail = (closeCode: number, errorTag: string, message: string) => {
    try {
      serverWs.send(JSON.stringify({ error: errorTag, message }));
    } catch {
      /* client may already have given up */
    }
    try {
      serverWs.close(closeCode, message.slice(0, 120));
    } catch {
      /* already closed */
    }
    return wsResponse;
  };

  const user = c.var.sessionUser;
  if (!user) {
    return fail(4401, 'unauthenticated', 'Sign in to use voice chat.');
  }

  const apiKey = env.GOOGLE_GENERATIVE_AI_API_KEY;
  if (!apiKey) {
    console.error('[voice-ws] GOOGLE_GENERATIVE_AI_API_KEY is not set on this environment');
    return fail(
      4503,
      'voice_not_configured',
      'Voice chat is not configured on the server (missing API key).',
    );
  }

  // Pre-flight: block voice if user is out of AI credits. Same pattern as text chat.
  try {
    const allowed = await hasAiCredits(user.id);
    if (!allowed) {
      return fail(4402, 'ai_credits_exhausted', 'Out of AI credits. Wait for the next reset.');
    }
  } catch (error) {
    console.error('[voice-ws] hasAiCredits check failed (allowing through)', error);
  }

  // Voice billing: meter only after the user actually sends billable input
  // (audio/text/media), not from raw socket open time.
  let sessionStartedAt: number | null = null;
  let voiceTrackingDone = false;
  const maybeMarkVoiceSessionStarted = (rawData: string | ArrayBuffer) => {
    if (sessionStartedAt !== null) return;

    let text: string | null = null;
    if (typeof rawData === 'string') {
      text = rawData;
    } else if (rawData instanceof ArrayBuffer) {
      text = new TextDecoder().decode(rawData);
    }
    if (!text) return;

    try {
      const parsed = JSON.parse(text) as GeminiClientFrame;
      const hasRealtimeAudio =
        typeof parsed?.realtimeInput?.audio?.data === 'string' &&
        parsed.realtimeInput.audio.data.length > 0;
      const hasRealtimeMedia =
        typeof parsed?.realtimeInput?.media?.data === 'string' &&
        parsed.realtimeInput.media.data.length > 0;
      const hasClientText =
        Array.isArray(parsed?.clientContent?.turns) &&
        parsed.clientContent.turns.some(
          (turn) =>
            Array.isArray(turn?.parts) &&
            turn.parts.some(
              (part) => typeof part?.text === 'string' && part.text.trim().length > 0,
            ),
        );

      if (hasRealtimeAudio || hasRealtimeMedia || hasClientText) {
        sessionStartedAt = Date.now();
      }
    } catch {
      // Ignore non-JSON / partial frames — they are not billable activity markers.
    }
  };
  const trackVoiceUsage = () => {
    if (voiceTrackingDone) return;
    voiceTrackingDone = true;
    if (sessionStartedAt === null) return;
    const durationMs = Date.now() - sessionStartedAt;
    if (durationMs < 1000) return; // ignore <1s noise (handshake failures, etc.)
    c.executionCtx?.waitUntil?.(
      import('../lib/billing')
        .then(({ voiceSessionCostCredits, trackCreditsUsed }) => {
          const credits = voiceSessionCostCredits(durationMs);
          if (credits <= 0) return;
          return trackCreditsUsed({ userId: user.id, credits });
        })
        .catch((error) => {
          console.error('[voice-ws] voice billing import/trackCreditsUsed failed', error);
        }),
    );
  };

  // Buffer any client messages that arrive while the upstream Gemini connection is
  // being established. Without this, messages sent between serverWs.accept() and
  // handler attachment would be silently dropped (e.g. the setup config message).
  const earlyMessages: (string | ArrayBuffer)[] = [];
  let upstreamReady = false;
  let upstreamRef: WebSocket | null = null;

  serverWs.addEventListener('message', (event) => {
    maybeMarkVoiceSessionStarted(event.data);
    if (upstreamReady && upstreamRef) {
      try {
        upstreamRef.send(event.data);
      } catch {
        /* upstream already closed */
      }
    } else {
      // Upstream not ready yet — queue for replay once connected
      earlyMessages.push(event.data);
    }
  });

  // Connect to Gemini Live with the server-side API key (never exposed to clients).
  // Use https:// scheme — Cloudflare Workers outbound WebSocket requires https/http.
  // Send the API key via the x-goog-api-key header (not a query string) so it never
  // ends up in CDN/proxy access logs nor in upstream error bodies that get echoed back.
  const geminiUrl =
    'https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  // CRITICAL: do NOT await the upstream fetch before returning the 101 response.
  // Cloudflare returns this Response to the client to complete the HTTP→WebSocket
  // upgrade — if we hold it back while waiting on Gemini, the client sits on a
  // hanging HTTP request and SwiftUI shows a forever-spinner. Instead we return
  // the 101 immediately, do the upstream connect in the background, and (a)
  // forward responses once it's ready or (b) fail() the client WS with a real
  // close reason if it never establishes.
  const wireUpUpstream = async () => {
    try {
      const upstreamResp = await fetch(geminiUrl, {
        headers: { Upgrade: 'websocket', 'x-goog-api-key': apiKey },
      });
      const upstream = upstreamResp.webSocket;
      if (!upstream) {
        const body = await upstreamResp.text().catch(() => '');
        console.error('[voice-ws] Gemini rejected WS upgrade', {
          status: upstreamResp.status,
          body,
          userId: user.id,
        });
        // Don't echo the upstream body to the client over the WS — Google's error
        // bodies have historically included echoed request fragments and internal
        // request IDs. Client gets a generic message; full detail stays in server logs.
        fail(
          4502,
          'voice_upstream_failed',
          `Voice provider rejected the connection (${upstreamResp.status}).`,
        );
        return;
      }
      upstream.accept();
      upstreamRef = upstream;

      // Forward Gemini → client BEFORE flushing buffered client messages so we
      // don't miss the immediate setupComplete (or an error on bad setup).
      upstream.addEventListener('message', (event) => {
        try {
          serverWs.send(event.data);
        } catch {
          /* client already closed */
        }
      });

      // Replay anything the client sent while we were connecting.
      for (const msg of earlyMessages) {
        try {
          upstream.send(msg);
        } catch {
          break;
        }
      }
      earlyMessages.length = 0;
      upstreamReady = true;

      // Propagate close events in both directions. Empty catches are intentional:
      // close() throws if the other side is already closed.
      serverWs.addEventListener('close', (event) => {
        try {
          upstream.close(event.code, event.reason || '');
        } catch {
          /* already closed */
        }
        trackVoiceUsage();
      });
      upstream.addEventListener('close', (event) => {
        try {
          serverWs.close(event.code, event.reason || '');
        } catch {
          /* already closed */
        }
        trackVoiceUsage();
      });

      serverWs.addEventListener('error', (event) => {
        console.error('[voice-ws] client error', {
          userId: user.id,
          event: String((event as ErrorEvent).message ?? ''),
        });
        try {
          upstream.close(1011, 'Client error');
        } catch {
          /* already closed */
        }
      });
      upstream.addEventListener('error', (event) => {
        console.error('[voice-ws] upstream error', {
          userId: user.id,
          event: String((event as ErrorEvent).message ?? ''),
        });
        try {
          serverWs.close(1011, 'Upstream error');
        } catch {
          /* already closed */
        }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[voice-ws] Failed to connect to Gemini', { error: msg, userId: user.id });
      fail(4502, 'voice_upstream_unreachable', `Failed to reach voice provider: ${msg}`);
    }
  };

  // Keep the worker alive until the upstream pipeline is wired up; return 101 NOW.
  // Always start the promise — waitUntil is best-effort, and even if the runtime
  // doesn't extend the worker lifetime, the WebSocketPair itself keeps it alive
  // while the client side stays open. Errors inside wireUpUpstream are surfaced
  // to the client via fail() so they cannot escape unhandled.
  const upstreamPromise = wireUpUpstream();
  c.executionCtx?.waitUntil?.(upstreamPromise);

  return wsResponse;
});

// Add CORS headers for /do/* routes
aiRouter.use('/do/*', async (c, next) => {
  const origin = c.req.header('Origin');
  if (origin && trustedOrigins.has(origin)) {
    c.header('Access-Control-Allow-Origin', origin);
    c.header('Vary', 'Origin');
    c.header('Access-Control-Allow-Credentials', 'true');
  }
  c.header('Access-Control-Allow-Headers', 'Content-Type, X-Voice-Secret, X-Caller');
  c.header('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (c.req.method === 'OPTIONS') {
    return c.text('');
  }
  return next();
});

aiRouter.post('/do/:action', async (c) => {
  let user = c.var.sessionUser;

  // Fallback to voice secret + caller ID ONLY if no valid session exists (e.g. Twilio webhook)
  if (!user) {
    if (!timingSafeEqual(env.VOICE_SECRET, c.req.header('X-Voice-Secret'))) {
      return c.json({ success: false, error: 'Unauthorized' }, 401);
    }
    const caller = c.req.header('X-Caller');
    if (!caller) return c.json({ success: false, error: 'Unauthorized' }, 401);

    const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
    const dbUser = await db.query.user.findFirst({
      where: (u, { eq, and }) => and(eq(u.phoneNumber, caller), eq(u.phoneNumberVerified, true)),
    });
    await conn.end();

    if (!dbUser) return c.json({ success: false, error: 'Unauthorized' }, 401);
    user = dbUser as typeof user;
  }

  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
  const connection = await db.query.connection.findFirst({
    where: (connection, { eq, or }) =>
      or(eq(connection.id, user!.defaultConnectionId!), eq(connection.userId, user!.id)),
  });
  await conn.end();
  if (!connection) return c.json({ success: false, error: 'Unauthorized' }, 401);

  try {
    const action = c.req.param('action') as keyof ToolsReturnType;
    const body = await c.req.json();

    // Get all tools for this connection
    const toolset: ToolsReturnType = await tools(connection.id, action === Tools.InboxRag);
    const tool = toolset[action as keyof ToolsReturnType];

    if (!tool) {
      return c.json({ success: false, error: `Tool '${action}' not found` }, 404);
    }

    const result = await tool.execute?.(body || {}, {
      toolCallId: crypto.randomUUID(),
      messages: [],
    });
    return c.json({ success: true, result });
  } catch (error: unknown) {
    console.error(`Error executing tool '${c.req.param('action')}':`, error);
    const message = error instanceof Error ? error.message : String(error);
    return c.json({ success: false, error: message }, 400);
  }
});

aiRouter.post('/call', async (c) => {
  if (env.DISABLE_CALLS) {
    return c.json({ success: false, error: 'Not implemented' }, 400);
  }

  if (!timingSafeEqual(env.VOICE_SECRET, c.req.header('X-Voice-Secret'))) {
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  if (!c.req.header('X-Caller')) {
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  const { success, data } = await z
    .object({
      query: z.string(),
    })
    .safeParseAsync(await c.req.json());

  if (!success) {
    return c.json({ success: false, error: 'Invalid request' }, 400);
  }

  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);

  const user = await db.query.user.findFirst({
    where: (user, { eq, and }) =>
      and(eq(user.phoneNumber, c.req.header('X-Caller')!), eq(user.phoneNumberVerified, true)),
  });

  if (!user) {
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  const connection = await db.query.connection.findFirst({
    where: (connection, { eq, or }) =>
      or(eq(connection.id, user.defaultConnectionId!), eq(connection.userId, user.id)),
  });

  await conn.end();

  if (!connection) {
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  const toolset = await tools(connection.id);
  const { text } = await generateText({
    model: resolveModel({ provider: 'auto', modelId: '', ollamaBaseUrl: '', env }),
    system: await getSharedAIProfilePromptForUser(user.id, {
      name: user.name,
      email: user.email,
    })
      .then((sharedAIProfilePrompt) =>
        // Append profile AFTER base system instructions so core rules take precedence
        sharedAIProfilePrompt ? `${systemPrompt}\n\n${sharedAIProfilePrompt}` : systemPrompt,
      )
      .catch((error) => {
        console.warn(
          '[AIProfile] Failed to build system prompt with profile for user:',
          user.id,
          error,
        );
        return systemPrompt;
      }),
    prompt: data.query,
    tools: toolset,
    maxSteps: 10,
  });

  return new Response(text, {
    headers: { 'Content-Type': 'text/plain' },
  });
});
