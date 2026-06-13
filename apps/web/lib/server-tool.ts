// Server tool wrapper using secure session cookies instead of exposed voice secret.
//
// Hits the existing `aiRouter.post('/do/:action')` endpoint (apps/server/src/routes/ai.ts),
// which resolves the authed session user, looks up their connection, and runs the
// named agent tool from the shared `tools()` factory. Auth is via the session cookie
// (`credentials: 'include'`); `X-Caller` is only used by the server's voice-secret
// fallback path and is harmless for cookie-authenticated calls.
export async function callServerTool(action: string, payload: unknown, caller: string) {
  const base = import.meta.env.VITE_PUBLIC_BACKEND_URL;

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
