import { activeDriverProcedure, router } from '../trpc';
import { composeEmail } from './ai/compose';
import { getThread, getThreadsFromDB, getZeroAgent } from '../../lib/server-utils';
import { createDb } from '../../db';
import { task } from '../../db/schema';
import { env } from '../../env';
import { and, desc, eq } from 'drizzle-orm';
import { OAuth2Client } from 'google-auth-library';
import { stripHtml } from 'string-strip-html';
import { z } from 'zod';

const assistantActivityTypeSchema = z.enum([
  'summary_viewed',
  'task_created',
  'event_created',
  'draft_generated',
  'draft_opened',
  'auto_send_candidate_reviewed',
]);

const assistantRiskSchema = z.enum(['low', 'medium', 'high']);
const assistantNudgeTypeSchema = z.enum([
  'reply_needed',
  'meeting_request',
  'follow_up',
  'draft_ready',
]);

const assistantSuggestedTaskSchema = z.object({
  title: z.string(),
  description: z.string().nullable(),
  priority: z.enum(['none', 'low', 'medium', 'high']),
  dueDate: z.string().nullable(),
});

const assistantSuggestedEventSchema = z.object({
  title: z.string(),
  startAt: z.string().nullable(),
  endAt: z.string().nullable(),
  location: z.string().nullable(),
  notes: z.string().nullable(),
});

const assistantThreadSchema = z.object({
  threadId: z.string(),
  subject: z.string(),
  summary: z.string(),
  actionItems: z.array(z.string()),
  suggestedTasks: z.array(assistantSuggestedTaskSchema),
  suggestedEvent: assistantSuggestedEventSchema.nullable(),
  replyNeeded: z.boolean(),
  followUpNeeded: z.boolean(),
  meetingRequested: z.boolean(),
  draftEligible: z.boolean(),
  existingDraft: z.boolean(),
  riskLevel: assistantRiskSchema,
  confidence: z.number(),
  reason: z.string(),
  researchQueries: z.array(z.string()),
  autoSendCandidate: z.boolean(),
  autoSendReason: z.string().nullable(),
  relatedTaskCount: z.number(),
});

const assistantNudgeSchema = z.object({
  type: assistantNudgeTypeSchema,
  title: z.string(),
  description: z.string(),
  count: z.number(),
  threadIds: z.array(z.string()),
});

type AssistantSuggestedTask = z.infer<typeof assistantSuggestedTaskSchema>;
type AssistantSuggestedEvent = z.infer<typeof assistantSuggestedEventSchema>;

const REPLY_KEYWORDS = /\b(reply|respond|follow up|can you|could you|would you|let me know|please|need|review|send|confirm)\b/i;
const MEETING_KEYWORDS =
  /\b(meeting|schedule|calendar|appointment|call|zoom|teams|meet|availability|reschedule)\b/i;
const URGENT_KEYWORDS = /\b(urgent|asap|today|immediately|priority|by end of day|deadline)\b/i;
const AUTOMATED_KEYWORDS = /\b(no-?reply|unsubscribe|notification|automated|do not reply)\b/i;

function buildActivityKey(userId: string, threadId: string | null) {
  return `assistant-activity:${userId}:${threadId ?? 'global'}:${Date.now()}:${crypto.randomUUID()}`;
}

async function logAssistantActivity(
  userId: string,
  payload: {
    type: z.infer<typeof assistantActivityTypeSchema>;
    threadId?: string | null;
    summary?: string;
    metadata?: Record<string, unknown>;
  },
) {
  const key = buildActivityKey(userId, payload.threadId ?? null);
  await env.prompts_storage.put(
    key,
    JSON.stringify({
      ...payload,
      createdAt: new Date().toISOString(),
    }),
  );
}

