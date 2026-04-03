// Server tool wrapper using secure session cookies instead of exposed voice secret
export async function callServerTool(action: string, payload: unknown, caller: string) {
  const base = import.meta.env.VITE_PUBLIC_SERVER_URL;

  const res = await fetch(`${base}/api/ai/do/${action}`, {
    method: 'POST',
    credentials: 'include', // <-- Authenticate securely via session cookie
    headers: {
      'Content-Type': 'application/json',
      'X-Caller': caller,
    },
    body: JSON.stringify(payload ?? {}),
  });

  // network / non-200 safety
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Server error (${res.status}): ${txt}`);
  }

  const data = await res.json<{ success: boolean; result?: unknown; error?: string }>(); // { success, result?, error? }
  if (!data.success) throw new Error(data.error ?? 'Unknown error');

  return data.result; // ⇦ what ElevenLabs expects
}
