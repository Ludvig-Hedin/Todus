import { afterEach, describe, expect, it, vi } from 'vitest';

import { deleteUserMemories, getCachedMemories } from './mem0';

vi.mock('cloudflare:workers', () => ({ env: {} }));

const createKv = () => {
  const store = new Map<string, string>();
  return {
    get: vi.fn(async (key: string) => store.get(key) ?? null),
    put: vi.fn(async (key: string, value: string) => {
      store.set(key, value);
    }),
    delete: vi.fn(async (key: string) => {
      store.delete(key);
    }),
  } as unknown as KVNamespace & {
    get: ReturnType<typeof vi.fn>;
    put: ReturnType<typeof vi.fn>;
    delete: ReturnType<typeof vi.fn>;
  };
};

describe('deleteUserMemories', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('deletes Mem0 memories for the specific user and invalidates KV cache', async () => {
    const kv = createKv();
    await kv.put('mem0:user:user 123', JSON.stringify(['remember me']));
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await deleteUserMemories('mem0-token', 'user 123', kv);

    expect(result).toBe(true);
    expect(fetchMock).toHaveBeenCalledWith('https://api.mem0.ai/v1/memories/?user_id=user%20123', {
      method: 'DELETE',
      headers: {
        Accept: 'application/json',
        Authorization: 'Token mem0-token',
      },
    });
    expect(kv.delete).toHaveBeenCalledWith('mem0:user:user 123');
  });

  it('does not call Mem0 when the API key is missing but still clears cache', async () => {
    const kv = createKv();
    await kv.put('mem0:user:user-1', JSON.stringify(['cached']));
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    const result = await deleteUserMemories(undefined, 'user-1', kv);
    const cached = await getCachedMemories('user-1', kv, '');

    expect(result).toBe(true);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(cached).toEqual([]);
  });

  it('returns false on Mem0 failures without throwing', async () => {
    const kv = createKv();
    const fetchMock = vi.fn(async () => new Response('down', { status: 500 }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(deleteUserMemories('mem0-token', 'user-1', kv)).resolves.toBe(false);
  });
});