async function listAssistantActivity(userId: string, threadId: string) {
  const prefix = `assistant-activity:${userId}:${threadId}:`;
  const listing = await env.prompts_storage.list({ prefix, limit: 20 });
  const entries = await Promise.all(
    listing.keys.map(async (key) => {
      const raw = await env.prompts_storage.get(key.name);
      if (!raw) return null;
      try {
        return JSON.parse(raw);
      } catch {
        // Malformed KV entry — skip rather than crashing the whole activity list
        return null;
      }
    }),
  );

  return entries.filter(Boolean);
}

function unique<T>(items: T[]) {
  return [...new Set(items)];
}

function cleanText(value: string | null | undefined) {
  if (!value) return '';
  return stripHtml(value).result.replace(/\s+/g, ' ').trim();
}

function latestMessageText(thread: Awaited<ReturnType<typeof getThread>>['result']) {
  const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
  return cleanText(latest?.decodedBody || latest?.body || '');
}

function buildFallbackSummary(thread: Awaited<ReturnType<typeof getThread>>['result']) {
  const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
  const participants = unique(
    thread.messages
      .map((message) => message.sender?.name || message.sender?.email)
      .filter((value): value is string => Boolean(value)),
  )
    .slice(0, 3)
    .join(', ');
  const bodyText = latestMessageText(thread);
  const snippet = bodyText.length > 240 ? `${bodyText.slice(0, 237)}...` : bodyText;
  const sender = latest?.sender?.name || latest?.sender?.email || 'Someone';
  const subject = latest?.subject || 'this thread';

  return `${sender} most recently wrote about "${subject}". Participants: ${participants || sender}. ${snippet}`.trim();
}

async function getThreadSummary(threadId: string, connectionId: string, thread: Awaited<ReturnType<typeof getThread>>['result']) {
  try {
    const response = await env.VECTORIZE.getByIds([threadId]);
    if (response.length && response[0]?.metadata?.['summary']) {
      const metadata = response[0].metadata as { summary?: string; connection?: string };
      if (metadata.connection === connectionId && metadata.summary) {
        const shortResponse = await env.AI.run('@cf/facebook/bart-large-cnn', {
          input_text: metadata.summary,
        });
        const short = typeof shortResponse?.summary === 'string' ? shortResponse.summary : null;
        if (short?.trim()) return short.trim();
      }
    }
  } catch (error) {
    console.warn('[mailAssistant.getThreadSummary] Failed to load vector summary', error);
  }

  return buildFallbackSummary(thread);
}

function inferDueDate(text: string, baseDate: Date) {
  const lower = text.toLowerCase();
  if (lower.includes('today')) return baseDate.toISOString();
  if (lower.includes('tomorrow')) {
    const tomorrow = new Date(baseDate);
    tomorrow.setDate(baseDate.getDate() + 1);
    return tomorrow.toISOString();
  }
  if (lower.includes('next week')) {
    const nextWeek = new Date(baseDate);
    nextWeek.setDate(baseDate.getDate() + 7);
    return nextWeek.toISOString();
  }
  return null;
}

function extractActionItems(text: string, subject: string, senderName: string) {
  const candidates = text
    .split(/[\n•\-]+|(?<=[.!?])\s+/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => REPLY_KEYWORDS.test(line) || MEETING_KEYWORDS.test(line) || URGENT_KEYWORDS.test(line));

  const cleaned = unique(
    candidates.map((line) =>
      line
        .replace(/^(please|can you|could you|would you|kindly)\s+/i, '')
        .replace(/\s+/g, ' ')
        .trim(),
    ),
  ).slice(0, 4);

  if (cleaned.length) return cleaned;

  if (REPLY_KEYWORDS.test(text)) {
    return [`Reply to ${senderName || 'the sender'} about ${subject || 'this thread'}`];
  }

  return [];
}

