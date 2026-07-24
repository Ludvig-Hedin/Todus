import { and, desc, eq } from 'drizzle-orm';
import { assistantOpenLoop, assistantWorkstreamMemory } from '../db/schema';
import { createDb } from '../db';
import { env } from '../env';

/**
 * Compact second-brain digest for native-client chat (/api/ai/chat).
 *
 * Both chat surfaces also expose the getPersonContext / getWorkstreamContext /
 * getOpenLoops tools for on-demand reads (native clients proxy them via
 * /api/ai/do/*). This digest is the ambient complement injected into the
 * system prompt: top open loops + active workstreams. Returns '' when the user has no
 * derived memory yet (briefing sync never ran) so callers can skip cleanly.
 *
 * Size is capped (8 loops, 5 workstreams, trimmed summaries) to keep the
 * per-turn token cost ~1KB.
 */

const MAX_LOOPS = 8;
const MAX_WORKSTREAMS = 5;
const MAX_SUMMARY_CHARS = 200;

/** Strip markdown structure so LLM-derived text can't break out of the prompt. */
const sanitizeInline = (value: string) =>
  value
    .replace(/`/g, '')
    .replace(/^#+\s*/gm, '')
    .replace(/[\r\n]+/g, ' ')
    .trim();

const trim = (value: string, max: number) =>
  value.length > max ? `${value.slice(0, max - 1)}…` : value;

export const getSecondBrainDigest = async (userId: string): Promise<string> => {
  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
  try {
    const [loops, workstreams] = await Promise.all([
      db
        .select({
          queue: assistantOpenLoop.queue,
          title: assistantOpenLoop.title,
          actionLine: assistantOpenLoop.actionLine,
          personEmail: assistantOpenLoop.personEmail,
        })
        .from(assistantOpenLoop)
        .where(and(eq(assistantOpenLoop.userId, userId), eq(assistantOpenLoop.status, 'open')))
        .orderBy(desc(assistantOpenLoop.updatedAt))
        .limit(MAX_LOOPS),
      db
        .select({
          title: assistantWorkstreamMemory.title,
          summary: assistantWorkstreamMemory.summary,
          nextMilestone: assistantWorkstreamMemory.nextMilestone,
        })
        .from(assistantWorkstreamMemory)
        .where(
          and(
            eq(assistantWorkstreamMemory.userId, userId),
            eq(assistantWorkstreamMemory.status, 'active'),
          ),
        )
        .orderBy(desc(assistantWorkstreamMemory.updatedAt))
        .limit(MAX_WORKSTREAMS),
    ]);

    if (loops.length === 0 && workstreams.length === 0) return '';

    const sections: string[] = [
      '## Assistant memory (auto-derived from the user\'s email and meetings; may be incomplete or stale — verify before acting on it)',
      'For deeper detail use the getPersonContext, getWorkstreamContext, and getOpenLoops tools.',
    ];

    if (loops.length > 0) {
      const lines = ['### Open loops (things needing attention)'];
      for (const l of loops) {
        const text = sanitizeInline(l.actionLine || l.title);
        const person = l.personEmail ? ` (${sanitizeInline(l.personEmail)})` : '';
        lines.push(`- [${l.queue}] ${trim(text, MAX_SUMMARY_CHARS)}${person}`);
      }
      sections.push(lines.join('\n'));
    }

    if (workstreams.length > 0) {
      const lines = ['### Active workstreams'];
      for (const w of workstreams) {
        const summary = sanitizeInline(w.summary);
        const milestone = w.nextMilestone ? ` Next: ${sanitizeInline(w.nextMilestone)}` : '';
        lines.push(
          `- ${sanitizeInline(w.title)}: ${trim(summary, MAX_SUMMARY_CHARS)}${milestone}`,
        );
      }
      sections.push(lines.join('\n'));
    }

    return sections.join('\n\n');
  } finally {
    await conn.end();
  }
};
