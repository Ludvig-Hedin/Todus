/**
 * Recall.ai Webhook Endpoint
 *
 * Handles bot status changes, recording ready, and transcript ready events.
 * Ported from reference/AA-MCP-MVP/src/app/api/webhooks/recall/route.ts
 */

import { Hono } from 'hono';
import type { HonoContext } from '../ctx';
import { createDb } from '../db';
import { meeting, meetingMedia, meetingTranscript } from '../db/schema';
import { eq, and, sql } from 'drizzle-orm';
import { env } from '../env';
import { getBotTranscript } from '../lib/recall';

export const recallWebhookRouter = new Hono<HonoContext>();

recallWebhookRouter.post('/', async (c) => {
  try {
    // Read body once so it's available for both HMAC and JSON parsing
    const rawBody = await c.req.text();

    // HMAC-SHA256 webhook signature verification
    const secret = env.RECALL_WEBHOOK_SECRET;
    if (secret) {
      const signature = c.req.header('x-recall-signature');
      if (!signature) {
        return c.json({ error: 'Unauthorized' }, 401);
      }
      const encoder = new TextEncoder();
      const key = await crypto.subtle.importKey(
        'raw',
        encoder.encode(secret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign'],
      );
      const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(rawBody));
      const expected = Array.from(new Uint8Array(mac))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('');
      // Accept both bare hex and "sha256=<hex>" prefixed forms
      const bare = signature.startsWith('sha256=') ? signature.slice(7) : signature;
      if (bare !== expected) {
        return c.json({ error: 'Unauthorized' }, 401);
      }
    } else {
      // In production, webhook secret must be configured to prevent spoofed events
      console.warn('[RECALL_WEBHOOK] No RECALL_WEBHOOK_SECRET set — webhook signature verification is disabled. Set it in production.');
    }

    const payload = JSON.parse(rawBody);
    const eventType = payload.event || payload.type;
    const botId = payload.data?.bot_id || payload.bot_id;

    console.log('[RECALL_WEBHOOK] Received:', { eventType, botId });

    if (!botId) {
      return c.json({ error: 'Missing bot_id' }, 400);
    }

    const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
    try {
      // Find meeting by recall_bot_id
      const [meetingRow] = await db
        .select()
        .from(meeting)
        .where(eq(meeting.recallBotId, botId))
        .limit(1);

      if (!meetingRow) {
        console.warn('[RECALL_WEBHOOK] No meeting found for bot:', botId);
        return c.json({ success: true, message: 'No matching meeting' });
      }

      switch (eventType) {
        case 'bot.status_change': {
          const status = payload.data?.status?.code;
          if (status === 'in_call_recording' || status === 'joining_call') {
            await db
              .update(meeting)
              .set({
                status: status === 'in_call_recording' ? 'recording' : 'bot_joining',
                botJoinedAt: status === 'in_call_recording' ? new Date() : undefined,
              })
              .where(eq(meeting.id, meetingRow.id));
          } else if (status === 'call_ended' || status === 'done') {
            await db
              .update(meeting)
              .set({ status: 'processing', botLeftAt: new Date() })
              .where(eq(meeting.id, meetingRow.id));
          } else if (status === 'fatal') {
            await db
              .update(meeting)
              .set({
                status: 'failed',
                errorMessage: payload.data?.status?.message || 'Bot encountered a fatal error',
              })
              .where(eq(meeting.id, meetingRow.id));
          }
          break;
        }

        case 'bot.recording_ready':
        case 'recording.done': {
          const recordingUrl = payload.data?.recording_url || payload.data?.video_url;
          if (recordingUrl) {
            // Upsert on recallMediaId to be idempotent on webhook retries
            await db
              .insert(meetingMedia)
              .values({
                id: crypto.randomUUID(),
                meetingId: meetingRow.id,
                mediaType: 'video_mixed',
                recallMediaId: payload.data?.recording_id || botId,
                url: recordingUrl,
                fileName: `recording-${botId}.mp4`,
                duration: payload.data?.duration || null,
                isReady: true,
                readyAt: new Date(),
                metadata: { source: 'recall_webhook', bot_id: botId },
              })
              .onConflictDoUpdate({
                target: meetingMedia.recallMediaId,
                set: { url: recordingUrl, isReady: true, readyAt: new Date() },
              });
          }
          // Only set ready once — prevents redundant writes on webhook retries
          await db
            .update(meeting)
            .set({ status: 'ready' })
            .where(and(eq(meeting.id, meetingRow.id), sql`${meeting.status} != 'ready'`));
          break;
        }

        case 'bot.transcript_ready':
        case 'transcript.done': {
          // Fetch full transcript from Recall API
          let transcriptFetched = false;
          try {
            const segments = await getBotTranscript(botId, env);
            if (segments.length > 0) {
              // Filter out segments without a recallSegmentId to avoid
              // onConflictDoNothing failing on null unique constraint
              const withId = segments.filter((seg) => seg.id);
              const withoutId = segments.filter((seg) => !seg.id);

              const mapSegment = (seg: (typeof segments)[number]) => ({
                id: crypto.randomUUID(),
                meetingId: meetingRow.id,
                startTime: Math.round(seg.start_time * 1000),
                endTime: Math.round(seg.end_time * 1000),
                speakerName: seg.speaker?.name || 'Unknown',
                speakerId: seg.speaker?.id || null,
                text: seg.text,
                confidence: seg.confidence?.toString() || null,
                isFromRealtime: false,
                recallSegmentId: seg.id || null,
              });

              // Insert segments with recall IDs — idempotent via onConflictDoNothing
              if (withId.length > 0) {
                const values = withId.map(mapSegment);
                for (let i = 0; i < values.length; i += 100) {
                  await db
                    .insert(meetingTranscript)
                    .values(values.slice(i, i + 100))
                    .onConflictDoNothing({ target: meetingTranscript.recallSegmentId });
                }
              }

              // Segments without recall IDs — delete existing then insert fresh
              // to avoid duplicates on webhook retries
              if (withoutId.length > 0) {
                // Only insert if no transcript segments exist yet (first time)
                const existingCount = await db
                  .select({ count: sql<number>`count(*)::int` })
                  .from(meetingTranscript)
                  .where(eq(meetingTranscript.meetingId, meetingRow.id));
                const totalExisting = existingCount[0]?.count ?? 0;

                // If we already have segments with IDs, skip the ID-less ones on retry
                if (totalExisting === 0 || withId.length === 0) {
                  const values = withoutId.map(mapSegment);
                  for (let i = 0; i < values.length; i += 100) {
                    await db.insert(meetingTranscript).values(values.slice(i, i + 100));
                  }
                }
              }

              transcriptFetched = true;
            }

            // Also save the transcript URL if provided — upsert to be idempotent
            const transcriptUrl = payload.data?.transcript_url;
            if (transcriptUrl) {
              await db
                .insert(meetingMedia)
                .values({
                  id: crypto.randomUUID(),
                  meetingId: meetingRow.id,
                  mediaType: 'transcript',
                  recallMediaId: `${botId}-transcript`,
                  url: transcriptUrl,
                  fileName: `transcript-${botId}.txt`,
                  isReady: true,
                  readyAt: new Date(),
                })
                .onConflictDoUpdate({
                  target: meetingMedia.recallMediaId,
                  set: { url: transcriptUrl, isReady: true, readyAt: new Date() },
                });
              transcriptFetched = true;
            }
          } catch (transcriptErr) {
            console.error('[RECALL_WEBHOOK] Failed to fetch transcript:', transcriptErr);
            // Don't mark as ready — transcript fetch failed
          }

          // Only set ready if transcript was actually fetched successfully
          if (transcriptFetched) {
            await db
              .update(meeting)
              .set({ status: 'ready' })
              .where(and(eq(meeting.id, meetingRow.id), sql`${meeting.status} != 'ready'`));
          }
          break;
        }

        default:
          console.log('[RECALL_WEBHOOK] Unhandled event type:', eventType);
      }

      return c.json({ success: true });
    } finally {
      await conn.end();
    }
  } catch (error) {
    console.error('[RECALL_WEBHOOK] Error:', error);
    return c.json({ error: 'Webhook processing failed' }, 500);
  }
});