function extractEventSuggestion(subject: string, text: string, baseDate: Date): AssistantSuggestedEvent | null {
  if (!MEETING_KEYWORDS.test(`${subject} ${text}`)) return null;

  const lower = `${subject} ${text}`.toLowerCase();
  const timeMatch = lower.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)/i);
  let start = new Date(baseDate);

  if (lower.includes('tomorrow')) {
    start.setDate(start.getDate() + 1);
  } else if (!lower.includes('today')) {
    const monthDay = lower.match(
      /\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})\b/i,
    );
    if (monthDay) {
      const parsed = new Date(`${monthDay[1]} ${monthDay[2]}, ${baseDate.getFullYear()}`);
      if (!Number.isNaN(parsed.getTime())) start = parsed;
    }
  }

  if (!timeMatch) {
    return {
      title: subject.replace(/^re:\s*/i, '').trim() || 'Meeting',
      startAt: null,
      endAt: null,
      location: null,
      notes: 'Meeting request detected in email. Review details before creating the event.',
    };
  }

  let hour = Number(timeMatch[1]);
  const minutes = Number(timeMatch[2] ?? '0');
  const meridiem = timeMatch[3].toLowerCase();

  if (meridiem === 'pm' && hour < 12) hour += 12;
  if (meridiem === 'am' && hour === 12) hour = 0;

  start.setHours(hour, minutes, 0, 0);
  const end = new Date(start.getTime() + 60 * 60 * 1000);

  return {
    title: subject.replace(/^re:\s*/i, '').trim() || 'Meeting',
    startAt: start.toISOString(),
    endAt: end.toISOString(),
    location: null,
    notes: 'Created from Todus Mail Assistant suggestion.',
  };
}

function inferAutoSendCandidate(text: string, confidence: number) {
  const normalized = text.toLowerCase();
  if (confidence < 0.92) {
    return {
      autoSendCandidate: false,
      autoSendReason: null,
    };
  }

  if (/\b(thanks|thank you|sounds good|works for me|confirmed|see you then)\b/.test(normalized)) {
    return {
      autoSendCandidate: true,
      autoSendReason: 'This thread looks like a low-risk acknowledgment or confirmation.',
    };
  }

  return {
    autoSendCandidate: false,
    autoSendReason: null,
  };
}

async function getRelatedTasks(userId: string, threadId: string) {
  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
  try {
    return await db
      .select()
      .from(task)
      .where(and(eq(task.userId, userId), eq(task.emailThreadId, threadId)))
      .orderBy(desc(task.updatedAt))
      .limit(5);
  } finally {
    await conn.end();
  }
}

function buildSuggestedTasks(
  actionItems: string[],
  baseDate: Date,
  urgent: boolean,
): AssistantSuggestedTask[] {
  return actionItems.slice(0, 3).map((item) => ({
    title: item.length > 110 ? `${item.slice(0, 107)}...` : item,
    description: item,
    priority: urgent ? 'high' : 'medium',
    dueDate: inferDueDate(item, baseDate),
  }));
}

function createResearchQueries(subject: string, senderEmail: string | undefined, latestText: string) {
  const queries = [subject].filter(Boolean);
  if (senderEmail) {
    const [, domain] = senderEmail.split('@');
    if (domain) queries.push(`Is ${domain} trustworthy?`);
  }
  if (/invoice|contract|pricing|security|policy/i.test(latestText)) {
    queries.push(`Double check details for ${subject}`);
  }
  return unique(queries).slice(0, 3);
}

async function createGoogleCalendarEvent(
  refreshToken: string,
  payload: {
    title: string;
    startAt: string;
    endAt: string;
    location?: string | null;
    notes?: string | null;
  },
) {
  const auth = new OAuth2Client(env.GOOGLE_CLIENT_ID, env.GOOGLE_CLIENT_SECRET);
  auth.setCredentials({ refresh_token: refreshToken });
  const { token } = await auth.getAccessToken();
  if (!token) {
    throw new Error('Could not refresh Google token');
  }

  const response = await fetch('https://www.googleapis.com/calendar/v3/calendars/primary/events', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      summary: payload.title,
      location: payload.location ?? undefined,
      description: payload.notes ?? undefined,
      // TODO: replace 'UTC' with the user's actual timezone once it's stored per user
      start: { dateTime: payload.startAt, timeZone: 'UTC' },
      end: { dateTime: payload.endAt, timeZone: 'UTC' },
    }),
  });

  if (!response.ok) {
    throw new Error(`Google Calendar API error: ${response.status}`);
  }

  const json = (await response.json()) as { id: string; htmlLink?: string };
  return {
    id: json.id,
    htmlLink: json.htmlLink ?? null,
  };
}

