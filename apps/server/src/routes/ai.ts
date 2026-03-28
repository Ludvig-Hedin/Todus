import { getCachedMemories, formatMemoriesForPrompt, addMemories, invalidateMemoryCache, preloadMemories } from '../lib/mem0';
import { systemPrompt } from '../services/call-service/system-prompt';
import { openai } from '@ai-sdk/openai';
import { tools } from './agent/tools';
import { generateText } from 'ai';
import { Tools } from '../types';
import { createDb } from '../db';
import { env } from '../env';
import type { HonoContext } from '../ctx';
import { Hono } from 'hono';
import { z } from 'zod';

type ToolsReturnType = Awaited<ReturnType<typeof tools>>;

export const aiRouter = new Hono<HonoContext>();

aiRouter.get('/', (c) => c.text('Twilio + ElevenLabs + AI Phone System Ready'));

// ─────────────────────────────────────────────────────────────────────────────
// Mobile AI Chat — SSE streaming proxy to OpenRouter
// Authenticates via Bearer token (set by main middleware → c.var.sessionUser).
// The iOS app sends the same payload format as the old Supabase edge function.
// ─────────────────────────────────────────────────────────────────────────────

const chatRequestSchema = z.object({
  messages: z.array(z.object({ role: z.string(), content: z.string() })),
  tasks: z.array(z.any()).optional(),
  model: z.string().optional(),
  stream: z.boolean().optional().default(true),
});

aiRouter.post('/chat', async (c) => {
  const user = c.var.sessionUser;
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const body = await c.req.json();
  const parsed = chatRequestSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid request' }, 400);

  const apiKey = env.OPENROUTER_API_KEY;
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

  // Proxy the request to OpenRouter as SSE
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
      stream: true,
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
                  enum: ['none', 'low', 'medium', 'high', 'urgent'],
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
                priority: { type: 'string', enum: ['none', 'low', 'medium', 'high', 'urgent'] },
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

  // ── Mem0: Tee the SSE stream to capture assistant response for memory storage ──
  // The TransformStream passes all chunks to the client unchanged while accumulating
  // the assistant's text content. After [DONE], fire-and-forget memory storage.
  if (mem0Key && user.id) {
    const lastUserMsg = parsed.data.messages.filter((m) => m.role === 'user').pop();
    let assistantText = '';
    const userId = user.id;

    const { readable, writable } = new TransformStream({
      transform(chunk, controller) {
        controller.enqueue(chunk);

        // Attempt to extract delta content from SSE chunks for memory storage.
        // This runs in the passthrough — errors must not break the stream.
        try {
          const text = new TextDecoder().decode(chunk);
          const lines = text.split('\n').filter((l) => l.startsWith('data: '));
          for (const line of lines) {
            const json = line.slice(6);
            if (json === '[DONE]') continue;
            const sseChunk = JSON.parse(json);
            const delta = sseChunk?.choices?.[0]?.delta?.content;
            if (delta) assistantText += delta;
          }
        } catch {
          // Ignore parse errors — some chunks may be partial
        }
      },
      flush() {
        // After stream ends, store the conversation in Mem0 (fire-and-forget)
        if (lastUserMsg && assistantText.length > 10) {
          const storePromise = (async () => {
            try {
              await addMemories(mem0Key, userId, [
                { role: 'user', content: lastUserMsg.content },
                { role: 'assistant', content: assistantText },
              ]);
              // Refresh cache in background so next request has fresh memories
              await invalidateMemoryCache(userId, env.prompts_storage);
              await preloadMemories(userId, env.prompts_storage, mem0Key);
            } catch (error) {
              console.warn('[Mem0] Post-stream memory storage failed:', error);
            }
          })();
          // Use waitUntil if available to keep the worker alive for the background task
          c.executionCtx?.waitUntil?.(storePromise);
        }
      },
    });

    upstreamResponse.body.pipeTo(writable);

    return new Response(readable, {
      status: 200,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        Connection: 'keep-alive',
      },
    });
  }

  // Fallback: no Mem0 key configured — pass through directly
  return new Response(upstreamResponse.body, {
    status: 200,
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    },
  });
});

// Add CORS headers for /do/* routes
aiRouter.use('/do/*', async (c, next) => {
  c.header('Access-Control-Allow-Origin', '*');
  c.header('Access-Control-Allow-Headers', 'Content-Type, X-Voice-Secret, X-Caller');
  c.header('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (c.req.method === 'OPTIONS') {
    return c.text('');
  }
  return next();
});

aiRouter.post('/do/:action', async (c) => {
  //   if (env.DISABLE_CALLS) return c.json({ success: false, error: 'Not implemented' }, 400);
  if (env.VOICE_SECRET !== c.req.header('X-Voice-Secret'))
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  const caller = c.req.header('X-Caller');
  if (!caller) return c.json({ success: false, error: 'Unauthorized' }, 401);
  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
  const user = await db.query.user.findFirst({
    where: (user, { eq, and }) =>
      and(eq(user.phoneNumber, caller), eq(user.phoneNumberVerified, true)),
  });
  if (!user) return c.json({ success: false, error: 'Unauthorized' }, 401);

  const connection = await db.query.connection.findFirst({
    where: (connection, { eq, or }) =>
      or(eq(connection.id, user.defaultConnectionId!), eq(connection.userId, user.id)),
  });
  await conn.end();
  if (!connection) return c.json({ success: false, error: 'Unauthorized' }, 401);

  try {
    const action = c.req.param('action') as keyof ToolsReturnType;
    const body = await c.req.json();
    console.log('[DEBUG] action', action, body);

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
  console.log('[DEBUG] Received call request');

  if (env.DISABLE_CALLS) {
    console.log('[DEBUG] Calls are disabled');
    return c.json({ success: false, error: 'Not implemented' }, 400);
  }

  if (env.VOICE_SECRET !== c.req.header('X-Voice-Secret')) {
    console.log('[DEBUG] Invalid voice secret');
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  if (!c.req.header('X-Caller')) {
    console.log('[DEBUG] Missing caller header');
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  console.log('[DEBUG] Parsing request body');
  const { success, data } = await z
    .object({
      query: z.string(),
    })
    .safeParseAsync(await c.req.json());

  if (!success) {
    console.log('[DEBUG] Invalid request body');
    return c.json({ success: false, error: 'Invalid request' }, 400);
  }

  console.log('[DEBUG] Connecting to database');
  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);

  console.log('[DEBUG] Finding user by phone number:', c.req.header('X-Caller'));
  const user = await db.query.user.findFirst({
    where: (user, { eq, and }) =>
      and(eq(user.phoneNumber, c.req.header('X-Caller')!), eq(user.phoneNumberVerified, true)),
  });

  if (!user) {
    console.log('[DEBUG] User not found or not verified');
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  console.log('[DEBUG] Finding connection for user:', user.id);
  const connection = await db.query.connection.findFirst({
    where: (connection, { eq, or }) =>
      or(eq(connection.id, user.defaultConnectionId!), eq(connection.userId, user.id)),
  });

  await conn.end();

  if (!connection) {
    console.log('[DEBUG] No connection found for user');
    return c.json({ success: false, error: 'Unauthorized' }, 401);
  }

  console.log('[DEBUG] Creating toolset for connection:', connection.id);
  const toolset = await tools(connection.id);
  const { text } = await generateText({
    model: openai(env.OPENAI_MODEL || 'gpt-4o'),
    system: systemPrompt,
    prompt: data.query,
    tools: toolset,
    maxSteps: 10,
  });

  return new Response(text, {
    headers: { 'Content-Type': 'text/plain' },
  });
});
