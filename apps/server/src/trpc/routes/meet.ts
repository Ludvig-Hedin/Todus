import { meeting, meetingMedia, meetingTranscript, meetIntegration } from '../../db/schema';
import { privateProcedure, createRateLimiterMiddleware, router } from '../trpc';
import { eq, and, desc, gte, lte, inArray, sql, isNull } from 'drizzle-orm';
import { createRecallBot, cancelBot } from '../../lib/recall';
import { pruneExpiredMeetingRecordings } from '../../lib/meeting-retention';
import { isProCustomer } from '../../lib/utils';
import { Ratelimit } from '@upstash/ratelimit';
import { TRPCError } from '@trpc/server';
import { createDb } from '../../db';
import { Autumn } from 'autumn-js';
import { env } from '../../env';
import { z } from 'zod';

// Helper to get a direct Drizzle DB connection
const getDb = () => createDb(env.HYPERDRIVE.connectionString);

type Db = ReturnType<typeof createDb>['db'];
type RecallBotResult = {
  id: string;
  meeting_url_id?: string | null;
};

async function claimMeetingForBotScheduling(db: Db, meetingId: string, userId: string) {
  const [claimed] = await db
    .update(meeting)
    .set({
      status: 'bot_joining',
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(meeting.id, meetingId),
        eq(meeting.userId, userId),
        eq(meeting.status, 'scheduled'),
        isNull(meeting.recallBotId),
      ),
    )
    .returning({ id: meeting.id });

  return !!claimed;
}

async function releasePendingBotClaim(db: Db, meetingId: string, userId: string) {
  await db
    .update(meeting)
    .set({
      status: 'scheduled',
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(meeting.id, meetingId),
        eq(meeting.userId, userId),
        eq(meeting.status, 'bot_joining'),
        isNull(meeting.recallBotId),
      ),
    );
}

async function persistScheduledBot(
  db: Db,
  meetingId: string,
  userId: string,
  botId: string,
  meetingUrlId: string | null | undefined,
  isScheduledForFuture: boolean,
) {
  const [updated] = await db
    .update(meeting)
    .set({
      recallBotId: botId,
      recallMeetingId: meetingUrlId ?? botId,
      status: isScheduledForFuture ? 'scheduled' : 'bot_joining',
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(meeting.id, meetingId),
        eq(meeting.userId, userId),
        eq(meeting.status, 'bot_joining'),
        isNull(meeting.recallBotId),
      ),
    )
    .returning();

  return updated;
}

type MeetResponse = {
  success: boolean;
  data: {
    created_at: string;
    id: string;
    is_large: boolean;
    live_stream_on_start: boolean;
    persist_chat: boolean;
    record_on_start: boolean;
    status: string;
    summarize_on_end: boolean;
    updated_at: string;
  };
};