export const mailAssistantRouter = router({
  getThread: activeDriverProcedure
    .input(z.object({ threadId: z.string() }))
    .output(assistantThreadSchema)
    .query(async ({ ctx, input }) => {
      const { activeConnection, sessionUser } = ctx;
      const { result: thread } = await getThread(activeConnection.id, input.threadId);
      const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
      const subject = latest?.subject || '';
      const senderName = latest?.sender?.name || latest?.sender?.email || 'the sender';
      const senderEmail = latest?.sender?.email;
      const latestText = latestMessageText(thread);
      const relatedTasks = await getRelatedTasks(sessionUser.id, input.threadId);
      const summary = await getThreadSummary(input.threadId, activeConnection.id, thread);
      const actionItems = extractActionItems(latestText, subject, senderName);
      const meetingRequested = MEETING_KEYWORDS.test(`${subject} ${latestText}`);
      const urgent = URGENT_KEYWORDS.test(`${subject} ${latestText}`);
      const automated = AUTOMATED_KEYWORDS.test(`${subject} ${latestText}`) || AUTOMATED_KEYWORDS.test(senderEmail ?? '');
      const replyNeeded =
        !automated &&
        !!latest &&
        latest.sender?.email?.toLowerCase() !== activeConnection.email.toLowerCase() &&
        (REPLY_KEYWORDS.test(latestText) || meetingRequested || urgent || actionItems.length > 0);
      const followUpNeeded = replyNeeded && !thread.hasUnread && relatedTasks.length === 0;
      const baseConfidence = automated ? 0.2 : replyNeeded ? 0.88 : meetingRequested ? 0.78 : 0.62;
      const confidence = Math.min(0.99, Math.max(0.2, baseConfidence + (relatedTasks.length > 0 ? 0.05 : 0)));
      const suggestedEvent = extractEventSuggestion(subject, latestText, new Date(latest?.receivedOn ?? Date.now()));
      const suggestedTasks = buildSuggestedTasks(actionItems, new Date(latest?.receivedOn ?? Date.now()), urgent);
      const riskLevel: z.infer<typeof assistantRiskSchema> = automated
        ? 'high'
        : urgent || meetingRequested
          ? 'medium'
          : 'low';
      const autoSend = inferAutoSendCandidate(latestText, confidence);

      return {
        threadId: input.threadId,
        subject,
        summary,
        actionItems,
        suggestedTasks,
        suggestedEvent,
        replyNeeded,
        followUpNeeded,
        meetingRequested,
        draftEligible: replyNeeded && confidence >= 0.8 && !thread.isLatestDraft && !automated,
        existingDraft: Boolean(thread.isLatestDraft),
        riskLevel,
        confidence,
        reason: automated
          ? 'The latest message looks automated, so the assistant will stay conservative.'
          : replyNeeded
            ? 'The latest message contains an actionable request or clear need for a reply.'
            : meetingRequested
              ? 'This thread looks like scheduling or meeting coordination.'
              : 'The assistant found light context but no strong action trigger.',
        researchQueries: createResearchQueries(subject, senderEmail, latestText),
        autoSendCandidate: autoSend.autoSendCandidate,
        autoSendReason: autoSend.autoSendReason,
        relatedTaskCount: relatedTasks.length,
      };
    }),

  getInboxNudges: activeDriverProcedure
    .input(z.object({ folder: z.string().optional().default('inbox') }))
    .output(z.object({ nudges: z.array(assistantNudgeSchema) }))
    .query(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      const threads = await getThreadsFromDB(activeConnection.id, {
        folder: input.folder,
        maxResults: 12,
      });

      const detailed = await Promise.all(
        threads.threads.slice(0, 8).map(async (threadRef) => {
          const { result } = await getThread(activeConnection.id, threadRef.id);
          const latest = result.latest ?? result.messages[result.messages.length - 1];
          const text = latestMessageText(result);
          const replyNeeded =
            !!latest &&
            latest.sender?.email?.toLowerCase() !== activeConnection.email.toLowerCase() &&
            REPLY_KEYWORDS.test(text);
          const meetingRequested = MEETING_KEYWORDS.test(`${latest?.subject ?? ''} ${text}`);
          const followUpNeeded = replyNeeded && !result.hasUnread;
          const draftReady = Boolean(result.isLatestDraft);
          return {
            id: threadRef.id,
            subject: latest?.subject || 'Thread',
            replyNeeded,
            meetingRequested,
            followUpNeeded,
            draftReady,
          };
        }),
      );

      const makeNudge = (
        type: z.infer<typeof assistantNudgeTypeSchema>,
        title: string,
        description: string,
        matches: typeof detailed,
      ) => ({
        type,
        title,
        description,
        count: matches.length,
        threadIds: matches.slice(0, 4).map((item) => item.id),
      });

      const replyNeededThreads = detailed.filter((item) => item.replyNeeded);
      const meetingThreads = detailed.filter((item) => item.meetingRequested);
      const followUpThreads = detailed.filter((item) => item.followUpNeeded);
      const draftReadyThreads = detailed.filter((item) => item.draftReady);

      const nudges = [
        replyNeededThreads.length
          ? makeNudge(
              'reply_needed',
              `${replyNeededThreads.length} thread${replyNeededThreads.length > 1 ? 's' : ''} likely need a reply`,
              'Todus found actionable replies waiting in your inbox.',
              replyNeededThreads,
            )
          : null,
        meetingThreads.length
          ? makeNudge(
              'meeting_request',
              `${meetingThreads.length} meeting request${meetingThreads.length > 1 ? 's' : ''} detected`,
              'Review these threads and turn them into calendar events quickly.',
              meetingThreads,
            )
          : null,
        followUpThreads.length
          ? makeNudge(
              'follow_up',
              `${followUpThreads.length} thread${followUpThreads.length > 1 ? 's' : ''} may need follow-up`,
              'These conversations look actionable but are no longer unread.',
              followUpThreads,
            )
          : null,
        draftReadyThreads.length
          ? makeNudge(
              'draft_ready',
              `${draftReadyThreads.length} thread${draftReadyThreads.length > 1 ? 's' : ''} already have drafts`,
              'Jump back into threads where a draft is already attached.',
              draftReadyThreads,
            )
          : null,
      ].filter((nudge): nudge is z.infer<typeof assistantNudgeSchema> => Boolean(nudge));

      return { nudges };
    }),

  createTaskFromSuggestion: activeDriverProcedure
    .input(
      z.object({
        threadId: z.string(),
        task: assistantSuggestedTaskSchema,
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const now = new Date();
        const [created] = await db
          .insert(task)
          .values({
            id: crypto.randomUUID(),
            userId: ctx.sessionUser.id,
            title: input.task.title,
            description: input.task.description ?? '',
            status: 'todo',
            priority: input.task.priority,
            dueDate: input.task.dueDate ? new Date(input.task.dueDate) : null,
            folderId: null,
            reminderIdentifier: null,
            emailThreadId: input.threadId,
            eventId: null,
            createdAt: now,
            updatedAt: now,
          })
          .returning();

        await logAssistantActivity(ctx.sessionUser.id, {
          type: 'task_created',
          threadId: input.threadId,
          summary: input.task.title,
          metadata: { taskId: created.id },
        });

        return { task: created };
      } finally {
        await conn.end();
      }
    }),

  createEventFromSuggestion: activeDriverProcedure
    .input(
      z.object({
        threadId: z.string(),
        event: assistantSuggestedEventSchema.extend({
          startAt: z.string(),
          endAt: z.string(),
        }),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection, sessionUser } = ctx;
      if (activeConnection.providerId !== 'google' || !activeConnection.refreshToken) {
        throw new Error('Calendar event creation is only available for connected Google accounts.');
      }

      const created = await createGoogleCalendarEvent(activeConnection.refreshToken, {
        title: input.event.title,
        startAt: input.event.startAt,
        endAt: input.event.endAt,
        location: input.event.location,
        notes: input.event.notes,
      });

      await logAssistantActivity(sessionUser.id, {
        type: 'event_created',
        threadId: input.threadId,
        summary: input.event.title,
        metadata: created,
      });

      return created;
    }),

  generateDraft: activeDriverProcedure
    .input(
      z.object({
        threadId: z.string(),
        openInComposer: z.boolean().optional().default(false),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection, sessionUser } = ctx;
      const { result: thread } = await getThread(activeConnection.id, input.threadId);

      if (thread.isLatestDraft) {
        return { draftId: null, created: false, reason: 'Draft already exists for this thread.' };
      }

      const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
      const latestBody = latestMessageText(thread);
      const relatedTasks = await getRelatedTasks(sessionUser.id, input.threadId);
      const suggestedEvent = extractEventSuggestion(
        latest?.subject || '',
        latestBody,
        new Date(latest?.receivedOn ?? Date.now()),
      );

      const taskContext = relatedTasks.length
        ? `\nRelated tasks:\n${relatedTasks.map((item) => `- ${item.title}`).join('\n')}`
        : '';
      const eventContext = suggestedEvent?.startAt
        ? `\nUpcoming event context:\n- ${suggestedEvent.title} at ${suggestedEvent.startAt}`
        : '';

      const prompt = `Draft a helpful reply to this email thread.${taskContext}${eventContext}\n\nKeep it concise, proactive, and ready to send after review.`;

      const threadMessages = thread.messages.map((message) => ({
        from: message.sender?.name || message.sender?.email || 'Unknown',
        to: message.to?.map((recipient) => recipient.name || recipient.email) || [],
        cc: message.cc?.map((recipient) => recipient.name || recipient.email) || [],
        subject: message.subject || '',
        body: cleanText(message.decodedBody || message.body || ''),
      }));

      const generatedBody = await composeEmail({
        prompt,
        threadMessages,
        username: sessionUser.name,
        connectionId: activeConnection.id,
      });

      const draftPayload = {
        to: latest?.sender?.email || '',
        cc:
          latest?.cc
            ?.map((recipient) => recipient.email)
            .filter((email) => email !== activeConnection.email)
            .join(', ') ?? '',
        bcc: '',
        subject: latest?.subject?.startsWith('Re: ') ? latest.subject : `Re: ${latest?.subject || 'No Subject'}`,
        message: generatedBody.replace(/\n/g, '<br>'),
        attachments: [],
        id: null,
        threadId: input.threadId,
        fromEmail: activeConnection.email,
      };

      const executionCtx = ctx.c.executionCtx;
      const { stub: agent } = await getZeroAgent(activeConnection.id, executionCtx);
      const createdDraft = await agent.createDraft(draftPayload);

      await logAssistantActivity(sessionUser.id, {
        type: 'draft_generated',
        threadId: input.threadId,
        summary: draftPayload.subject,
        metadata: {
          draftId: createdDraft?.id ?? null,
          openInComposer: input.openInComposer,
        },
      });

      return {
        draftId: createdDraft?.id ?? null,
        created: true,
        reason: 'Assistant draft generated.',
        preview: generatedBody,
      };
    }),

  logActivity: activeDriverProcedure
    .input(
      z.object({
        threadId: z.string().nullable().optional(),
        type: assistantActivityTypeSchema,
        summary: z.string().optional(),
        metadata: z.record(z.string(), z.unknown()).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      await logAssistantActivity(ctx.sessionUser.id, input);
      return { success: true };
    }),

  getActivity: activeDriverProcedure
    .input(z.object({ threadId: z.string() }))
    .query(async ({ ctx, input }) => {
      return {
        activity: await listAssistantActivity(ctx.sessionUser.id, input.threadId),
      };
    }),
});
