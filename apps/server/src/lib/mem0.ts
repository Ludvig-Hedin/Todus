/**
 * Mem0 REST API Client with Multi-Layer Caching
 *
 * Provides persistent AI memory via Mem0 (https://mem0.ai).
 * All Mem0 API calls are server-side only — the API key never reaches client code.
 *
 * Caching strategy (zero latency on the hot path):
 *   Layer 1: In-memory Map — 0ms reads, populated on preload
 *   Layer 2: Cloudflare KV — <5ms reads, survives DO restarts
 *   Layer 3: Mem0 API — 200-400ms, only called on cache miss or background refresh
 *
 * user_id = Better Auth user.id — stable across web + iOS.
 */

const MEM0_API_BASE = 'https://api.mem0.ai';
const KV_PREFIX = 'mem0:user:';
const KV_TTL_SECONDS = 300; // 5 minutes
const IN_MEMORY_TTL_MS = 5 * 60 * 1000; // 5 minutes
const DEFAULT_TOP_K = 15;

// ── Types ──────────────────────────────────────────────────────────────────

export interface MemoryEntry {
  id: string;
  memory: string;
  user_id?: string;
  metadata?: Record<string, unknown>;
  categories?: string[];
  created_at?: string;
  updated_at?: string;
  score?: number;
}

interface Mem0SearchResponse {
  memories?: MemoryEntry[];
  results?: MemoryEntry[];
}

interface Mem0GetAllResponse {
  memories?: MemoryEntry[];
  results?: MemoryEntry[];
}

// ── In-Memory Cache (Layer 1) ──────────────────────────────────────────────
// Global in-memory cache shared across requests within the same isolate/DO instance.
// This is the fastest layer — 0ms reads.

interface CacheEntry {
  memories: string[];
  fetchedAt: number;
}

const inMemoryCache = new Map<string, CacheEntry>();

function getFromMemoryCache(userId: string): string[] | null {
  const entry = inMemoryCache.get(userId);
  if (!entry) return null;
  if (Date.now() - entry.fetchedAt > IN_MEMORY_TTL_MS) {
    inMemoryCache.delete(userId);
    return null;
  }
  return entry.memories;
}

function setInMemoryCache(userId: string, memories: string[]): void {
  inMemoryCache.set(userId, { memories, fetchedAt: Date.now() });
}

// ── Core API Functions ─────────────────────────────────────────────────────

/**
 * Add memories from a conversation to Mem0.
 * Fire-and-forget — errors are logged but never thrown.
 */
export async function addMemories(
  apiKey: string,
  userId: string,
  messages: Array<{ role: string; content: string }>,
  metadata?: Record<string, unknown>,
): Promise<void> {
  try {
    const body: Record<string, unknown> = {
      user_id: userId,
      messages,
      version: 'v2',
    };
    if (metadata) body.metadata = metadata;

    const response = await fetch(`${MEM0_API_BASE}/v1/memories/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Token ${apiKey}`,
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => 'unknown');
      console.warn(`[Mem0] addMemories failed (${response.status}): ${errorText}`);
    }
  } catch (error) {
    // Never break the AI flow — log and move on
    console.warn('[Mem0] addMemories error:', error);
  }
}

/**
 * Search memories by semantic query for a specific user.
 * Returns raw MemoryEntry array for maximum flexibility.
 */
export async function searchMemories(
  apiKey: string,
  userId: string,
  query: string,
  topK: number = DEFAULT_TOP_K,
): Promise<MemoryEntry[]> {
  try {
    const response = await fetch(`${MEM0_API_BASE}/v2/memories/search/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Token ${apiKey}`,
      },
      body: JSON.stringify({
        query,
        filters: { AND: [{ user_id: userId }] },
        top_k: topK,
      }),
    });

    if (!response.ok) {
      console.warn(`[Mem0] searchMemories failed (${response.status})`);
      return [];
    }

    const data = (await response.json()) as Mem0SearchResponse;
    return data.memories ?? data.results ?? [];
  } catch (error) {
    console.warn('[Mem0] searchMemories error:', error);
    return [];
  }
}

/**
 * Get all memories for a user (used for preloading / cache warm-up).
 */
export async function getAllMemories(apiKey: string, userId: string): Promise<MemoryEntry[]> {
  try {
    const response = await fetch(`${MEM0_API_BASE}/v2/memories/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Token ${apiKey}`,
      },
      body: JSON.stringify({
        filters: { AND: [{ user_id: userId }] },
      }),
    });

    if (!response.ok) {
      console.warn(`[Mem0] getAllMemories failed (${response.status})`);
      return [];
    }

    const data = (await response.json()) as Mem0GetAllResponse;
    return data.memories ?? data.results ?? [];
  } catch (error) {
    console.warn('[Mem0] getAllMemories error:', error);
    return [];
  }
}

