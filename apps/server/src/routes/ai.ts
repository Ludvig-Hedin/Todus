import { getCachedMemories, formatMemoriesForPrompt, addMemories, invalidateMemoryCache, preloadMemories } from '../lib/mem0';
import { injectMentionContextIntoMessages, mentionRefSchema } from '../lib/mentions';
import { systemPrompt } from '../services/call-service/system-prompt';
import { getSharedAIProfilePromptForUser } from '../lib/ai-profile';
import { perplexity } from '@ai-sdk/perplexity';
import { resolveModel } from '../lib/ai-model-resolver';
import { tools } from './agent/tools';
import { generateText } from 'ai';
import { Tools } from '../types';
import { createDb } from '../db';
import { env } from '../env';
import type { HonoContext } from '../ctx';
import { Hono } from 'hono';
import { z } from 'zod';
import { serializedFileSchema } from '../lib/schemas';

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
async function searchWithTavily(query: string, apiKey: string): Promise<{ text: string; sources: WebSearchSource[] }> {
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
        include_answer: true,  // Tavily's own short answer — useful for the summary
        include_raw_content: false,
        max_results: 5,
      }),
      signal: controller.signal,
    });
  } catch (err: any) {
    if (err?.name === 'AbortError') throw new Error('Tavily API request timed out');
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
async function searchWithPerplexity(query: string): Promise<{ text: string; sources: WebSearchSource[] }> {
  const result = await generateText({
    model: perplexity('sonar'),
    system: 'You are a research assistant. Provide factual, well-sourced answers.',
    messages: [{ role: 'user', content: query }],
    maxTokens: 1024,
  });

  // Perplexity returns citation URLs in experimental provider metadata
  const rawCitations: string[] = (result as any).experimental_providerMetadata?.perplexity?.citations ?? [];
  const sources: WebSearchSource[] = rawCitations.map((url: string) => ({
    url,
    title: (() => { try { return new URL(url).hostname.replace('www.', ''); } catch { return url; } })(),
    snippet: '',
  }));

  return { text: result.text, sources };
}

/** Inject search results into the message array as a system message before the last user message. */
function injectSearchContext(
  messages: { role: string; content: string }[],
  searchText: string,
  sources: WebSearchSource[],
): { role: string; content: string }[] {
  if (sources.length === 0) return messages;

  const sourcesBlock = sources
    .map((s, i) => `[${i + 1}] "${s.title}" — ${s.url}\n${s.snippet || '(see search summary below)'}`)
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
  result.splice(lastUserIdx, 0, { role: 'system', content: searchContext });
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

const chatRequestSchema = z.object({
  messages: z.array(chatMessageSchema),
  mentions: z.array(mentionRefSchema).optional(),
  tasks: z.array(z.any()).optional(),
  model: z.string().optional(),
  stream: z.boolean().optional().default(true),
  /** Base64-encoded files from the client; merged into the last user message for the model */
  attachments: z.array(serializedFileSchema).optional(),
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

  // ── Mem0: Inject cached memories into the message stream ─────────────────
  // Reads from KV cache (<5ms) or in-memory (0ms). Mem0 API is only hit on
  // full cache miss — preload should have warmed the cache on prior requests.
  const mem0Key = env.MEM0_API_KEY;
  let enrichedMessages = parsed.data.messages;

  if (mem0Key && user.id) {
    try {
      const memories = await getCachedMemories(user.id, env.prompts_storage, mem0Key);
      const memoryBlock = formatMemoriesForPrompt(memories);
      if (memoryBlock) {
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
    parsed.data.messages.some((m) => m.role === 'tool' || (m as any).tool_calls);

  if (!isFollowUpStep) {
    enrichedMessages = injectMentionContextIntoMessages(enrichedMessages as any, parsed.data.mentions);
  }

  // ── Web Search: detect, search, inject sources ──────────────────────────
  // Check if the user's last message would benefit from current web information.
  // If so, call Perplexity sonar and inject results + citation instructions.
  const rawLastUserMsg = parsed.data.messages.filter((m) => m.role === 'user').pop();
  const lastUserMsg = enrichedMessages.filter((m) => m.role === 'user').pop();
  const searchQuery = typeof rawLastUserMsg?.content === 'string' ? rawLastUserMsg.content : '';
  const needsSearch = !isFollowUpStep && searchQuery ? shouldSearchWeb(searchQuery) : false;
  let searchSources: WebSearchSource[] = [];

  if (needsSearch && searchQuery) {
    try {
      const searchResult = await performWebSearch(searchQuery, env);
      searchSources = searchResult.sources;
      if (searchSources.length > 0) {
        enrichedMessages = injectSearchContext(enrichedMessages as any, searchResult.text, searchSources);
      }
    } catch (error) {
      // Web search failure must never block the AI flow — proceed without sources
      console.warn('[WebSearch] Perplexity search failed:', error);
    }
  }

  try {
    const sharedAIProfilePrompt = await getSharedAIProfilePromptForUser(user.id);
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
        enrichedMessages = [{ role: 'system', content: sharedAIProfilePrompt }, ...enrichedMessages];
      }
    }
  } catch (error) {
    console.warn('[AIProfile] Failed to inject AI profile into /ai/chat for user:', user.id, error);
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

  // Proxy the request to OpenRouter
  const upstreamResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://todus.app',
      'X-Title': 'Todus AI',
    },
    body: JSON.stringify({
      model,
      messages: enrichedMessages,
      stream: shouldStream,
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
            description: 'Create a new calendar event on the user\'s device calendar',
            parameters: {
              type: 'object',
              properties: {
                title: { type: 'string', description: 'Event title' },
                startDate: { type: 'string', description: 'ISO 8601 start datetime, e.g. 2025-04-01T09:00:00' },
                endDate: { type: 'string', description: 'ISO 8601 end datetime (optional, defaults to 1 hour after start)' },
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
            description: 'Update an existing calendar event. Use the event identifier from the calendar context.',
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
                threadId: { type: 'string', description: 'Thread ID to reply to (omit for new email)' },
              },
              required: ['to', 'subject', 'body'],
            },
          },
        },
      ],
    }),
  });

  if (!upstreamResponse.ok || !upstreamResponse.body) {
    const errorText = await upstreamResponse.text().catch(() => 'Unknown error');
    return c.json({ error: `AI provider error: ${upstreamResponse.status}`, details: errorText }, 502);
  }

  // ── Build SSE response stream ────────────────────────────────────────────
  // We use a custom ReadableStream to:
  // 1. Write web search custom events (search_status, sources) before the LLM response
  // 2. Pipe upstream OpenRouter SSE through unchanged
  // 3. Capture assistant text for Mem0 memory storage (fire-and-forget)
  const encoder = new TextEncoder();
  const mem0LastUserMsg = parsed.data.messages.filter((m) => m.role === 'user').pop();
  let assistantText = '';
  const userId = user.id;
  const persistConversationMemory = async (assistantContent: string) => {
    if (!mem0Key || !userId || !mem0LastUserMsg || assistantContent.length <= 10) return;

    await addMemories(mem0Key, userId, [
      { role: 'user', content: typeof mem0LastUserMsg.content === 'string' ? mem0LastUserMsg.content : '' },
      { role: 'assistant', content: assistantContent },
    ]);
    await invalidateMemoryCache(userId, env.prompts_storage);
    await preloadMemories(userId, env.prompts_storage, mem0Key);
  };

  // ── Non-streaming path — preserve the same memory + source behaviour ─────
  if (!shouldStream) {
    const responseData = (await upstreamResponse.json()) as Record<string, any>;
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
    });
  }

  const responseStream = new ReadableStream({
    async start(controller) {
      try {
        // 1. Write web search custom events before the LLM answer.
        //    Already gated by needsSearch (which is false on follow-up steps),
        //    so this block won't fire on round-2+ tool-result replays.
        if (needsSearch && searchQuery) {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({ type: 'search_status', status: 'searching', queries: [searchQuery] })}\n\n`),
          );
        }
        if (searchSources.length > 0) {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({ type: 'sources', sources: searchSources })}\n\n`),
          );
        } else if (needsSearch && searchQuery) {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({ type: 'search_status', status: 'idle', queries: [searchQuery] })}\n\n`),
          );
        }

        // 2. Pipe upstream OpenRouter SSE through, capturing content for Mem0
        if (!upstreamResponse.body) {
          controller.close();
          return;
        }
        const reader = upstreamResponse.body.getReader();
        const decoder = new TextDecoder();
        let reasoningStartTime = 0;
        let hasReasoning = false;

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          // Pass through to client
          controller.enqueue(value);

          // Extract content + reasoning from SSE chunks (best-effort, errors won't break stream)
          try {
            const text = decoder.decode(value, { stream: true });
            const lines = text.split('\n').filter((l) => l.startsWith('data: '));
            for (const line of lines) {
              const json = line.slice(6);
              if (json === '[DONE]') continue;
              const sseChunk = JSON.parse(json);
              const delta = sseChunk?.choices?.[0]?.delta;

              // Capture main content for Mem0
              if (delta?.content) assistantText += delta.content;

              // Extract reasoning tokens from reasoning models (deepseek-r1, o1, etc.)
              // OpenRouter passes these as `reasoning_content` or `reasoning` in the delta.
              const reasoningToken = delta?.reasoning_content ?? delta?.reasoning;
              if (reasoningToken) {
                if (!hasReasoning) {
                  reasoningStartTime = Date.now();
                  hasReasoning = true;
                }
                // Re-emit as a custom reasoning event for the iOS client
                controller.enqueue(
                  encoder.encode(`data: ${JSON.stringify({ type: 'reasoning', content: reasoningToken })}\n\n`),
                );
              }

              // When reasoning ends (first content token after reasoning), emit reasoning_done
              if (hasReasoning && delta?.content && reasoningStartTime > 0) {
                const durationMs = Date.now() - reasoningStartTime;
                controller.enqueue(
                  encoder.encode(`data: ${JSON.stringify({ type: 'reasoning_done', duration_ms: durationMs })}\n\n`),
                );
                reasoningStartTime = 0; // Only emit once
              }
            }
          } catch {
            // Ignore parse errors — some chunks may be partial
          }
        }

        // 3. Mem0: store conversation memory after stream completes (fire-and-forget)
        if (mem0Key && userId && mem0LastUserMsg && assistantText.length > 10) {
          const storePromise = persistConversationMemory(assistantText).catch((error) => {
            console.warn('[Mem0] Post-stream memory storage failed:', error);
          });
          c.executionCtx?.waitUntil?.(storePromise);
        }

        controller.close();
      } catch (error) {
        controller.error(error);
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
  const geminiUrl =
    `https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${apiKey}`;

  try {
    const resp = await fetch(geminiUrl, { headers: { Upgrade: 'websocket' } });
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

aiRouter.get('/voice-ws', async (c) => {
  const user = c.var.sessionUser;
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const upgradeHeader = c.req.header('Upgrade');
  if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
    return c.text('Expected WebSocket upgrade', 426);
  }

  const apiKey = env.GOOGLE_GENERATIVE_AI_API_KEY;
  if (!apiKey) return c.json({ error: 'Voice not configured' }, 503);

  // Create WebSocket pair: clientWs returns to the iOS app, serverWs stays here
  const pair = new WebSocketPair();
  const [clientWs, serverWs] = Object.values(pair);
  serverWs.accept();

  // Buffer any client messages that arrive while the upstream Gemini connection is
  // being established. Without this, messages sent between serverWs.accept() and
  // handler attachment would be silently dropped (e.g. the setup config message).
  const earlyMessages: (string | ArrayBuffer)[] = [];
  let upstreamReady = false;
  let upstreamRef: WebSocket | null = null;

  serverWs.addEventListener('message', (event) => {
    if (upstreamReady && upstreamRef) {
      try { upstreamRef.send(event.data); } catch { /* upstream already closed */ }
    } else {
      // Upstream not ready yet — queue for replay once connected
      earlyMessages.push(event.data);
    }
  });

  // Connect to Gemini Live with the server-side API key (never exposed to clients).
  // Use https:// scheme — Cloudflare Workers outbound WebSocket requires https/http.
  const geminiUrl =
    `https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${apiKey}`;

  try {
    const upstreamResp = await fetch(geminiUrl, {
      headers: { Upgrade: 'websocket' },
    });
    const upstream = upstreamResp.webSocket;
    if (!upstream) {
      const body = await upstreamResp.text().catch(() => '');
      console.error('[voice-ws] Gemini rejected WS upgrade', {
        status: upstreamResp.status,
        body,
        userId: user.id,
      });
      serverWs.close(1011, `Gemini error ${upstreamResp.status}`);
      return new Response(`Voice service error: Gemini returned ${upstreamResp.status} — ${body}`, { status: 502 });
    }
    upstream.accept();
    upstreamRef = upstream;

    // Set up Gemini→client forwarding BEFORE flushing early messages so we
    // don't miss any immediate responses (e.g. error on bad model in setup).
    upstream.addEventListener('message', (event) => {
      try { serverWs.send(event.data); } catch { /* client already closed */ }
    });

    // Flush any messages that arrived while we were connecting to Gemini
    for (const msg of earlyMessages) {
      try { upstream.send(msg); } catch { break; }
    }
    earlyMessages.length = 0;
    upstreamReady = true;

    // Propagate close events in both directions. Empty catches are intentional:
    // close() throws if the other side is already closed, which is the common
    // race during teardown — nothing to do but proceed.
    serverWs.addEventListener('close', (event) => {
      try { upstream.close(event.code, event.reason || ''); } catch { /* already closed */ }
    });
    upstream.addEventListener('close', (event) => {
      try { serverWs.close(event.code, event.reason || ''); } catch { /* already closed */ }
    });

    // Handle errors by tearing down the other side. Log so we can diagnose;
    // the close() catch stays empty because by this point teardown is best-effort.
    serverWs.addEventListener('error', (event) => {
      console.error('[voice-ws] client error', { userId: user.id, event: String((event as ErrorEvent).message ?? '') });
      try { upstream.close(1011, 'Client error'); } catch { /* already closed */ }
    });
    upstream.addEventListener('error', (event) => {
      console.error('[voice-ws] upstream error', { userId: user.id, event: String((event as ErrorEvent).message ?? '') });
      try { serverWs.close(1011, 'Upstream error'); } catch { /* already closed */ }
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[voice-ws] Failed to connect to Gemini', { error: msg, userId: user.id });
    serverWs.close(1011, 'Failed to connect to voice service');
    return new Response(`Voice service error: ${msg}`, { status: 502 });
  }

  // Return the 101 Switching Protocols response with the client-side WebSocket
  return new Response(null, {
    status: 101,
    webSocket: clientWs,
  } as ResponseInit & { webSocket: WebSocket });
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
      where: (u, { eq, and }) =>
        and(eq(u.phoneNumber, caller), eq(u.phoneNumberVerified, true)),
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
  } catch (error: any) {
    console.error(`Error executing tool '${c.req.param('action')}':`, error);
    return c.json({ success: false, error: error.message }, 400);
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
    system: await getSharedAIProfilePromptForUser(user.id)
      .then((sharedAIProfilePrompt) =>
        // Append profile AFTER base system instructions so core rules take precedence
        sharedAIProfilePrompt ? `${systemPrompt}\n\n${sharedAIProfilePrompt}` : systemPrompt,
      )
      .catch((error) => {
        console.warn('[AIProfile] Failed to build system prompt with profile for user:', user.id, error);
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
