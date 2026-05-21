import { z } from 'zod';
import { generateObject } from 'ai';
import { resolveModel } from './ai-model-resolver';
import { env } from '../env';

/**
 * One verb-first natural-language sentence per briefing candidate, generated
 * by the cheapest available chat model in a single batched call per thread.
 *
 * Returns `Record<uniqueKey, sentence>`. On any failure (timeout, model
 * exception, malformed output) returns `{}` so the caller falls back to the
 * existing `title`/`summary` rendering on the client. Never throws.
 */

export type ActionLineCandidate = {
  uniqueKey: string;
  /** Type of the underlying open-loop or prepared-action — drives the verb. */
  kind: string;
  /** Fallback `title` already on the candidate; used if the LLM omits this key. */
  fallback: string;
};

export type GenerateActionLinesInput = {
  senderName: string;
  senderEmail: string;
  subject: string;
  snippet: string;
  candidates: ActionLineCandidate[];
};

const TIMEOUT_MS = 4000;

const responseSchema = z.object({
  lines: z.array(
    z.object({
      uniqueKey: z.string(),
      sentence: z.string().max(120),
    }),
  ),
});

const SYSTEM_PROMPT = `You generate one verb-first action sentence per candidate.

Rules:
- Start with a verb: Reply, Confirm, Decline, Schedule, Wait, Research, Draft, Review, Send, Archive.
- Include the sender first name and a short fragment of what the email is about.
- Maximum 80 characters.
- No emoji. No quotation marks. No trailing period.
- Never just restate the subject verbatim — the sentence must add the verb + actor + context.
- One sentence per candidate, keyed by uniqueKey.

Examples:
- needs_reply  →  "Reply to Sarah about the Q4 proposal"
- draft_ready  →  "Send the draft you wrote to Anna about pricing"
- waiting_on_other  →  "Follow up with Finance on the budget review"
- research_needed  →  "Look into the API change before replying to Tom"
- meeting_follow_up  →  "Confirm Friday's design review with the team"
- decision_needed  →  "Decide on the vendor proposal Marcus sent"`;

/**
 * Generate action lines for a thread's briefing candidates. Best-effort:
 * returns `{}` on disabled flag, timeout, or model failure.
 */
export async function generateActionLines(
  input: GenerateActionLinesInput,
): Promise<Record<string, string>> {
  if (env.ASSISTANT_ACTION_LINE_ENABLED !== 'true') return {};
  if (input.candidates.length === 0) return {};

  const userPrompt = buildUserPrompt(input);

  try {
    const result = await Promise.race([
      generateObject({
        model: resolveModel({ provider: 'auto', modelId: '', ollamaBaseUrl: '', env }),
        schema: responseSchema,
        system: SYSTEM_PROMPT,
        prompt: userPrompt,
        maxTokens: 400,
        temperature: 0.3,
      }),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error('action-line timeout')), TIMEOUT_MS),
      ),
    ]);

    const out: Record<string, string> = {};
    const knownKeys = new Set(input.candidates.map((c) => c.uniqueKey));
    for (const line of result.object.lines) {
      if (!knownKeys.has(line.uniqueKey)) continue;
      const trimmed = sanitize(line.sentence);
      if (trimmed.length === 0) continue;
      out[line.uniqueKey] = trimmed;
    }
    return out;
  } catch (error) {
    console.warn('[assistant-action-line] generation failed:', error);
    return {};
  }
}

function buildUserPrompt(input: GenerateActionLinesInput): string {
  const candidatesYaml = input.candidates
    .map((c) => `  - uniqueKey: ${JSON.stringify(c.uniqueKey)}\n    kind: ${c.kind}`)
    .join('\n');
  return `Thread context:
- sender: ${input.senderName} <${input.senderEmail}>
- subject: ${input.subject}
- snippet: ${truncate(input.snippet, 400)}

Candidates (one sentence per uniqueKey, return ALL keys):
${candidatesYaml}`;
}

function sanitize(s: string): string {
  let out = s.trim();
  // Strip surrounding quotes.
  if ((out.startsWith('"') && out.endsWith('"')) || (out.startsWith('“') && out.endsWith('”'))) {
    out = out.slice(1, -1).trim();
  }
  // Strip trailing period (rule).
  if (out.endsWith('.')) out = out.slice(0, -1);
  // Cap at 80 chars to enforce the rule even if model exceeds it.
  if (out.length > 80) out = out.slice(0, 80);
  return out;
}

function truncate(s: string, n: number): string {
  if (s.length <= n) return s;
  return s.slice(0, n);
}