// ── Caching Layer ──────────────────────────────────────────────────────────

/**
 * Get memories with multi-layer caching:
 *   1. In-memory cache (0ms)
 *   2. KV cache (<5ms)
 *   3. Mem0 API (200-400ms, only on full cache miss)
 *
 * This is the function to call in the hot path — it's always fast.
 */
export async function getCachedMemories(
  userId: string,
  kv: KVNamespace | undefined,
  apiKey: string,
): Promise<string[]> {
  // Layer 1: in-memory cache (0ms)
  const cached = getFromMemoryCache(userId);
  if (cached !== null) return cached;

  // Layer 2: KV cache (<5ms)
  if (kv) {
    try {
      const kvData = await kv.get(`${KV_PREFIX}${userId}`);
      if (kvData) {
        const memories = JSON.parse(kvData) as string[];
        setInMemoryCache(userId, memories);
        return memories;
      }
    } catch (error) {
      console.warn('[Mem0] KV read error:', error);
    }
  }

  // Layer 3: Mem0 API (only on full cache miss)
  if (!apiKey) return [];
  const entries = await getAllMemories(apiKey, userId);
  const memoryStrings = entries.map((e) => e.memory);
  setInMemoryCache(userId, memoryStrings);

  // Write back to KV for next time
  if (kv) {
    try {
      await kv.put(`${KV_PREFIX}${userId}`, JSON.stringify(memoryStrings), {
        expirationTtl: KV_TTL_SECONDS,
      });
    } catch (error) {
      console.warn('[Mem0] KV write error:', error);
    }
  }

  return memoryStrings;
}

/**
 * Preload memories into both cache layers in the background.
 * Call this on WebSocket connect / auth so memories are ready before the user sends a message.
 * Returns the fetched memories for convenience.
 */
export async function preloadMemories(
  userId: string,
  kv: KVNamespace | undefined,
  apiKey: string,
): Promise<string[]> {
  if (!apiKey || !userId) return [];

  try {
    const entries = await getAllMemories(apiKey, userId);
    const memoryStrings = entries.map((e) => e.memory);
    setInMemoryCache(userId, memoryStrings);

    if (kv) {
      await kv.put(`${KV_PREFIX}${userId}`, JSON.stringify(memoryStrings), {
        expirationTtl: KV_TTL_SECONDS,
      });
    }

    return memoryStrings;
  } catch (error) {
    console.warn('[Mem0] preloadMemories error:', error);
    return [];
  }
}

/**
 * Invalidate both cache layers for a user.
 * Called after addMemories so next fetch gets fresh data.
 */
export async function invalidateMemoryCache(
  userId: string,
  kv: KVNamespace | undefined,
): Promise<void> {
  inMemoryCache.delete(userId);
  if (kv) {
    try {
      await kv.delete(`${KV_PREFIX}${userId}`);
    } catch (error) {
      console.warn('[Mem0] KV invalidation error:', error);
    }
  }
}

/**
 * Best-effort erasure for external Mem0 memories during account deletion.
 * Never throw from here: account deletion must continue even if Mem0 is down,
 * but caches are always invalidated so deleted users cannot be rehydrated from
 * stale local/KV memory.
 */
export async function deleteUserMemories(
  apiKey: string | undefined,
  userId: string,
  kv: KVNamespace | undefined,
): Promise<boolean> {
  await invalidateMemoryCache(userId, kv);

  if (!apiKey || !userId) {
    return true;
  }

  try {
    const url = `${MEM0_API_BASE}/v1/memories/?user_id=${encodeURIComponent(userId)}`;
    const response = await fetch(url, {
      method: 'DELETE',
      headers: {
        Accept: 'application/json',
        Authorization: `Token ${apiKey}`,
      },
    });

    if (!response.ok && response.status !== 404) {
      const errorText = await response.text().catch(() => 'unknown');
      console.warn(`[Mem0] deleteUserMemories failed (${response.status}): ${errorText}`);
      return false;
    }

    return true;
  } catch (error) {
    console.warn('[Mem0] deleteUserMemories error:', error);
    return false;
  }
}

// ── Prompt Formatting ──────────────────────────────────────────────────────

/**
 * Format a list of memory strings into a block suitable for injection
 * into the AI system prompt. Returns empty string if no memories.
 */
export function formatMemoriesForPrompt(memories: string[]): string {
  if (!memories.length) return '';

  const memoryList = memories.map((m) => `- ${m}`).join('\n');
  return `## User Memory (persistent context from past interactions)
The following facts were learned from previous conversations with this user. Use them to personalize your responses — but do not repeat them back verbatim unless directly relevant.

${memoryList}`;
}