export const meetRouter = router({
  // ─── Legacy: Create meeting via Autumn API ──────────────────────────
  create: privateProcedure
    .use(
      createRateLimiterMiddleware({
        limiter: Ratelimit.slidingWindow(10, '1m'),
        generatePrefix: ({ sessionUser }) => `ratelimit:meet-create-${sessionUser?.id}`,
      }),
    )
    .mutation(async ({ ctx }) => {
      const enableMeet = env.ENABLE_MEET === 'true';
      if (!enableMeet) return new Response('Not implemented', { status: 501 });
      const autumn = new Autumn({ secretKey: env.AUTUMN_SECRET_KEY });
      const customer = await autumn.customers.get(ctx.sessionUser?.id);
      if (!customer.data) {
        throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Customer not found' });
      }

      if (!isProCustomer(customer.data)) {
        throw new TRPCError({
          code: 'UNAUTHORIZED',
          message: 'Customer is not a pro customer, please upgrade to a pro plan',
        });
      }

      const AuthHeader = env.MEET_AUTH_HEADER;
      const response = await fetch(env.MEET_API_URL + '/meetings', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: AuthHeader,
        },
      });

      if (!response.ok) {
        console.error(await response.text());
        throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'Failed to create meeting' });
      }

      const data = await response.json<MeetResponse>();
      return data;
    }),

  // ─── Integration settings ──────────────────────────────────────────

  getIntegration: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const [row] = await db
        .select()
        .from(meetIntegration)
        .where(eq(meetIntegration.userId, ctx.sessionUser.id))
        .limit(1);
      return { integration: row || null };
    } finally {
      await conn.end();
    }
  }),

  upsertIntegration: privateProcedure
    .input(
      z.object({
        botName: z.string().optional(),
        isEnabled: z.boolean().optional(),
        autoJoin: z.boolean().optional(),
        joinEarlyMinutes: z.number().int().min(0).max(10).optional(),
        autoGenerateSummary: z.boolean().optional(),
        summaryLanguage: z.string().min(2).max(5).optional(),
        excludeAllDay: z.boolean().optional(),
        minimumDurationMinutes: z.number().int().min(0).max(120).optional(),
        notifyOnRecordingStart: z.boolean().optional(),
        notifyOnRecapReady: z.boolean().optional(),
        autoDeleteDays: z.number().int().min(0).max(365).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [existing] = await db
          .select()
          .from(meetIntegration)
          .where(eq(meetIntegration.userId, ctx.sessionUser.id))
          .limit(1);

        if (existing) {
          // Build update object from all provided fields
          const updates: Record<string, unknown> = {};
          for (const [key, value] of Object.entries(input)) {
            if (value !== undefined) updates[key] = value;
          }

          const [updated] = await db
            .update(meetIntegration)
            .set(updates)
            .where(eq(meetIntegration.id, existing.id))
            .returning();
          return { integration: updated };
        }

        const [created] = await db
          .insert(meetIntegration)
          .values({
            id: crypto.randomUUID(),
            userId: ctx.sessionUser.id,
            botName: input.botName || 'Notetaker',
            isEnabled: input.isEnabled ?? true,
            autoJoin: input.autoJoin ?? false,
            joinEarlyMinutes: input.joinEarlyMinutes ?? 1,
            autoGenerateSummary: input.autoGenerateSummary ?? true,
            summaryLanguage: input.summaryLanguage ?? 'en',
            excludeAllDay: input.excludeAllDay ?? true,
            minimumDurationMinutes: input.minimumDurationMinutes ?? 5,
            notifyOnRecordingStart: input.notifyOnRecordingStart ?? true,
            notifyOnRecapReady: input.notifyOnRecapReady ?? true,
            autoDeleteDays: input.autoDeleteDays ?? 0,
          })
          .returning();
        return { integration: created };
      } finally {
        await conn.end();
      }
    }),

  // ─── Meeting CRUD ──────────────────────────────────────────────────

  listMeetings: privateProcedure
    .input(
      z
        .object({
          status: z
            .enum([
              'scheduled',
              'bot_joining',
              'recording',
              'processing',
              'ready',
              'failed',
              'cancelled',
            ])
            .optional(),
          search: z.string().optional(),
          from: z.string().datetime().optional(),
          to: z.string().datetime().optional(),
          limit: z.number().int().min(1).max(100).optional().default(50),
          offset: z.number().int().min(0).optional().default(0),
        })
        .optional()
        .default({}),
    )
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [integration] = await db
          .select({
            id: meetIntegration.id,
            autoDeleteDays: meetIntegration.autoDeleteDays,
            lastPrunedAt: meetIntegration.lastPrunedAt,
          })
          .from(meetIntegration)
          .where(eq(meetIntegration.userId, ctx.sessionUser.id))
          .limit(1);

        await pruneExpiredMeetingRecordings(db, {
          integrationId: integration?.id,
          userId: ctx.sessionUser.id,
          autoDeleteDays: integration?.autoDeleteDays,
          lastPrunedAt: integration?.lastPrunedAt,
        });

        const conditions = [eq(meeting.userId, ctx.sessionUser.id)];

        if (input.status) conditions.push(eq(meeting.status, input.status));
        if (input.search) {
          // Escape SQL LIKE wildcards in the user-supplied search string
          const escaped = input.search.replace(/[%_\\]/g, '\\$&');
          const pattern = `%${escaped}%`;
          conditions.push(sql`${meeting.title} LIKE ${pattern} ESCAPE '\\'`);
        }
        if (input.from) conditions.push(gte(meeting.startsAt, new Date(input.from)));
        if (input.to) conditions.push(lte(meeting.startsAt, new Date(input.to)));

        const meetings = await db
          .select()
          .from(meeting)
          .where(and(...conditions))
          .orderBy(desc(meeting.startsAt))
          .limit(input.limit)
          .offset(input.offset);

        return { meetings };
      } finally {
        await conn.end();
      }
    }),

  getMeeting: privateProcedure
    .input(z.object({ meetingId: z.string() }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [integration] = await db
          .select({
            id: meetIntegration.id,
            autoDeleteDays: meetIntegration.autoDeleteDays,
            lastPrunedAt: meetIntegration.lastPrunedAt,
          })
          .from(meetIntegration)
          .where(eq(meetIntegration.userId, ctx.sessionUser.id))
          .limit(1);

        await pruneExpiredMeetingRecordings(db, {
          integrationId: integration?.id,
          userId: ctx.sessionUser.id,
          autoDeleteDays: integration?.autoDeleteDays,
          lastPrunedAt: integration?.lastPrunedAt,
        });

        const [meetingRow] = await db
          .select()
          .from(meeting)
          .where(and(eq(meeting.id, input.meetingId), eq(meeting.userId, ctx.sessionUser.id)))
          .limit(1);

        if (!meetingRow) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Meeting not found' });
        }

        // Fetch media and transcript in parallel
        const [media, transcripts] = await Promise.all([
          db
            .select()
            .from(meetingMedia)
            .where(eq(meetingMedia.meetingId, input.meetingId))
            .orderBy(meetingMedia.createdAt),
          db
            .select()
            .from(meetingTranscript)
            .where(eq(meetingTranscript.meetingId, input.meetingId))
            .orderBy(meetingTranscript.startTime),
        ]);

        return { meeting: meetingRow, media, transcripts };
      } finally {
        await conn.end();
      }
    }),

  createMeeting: privateProcedure
    .input(
      z.object({
        title: z.string(),
        meetUrl: z.string().url(),
        startsAt: z.string().datetime(),
        endsAt: z.string().datetime().optional(),
        description: z.string().optional(),
        participants: z.any().optional(),
        googleEventId: z.string().optional(),
        calendarId: z.string().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const id = crypto.randomUUID();
        const now = new Date();

        // Get user's integration for the integrationId FK
        const [integration] = await db
          .select()
          .from(meetIntegration)
          .where(eq(meetIntegration.userId, ctx.sessionUser.id))
          .limit(1);

        const [created] = await db
          .insert(meeting)
          .values({
            id,
            userId: ctx.sessionUser.id,
            integrationId: integration?.id || null,
            title: input.title,
            meetUrl: input.meetUrl,
            startsAt: new Date(input.startsAt),
            endsAt: input.endsAt ? new Date(input.endsAt) : null,
            description: input.description || null,
            participants: input.participants || null,
            googleEventId: input.googleEventId || null,
            calendarId: input.calendarId || null,
            status: 'scheduled',
            createdAt: now,
            updatedAt: now,
          })
          .returning();

        return { meeting: created };
      } finally {
        await conn.end();
      }
    }),

  deleteMeeting: privateProcedure
    .input(z.object({ meetingId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [meetingRow] = await db
          .select()
          .from(meeting)
          .where(and(eq(meeting.id, input.meetingId), eq(meeting.userId, ctx.sessionUser.id)))
          .limit(1);

        if (!meetingRow) throw new TRPCError({ code: 'NOT_FOUND', message: 'Meeting not found' });

        // Prevent deletion while a bot is actively recording
        if (meetingRow.recallBotId && ['recording', 'bot_joining'].includes(meetingRow.status)) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'Cannot delete a meeting that is currently being recorded.',
          });
        }

        await db
          .delete(meeting)
          .where(and(eq(meeting.id, input.meetingId), eq(meeting.userId, ctx.sessionUser.id)));
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  // ─── Recall.ai bot operations ──────────────────────────────────────

  scheduleBot: privateProcedure
    .input(z.object({ meetingId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Get the meeting
        const [meetingRow] = await db
          .select()
          .from(meeting)
          .where(and(eq(meeting.id, input.meetingId), eq(meeting.userId, ctx.sessionUser.id)))
          .limit(1);

        if (!meetingRow) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Meeting not found' });
        }

        if (meetingRow.recallBotId) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'Bot already scheduled for this meeting',
          });
        }

        // Get bot name from integration settings
        const [integration] = await db
          .select()
          .from(meetIntegration)
          .where(eq(meetIntegration.userId, ctx.sessionUser.id))
          .limit(1);

        const botName = integration?.botName || 'Note Taker';

        // Determine if we should schedule for the future or join now
        const now = new Date();
        const startsAt = new Date(meetingRow.startsAt);
        const minutesUntilStart = (startsAt.getTime() - now.getTime()) / (1000 * 60);
        // If meeting starts in more than 2 minutes, schedule for the future
        const startAtISO = minutesUntilStart > 2 ? startsAt.toISOString() : undefined;

        const claimed = await claimMeetingForBotScheduling(db, meetingRow.id, ctx.sessionUser.id);
        if (!claimed) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'Bot already scheduled for this meeting',
          });
        }

        let result: RecallBotResult;
        try {
          result = await createRecallBot(
            {
              meetingUrl: meetingRow.meetUrl,
              botName,
              startAtISO,
              metadata: { meeting_id: meetingRow.id, user_id: ctx.sessionUser.id },
            },
            env,
          );
        } catch (createErr) {
          await releasePendingBotClaim(db, meetingRow.id, ctx.sessionUser.id);
          throw createErr;
        }

        try {
          const updated = await persistScheduledBot(
            db,
            meetingRow.id,
            ctx.sessionUser.id,
            result.id,
            result.meeting_url_id,
            !!startAtISO,
          );

          if (!updated) {
            throw new Error('Failed to persist scheduled bot');
          }

          return { meeting: updated, botId: result.id };
        } catch (dbErr) {
          // Cancel the bot to prevent it from joining without a DB record
          try {
            await cancelBot(result.id, env);
          } catch {
            /* best effort */
          }
          await releasePendingBotClaim(db, meetingRow.id, ctx.sessionUser.id);
          throw dbErr;
        }
      } finally {
        await conn.end();
      }
    }),

  cancelBot: privateProcedure
    .input(z.object({ meetingId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [meetingRow] = await db
          .select()
          .from(meeting)
          .where(and(eq(meeting.id, input.meetingId), eq(meeting.userId, ctx.sessionUser.id)))
          .limit(1);

        if (!meetingRow) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Meeting not found' });
        }

        if (!meetingRow.recallBotId) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'No bot scheduled for this meeting',
          });
        }

        // Cancel the bot via Recall API
        try {
          await cancelBot(meetingRow.recallBotId, env);
        } catch (err) {
          // Bot may already be gone — continue with cleanup
          console.warn('[MEET] Failed to cancel bot via API:', err);
        }

        const [updated] = await db
          .update(meeting)
          .set({
            recallBotId: null,
            recallMeetingId: null,
            status: 'cancelled',
          })
          .where(eq(meeting.id, meetingRow.id))
          .returning();

        return { meeting: updated };
      } finally {
        await conn.end();
      }
    }),

  // ─── AI: Summary generation ────────────────────────────────────────

  generateSummary: privateProcedure
    .input(z.object({ meetingId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Get meeting + transcript
        const [meetingRow] = await db
          .select()
          .from(meeting)
          .where(and(eq(meeting.id, input.meetingId), eq(meeting.userId, ctx.sessionUser.id)))
          .limit(1);

        if (!meetingRow) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Meeting not found' });
        }

        const transcripts = await db
          .select()
          .from(meetingTranscript)
          .where(eq(meetingTranscript.meetingId, input.meetingId))
          .orderBy(meetingTranscript.startTime);

        if (transcripts.length === 0) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'No transcript available to summarize',
          });
        }

        // Build transcript text for the AI
        const transcriptText = transcripts
          .map((t) => `[${formatMs(t.startTime)}] ${t.speakerName}: ${t.text}`)
          .join('\n');

        // Call AI for summary + action items
        const { generateText } = await import('ai');
        const { openai } = await import('@ai-sdk/openai');

        const model = openai(env.OPENAI_MINI_MODEL || 'gpt-4o-mini');
        const systemPrompt = `You are a meeting analyst. Given a meeting transcript, produce:
1. A concise summary (3-6 sentences) covering the key discussion points and decisions.
2. A JSON array of action items, each with: { "description": string, "owner": string (speaker name or "Unassigned"), "dueDate": string | null }.

Respond in this exact JSON format:
{
  "summary": "...",
  "actionItems": [...]
}`;

        const userPrompt = `Meeting: ${meetingRow.title}
Date: ${meetingRow.startsAt}
Participants: ${JSON.stringify(meetingRow.participants || [])}

Transcript:
${transcriptText.slice(0, 30000)}`; // Cap at ~30k chars to stay within context

        const result = await generateText({
          model,
          system: systemPrompt,
          prompt: userPrompt,
        });

        // Parse AI response
        let summary = '';
        let actionItems: unknown[] = [];
        try {
          const parsed = JSON.parse(result.text);
          summary = parsed.summary || '';
          actionItems = parsed.actionItems || [];
        } catch {
          // If JSON parsing fails, use the raw text as summary
          summary = result.text;
        }

        // Store results
        const [updated] = await db
          .update(meeting)
          .set({ aiSummary: summary, actionItems })
          .where(eq(meeting.id, meetingRow.id))
          .returning();

        return { meeting: updated, summary, actionItems };
      } finally {
        await conn.end();
      }
    }),

  // ─── AI: Q&A on meeting transcript ─────────────────────────────────

  askQuestion: privateProcedure
    .input(
      z.object({
        meetingId: z.string(),
        question: z.string().min(1).max(2000),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Get meeting + transcript
        const [meetingRow] = await db
          .select()
          .from(meeting)
          .where(and(eq(meeting.id, input.meetingId), eq(meeting.userId, ctx.sessionUser.id)))
          .limit(1);

        if (!meetingRow) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Meeting not found' });
        }

        const transcripts = await db
          .select()
          .from(meetingTranscript)
          .where(eq(meetingTranscript.meetingId, input.meetingId))
          .orderBy(meetingTranscript.startTime);

        // Build context from transcript + recap
        const transcriptText = transcripts
          .map((t) => `[${formatMs(t.startTime)}] ${t.speakerName}: ${t.text}`)
          .join('\n');

        const context = [
          `Meeting: ${meetingRow.title}`,
          `Date: ${meetingRow.startsAt}`,
          meetingRow.aiSummary ? `Summary: ${meetingRow.aiSummary}` : '',
          meetingRow.actionItems ? `Action Items: ${JSON.stringify(meetingRow.actionItems)}` : '',
          `\nTranscript:\n${transcriptText.slice(0, 25000)}`,
        ]
          .filter(Boolean)
          .join('\n');

        const { generateText } = await import('ai');
        const { openai } = await import('@ai-sdk/openai');

        const model = openai(env.OPENAI_MINI_MODEL || 'gpt-4o-mini');

        const result = await generateText({
          model,
          system: `You are an assistant that answers questions about a specific meeting based on its transcript and summary. Be precise and cite the relevant parts of the transcript when possible. If the answer is not in the transcript, say so.`,
          prompt: `${context}\n\nQuestion: ${input.question}`,
        });

        return { answer: result.text };
      } finally {
        await conn.end();
      }
    }),

  // ─── Calendar sync ─────────────────────────────────────────────────
  // Pulls Google Calendar events with Meet URLs and upserts meetings

  syncFromCalendar: privateProcedure.mutation(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      // Get the user's Google connection for calendar access
      const { connection: connectionTable } = await import('../../db/schema');
      const [googleConn] = await db
        .select()
        .from(connectionTable)
        .where(
          and(
            eq(connectionTable.userId, ctx.sessionUser.id),
            eq(connectionTable.providerId, 'google'),
          ),
        )
        .limit(1);

      if (!googleConn || !googleConn.accessToken) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'No Google connection found. Please connect your Google account first.',
        });
      }

      // Check if token is expired and refresh if needed
      let accessToken = googleConn.accessToken;
      if (googleConn.expiresAt && new Date(googleConn.expiresAt) < new Date()) {
        if (!googleConn.refreshToken) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'Google token expired. Please reconnect.',
          });
        }
        // Refresh the token
        const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            grant_type: 'refresh_token',
            client_id: env.GOOGLE_CLIENT_ID,
            client_secret: env.GOOGLE_CLIENT_SECRET,
            refresh_token: googleConn.refreshToken,
          }),
        });
        if (!tokenRes.ok) {
          throw new TRPCError({ code: 'BAD_REQUEST', message: 'Failed to refresh Google token.' });
        }
        const tokenData = await tokenRes.json<{ access_token: string; expires_in: number }>();
        accessToken = tokenData.access_token;

        // Update the stored token
        await db
          .update(connectionTable)
          .set({
            accessToken,
            expiresAt: new Date(Date.now() + tokenData.expires_in * 1000),
          })
          .where(eq(connectionTable.id, googleConn.id));
      }

      // Fetch calendar events for the 7 days before and after now (14-day window)
      const now = new Date();
      const weekLater = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
      const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

      const calendarRes = await fetch(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events?` +
          new URLSearchParams({
            timeMin: weekAgo.toISOString(),
            timeMax: weekLater.toISOString(),
            singleEvents: 'true',
            orderBy: 'startTime',
            maxResults: '100',
          }),
        { headers: { Authorization: `Bearer ${accessToken}` } },
      );

      if (!calendarRes.ok) {
        const errText = await calendarRes.text();
        console.error('[MEET_SYNC] Calendar API error:', errText);
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'Failed to fetch calendar events',
        });
      }

      const calendarData = await calendarRes.json<{
        items: Array<{
          id: string;
          summary?: string;
          description?: string;
          hangoutLink?: string;
          conferenceData?: { entryPoints?: Array<{ uri?: string; entryPointType?: string }> };
          start?: { dateTime?: string; date?: string };
          end?: { dateTime?: string; date?: string };
          attendees?: Array<{ email?: string; displayName?: string; responseStatus?: string }>;
        }>;
      }>();

      // Filter events with Google Meet URLs
      const meetEvents = (calendarData.items || []).filter((event) => {
        if (event.hangoutLink) return true;
        const meetEntry = event.conferenceData?.entryPoints?.find(
          (ep) => ep.entryPointType === 'video' && ep.uri?.includes('meet.google.com'),
        );
        return !!meetEntry;
      });

      // Get user's integration
      const [integration] = await db
        .select({
          id: meetIntegration.id,
          botName: meetIntegration.botName,
          autoJoin: meetIntegration.autoJoin,
          excludeAllDay: meetIntegration.excludeAllDay,
          minimumDurationMinutes: meetIntegration.minimumDurationMinutes,
          autoDeleteDays: meetIntegration.autoDeleteDays,
          lastPrunedAt: meetIntegration.lastPrunedAt,
        })
        .from(meetIntegration)
        .where(eq(meetIntegration.userId, ctx.sessionUser.id))
        .limit(1);

      // Batch-fetch all existing meetings for these calendar event IDs in one query
      // instead of one query per event (N+1 avoidance)
      const googleEventIds = meetEvents.map((e) => e.id).filter(Boolean);
      const existingMeetings =
        googleEventIds.length > 0
          ? await db
              .select()
              .from(meeting)
              .where(
                and(
                  eq(meeting.userId, ctx.sessionUser.id),
                  inArray(meeting.googleEventId, googleEventIds),
                ),
              )
          : [];
      const existingByEventId = new Map(existingMeetings.map((m) => [m.googleEventId, m]));

      // Determine auto-record preferences
      const shouldAutoRecord = integration?.autoJoin ?? false;
      const excludeAllDay = integration?.excludeAllDay ?? true;
      const minDuration = integration?.minimumDurationMinutes ?? 5;
      const botName = integration?.botName || 'Notetaker';

      let synced = 0;
      const newMeetingIds: { id: string; meetUrl: string; startsAt: Date }[] = [];

      for (const event of meetEvents) {
        const meetUrl =
          event.hangoutLink ||
          event.conferenceData?.entryPoints?.find(
            (ep) => ep.entryPointType === 'video' && ep.uri?.includes('meet.google.com'),
          )?.uri ||
          '';

        if (!meetUrl) continue;

        // All-day events use event.start.date (no dateTime) — skip if setting enabled
        const isAllDay = !event.start?.dateTime && !!event.start?.date;
        if (isAllDay && excludeAllDay) continue;

        const startDateRaw = event.start?.dateTime || event.start?.date;
        if (!startDateRaw) continue;
        const startsAt = new Date(startDateRaw);
        if (isNaN(startsAt.getTime())) continue;
        const endsAt = event.end?.dateTime ? new Date(event.end.dateTime) : null;

        // Skip meetings shorter than minimum duration
        if (endsAt && minDuration > 0) {
          const durationMinutes = (endsAt.getTime() - startsAt.getTime()) / (1000 * 60);
          if (durationMinutes < minDuration) continue;
        }

        const existing = existingByEventId.get(event.id);

        if (existing) {
          await db
            .update(meeting)
            .set({
              title: event.summary || 'Untitled Meeting',
              startsAt,
              endsAt,
              participants: event.attendees || null,
            })
            .where(eq(meeting.id, existing.id));

          if (shouldAutoRecord && !existing.recallBotId && existing.status === 'scheduled' && startsAt > now) {
            newMeetingIds.push({ id: existing.id, meetUrl, startsAt });
          }
        } else {
          const newId = crypto.randomUUID();
          await db.insert(meeting).values({
            id: newId,
            userId: ctx.sessionUser.id,
            integrationId: integration?.id || null,
            googleEventId: event.id,
            calendarId: 'primary',
            title: event.summary || 'Untitled Meeting',
            description: event.description || null,
            meetUrl,
            startsAt,
            endsAt,
            participants: event.attendees || null,
            status: 'scheduled',
            createdAt: new Date(),
            updatedAt: new Date(),
          });
          synced++;

          // Track new upcoming meetings for auto-record
          if (shouldAutoRecord && startsAt > now) {
            newMeetingIds.push({ id: newId, meetUrl, startsAt });
          }
        }
      }

      // Auto-schedule recording for new upcoming meetings
      let autoRecorded = 0;
      for (const m of newMeetingIds) {
        try {
          const claimed = await claimMeetingForBotScheduling(db, m.id, ctx.sessionUser.id);
          if (!claimed) {
            continue;
          }

          const minutesUntilStart = (m.startsAt.getTime() - now.getTime()) / (1000 * 60);
          const startAtISO = minutesUntilStart > 2 ? m.startsAt.toISOString() : undefined;

          let result: RecallBotResult;
          try {
            result = await createRecallBot(
              {
                meetingUrl: m.meetUrl,
                botName,
                startAtISO,
                metadata: { meeting_id: m.id, user_id: ctx.sessionUser.id },
              },
              env,
            );
          } catch (createErr) {
            await releasePendingBotClaim(db, m.id, ctx.sessionUser.id);
            throw createErr;
          }

          try {
            const updated = await persistScheduledBot(
              db,
              m.id,
              ctx.sessionUser.id,
              result.id,
              result.meeting_url_id,
              !!startAtISO,
            );

            if (!updated) {
              throw new Error('Failed to persist scheduled bot');
            }
          } catch (dbErr) {
            try {
              await cancelBot(result.id, env);
            } catch (cancelErr) {
              console.warn('[MEET_SYNC] Failed to cancel bot after DB update error:', {
                meetingId: m.id,
                botId: result.id,
                error: cancelErr,
              });
            }
            await releasePendingBotClaim(db, m.id, ctx.sessionUser.id);
            throw dbErr;
          }

          autoRecorded++;
        } catch (botErr) {
          // Auto-record is best-effort — don't fail the sync
          console.warn('[MEET_SYNC] Failed to auto-schedule bot for meeting:', m.id, botErr);
        }
      }

      await pruneExpiredMeetingRecordings(db, {
        integrationId: integration?.id,
        userId: ctx.sessionUser.id,
        autoDeleteDays: integration?.autoDeleteDays,
        lastPrunedAt: integration?.lastPrunedAt,
      });

      return { synced, total: meetEvents.length, autoRecorded };
    } finally {
      await conn.end();
    }
  }),
});

// Helper: format milliseconds to HH:MM:SS
function formatMs(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0)
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
