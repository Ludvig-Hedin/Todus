import { and, eq, inArray, sql } from 'drizzle-orm';
import { meetIntegration, meeting, meetingMedia } from '../db/schema';
import type { createDb } from '../db';

type Db = ReturnType<typeof createDb>['db'];

const PRUNE_RATE_LIMIT_MS = 60 * 60 * 1000;
const PRUNE_MEDIA_TYPES = ['audio_mixed', 'video_mixed'] as const;

async function markPrunedAt(db: Db, integrationId: string, now: Date) {
  await db
    .update(meetIntegration)
    .set({
      lastPrunedAt: now,
      updatedAt: now,
    })
    .where(eq(meetIntegration.id, integrationId));
}

export async function pruneExpiredMeetingRecordings(
  db: Db,
  {
    integrationId,
    userId,
    autoDeleteDays,
    lastPrunedAt,
  }: {
    integrationId?: string | null;
    userId: string;
    autoDeleteDays: number | null | undefined;
    lastPrunedAt?: Date | string | null;
  },
) {
  if (!autoDeleteDays || autoDeleteDays <= 0) {
    return { deleted: 0 };
  }

  const now = new Date();
  const savedDate = lastPrunedAt ? new Date(lastPrunedAt) : null;
  if (savedDate && !Number.isNaN(savedDate.getTime())) {
    const ageMs = now.getTime() - savedDate.getTime();
    if (ageMs <= PRUNE_RATE_LIMIT_MS) {
      return { deleted: 0 };
    }
  }

  const cutoff = new Date(now.getTime() - autoDeleteDays * 24 * 60 * 60 * 1000);

  const meetingIds = await db
    .select({ id: meeting.id })
    .from(meeting)
    .where(eq(meeting.userId, userId));

  if (meetingIds.length === 0) {
    if (integrationId) {
      await markPrunedAt(db, integrationId, now);
    }
    return { deleted: 0 };
  }

  const cutoffExpression = sql`COALESCE(${meetingMedia.readyAt}, ${meetingMedia.createdAt}) < ${cutoff}`;

  const deletedRows = await db
    .delete(meetingMedia)
    .where(
      and(
        inArray(meetingMedia.meetingId, meetingIds.map((row) => row.id)),
        inArray(meetingMedia.mediaType, PRUNE_MEDIA_TYPES),
        cutoffExpression,
      ),
    )
    .returning({ id: meetingMedia.id });

  if (integrationId) {
    await markPrunedAt(db, integrationId, now);
  }

  return { deleted: deletedRows.length };
}
