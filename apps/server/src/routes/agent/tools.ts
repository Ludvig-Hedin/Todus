import { getCurrentDateContext, GmailSearchAssistantSystemPrompt } from '../../lib/prompts';
import { buildAIProfilePrompt } from '../../lib/ai-profile';
import { getThread, getZeroAgent, getZeroDB } from '../../lib/server-utils';
import type { IGetThreadResponse } from '../../lib/driver/types';
import { composeEmail } from '../../trpc/routes/ai/compose';
import { buildAuthClient, calendarFetchJSON } from '../../trpc/routes/calendar';
import {
  meeting,
  meetingTranscript,
  connection,
  task,
  assistantPersonMemory,
  assistantWorkstreamMemory,
  assistantOpenLoop,
} from '../../db/schema';
import { perplexity } from '@ai-sdk/perplexity';
import { eq, desc, and, like, ilike, or, inArray } from 'drizzle-orm';
import { colors } from '../../lib/prompts';
import { resolveModel } from '../../lib/ai-model-resolver';
import { generateText, tool } from 'ai';
import { Tools } from '../../types';
import { env } from '../../env';
import { z } from 'zod';
import { createDb } from '../../db';

type ModelTypes = 'summarize' | 'general' | 'chat' | 'vectorize';

const models: Record<ModelTypes, any> = {
  summarize: '@cf/facebook/bart-large-cnn',
  general: 'llama-3.3-70b-instruct-fp8-fast',
  chat: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
  vectorize: '@cf/baai/bge-large-en-v1.5',
};

export const getEmbeddingVector = async (
  text: string,
  gatewayId: 'vectorize-save' | 'vectorize-load',
) => {
  try {
    const embeddingResponse = await env.AI.run(
      models.vectorize,
      { text },
      {
        gateway: {
          id: gatewayId,
        },
      },
    );
    const embeddingVector = embeddingResponse.data[0];
    return embeddingVector ?? null;
  } catch (error) {
    console.log('[getEmbeddingVector] failed', error);
    return null;
  }
};

// const askZeroMailbox = (connectionId: string) =>
//   tool({
//     description: 'Ask Zero a question about the mailbox',
//     parameters: z.object({
//       question: z.string().describe('The question to ask Zero'),
//       topK: z.number().describe('The number of results to return').max(9).min(1).default(3),
//     }),
//     execute: async ({ question, topK = 3 }) => {
//       const embedding = await getEmbeddingVector(question, 'vectorize-load');
//       if (!embedding) {
//         return { error: 'Failed to get embedding' };
//       }
//       const threadResults = await env.VECTORIZE.query(embedding, {
//         topK,
//         returnMetadata: 'all',
//         filter: {
//           connection: connectionId,
//         },
//       });

//       if (!threadResults.matches.length) {
//         return {
//           response: [],
//           success: false,
//         };
//       }
//       return {
//         response: threadResults.matches.map((e) => e.metadata?.['summary'] ?? 'no content'),
//         success: true,
//       };
//     },
//   });

// const askZeroThread = (connectionId: string) =>
//   tool({
//     description: 'Ask Zero a question about a specific thread',
//     parameters: z.object({
//       threadId: z.string().describe('The ID of the thread to ask Zero about'),
//       question: z.string().describe('The question to ask Zero'),
//     }),
//     execute: async ({ threadId, question }) => {
//       const response = await env.VECTORIZE.getByIds([threadId]);
//       if (!response.length) return { response: "I don't know, no threads found", success: false };
//       const embedding = await getEmbeddingVector(question, 'vectorize-load');
//       if (!embedding) {
//         return { error: 'Failed to get embedding' };
//       }
//       const threadResults = await env.VECTORIZE.query(embedding, {
//         topK: 1,
//         returnMetadata: 'all',
//         filter: {
//           thread: threadId,
//           connection: connectionId,
//         },
//       });
//       const topThread = threadResults.matches[0];
//       if (!topThread) return { response: "I don't know, no threads found", success: false };
//       return {
//         response: topThread.metadata?.['summary'] ?? 'no content',
//         success: true,
//       };
//     },
//   });

/**
 * ⚠️  IMPORTANT
 * Do NOT return the full thread here – it bloats the conversation state and
 * may hit the 128 MB cap in Cloudflare Workers. We only hand back a lightweight
 * tag that the front-end can interpret.
 *
 * The tag format must be exactly: <thread id="{id}"/>
 */
const getEmail = () =>
  tool({
    description: 'Return a placeholder tag for a specific email thread by ID',
    parameters: z.object({
      id: z.string().describe('The ID of the email thread to retrieve'),
    }),
    execute: async ({ id }) => {
      /* nothing to fetch server-side any more */
      return `<thread id="${id}"/>`;
    },
  });

const getThreadSummary = (connectionId: string) =>
  tool({
    description: 'Get the summary of a specific email thread',
    parameters: z.object({
      id: z.string().describe('The ID of the email thread to get the summary of'),
    }),
    execute: async ({ id }) => {
      const response = await env.VECTORIZE.getByIds([id]);
      let thread: IGetThreadResponse | null = null;
      try {
        const { result } = await getThread(connectionId, id);
        thread = result;
      } catch (error) {
        console.error('Error getting thread', error);
        return { error: 'Thread not found' };
      }
      if (response.length && response?.[0]?.metadata?.['summary'] && thread?.latest?.subject) {
        const result = response[0].metadata as { summary: string; connection: string };
        if (result.connection !== connectionId) {
          return null;
        }
        const shortResponse = await env.AI.run('@cf/facebook/bart-large-cnn', {
          input_text: result.summary,
        });
        return {
          short: shortResponse.summary,
          subject: thread.latest?.subject,
          sender: thread.latest?.sender,
          date: thread.latest?.receivedOn,
        };
      }
      return {
        subject: thread.latest?.subject,
        sender: thread.latest?.sender,
        date: thread.latest?.receivedOn,
      };
    },
  });

const composeEmailTool = (connectionId: string) =>
  tool({
    description: 'Compose an email using AI assistance',
    parameters: z.object({
      prompt: z.string().describe('The prompt or rough draft for the email'),
      emailSubject: z.string().optional().describe('The subject of the email'),
      to: z.array(z.string()).optional().describe('Recipients of the email'),
      cc: z.array(z.string()).optional().describe('CC recipients of the email'),
      threadMessages: z
        .array(
          z.object({
            from: z.string().describe('The sender of the email'),
            to: z.array(z.string()).describe('The recipients of the email'),
            cc: z.array(z.string()).optional().describe('The CC recipients of the email'),
            subject: z.string().describe('The subject of the email'),
            body: z.string().describe('The body of the email'),
          }),
        )
        .optional()
        .describe('Previous messages in the thread for context'),
    }),
    execute: async (data) => {
      const newBody = await composeEmail({
        ...data,
        username: 'AI Assistant',
        connectionId,
      });
      return { newBody };
    },
  });

// const listEmails = (connectionId: string) =>
//   tool({
//     description: 'List emails in a specific folder',
//     parameters: z.object({
//       folder: z.string().describe('The folder to list emails from').default('inbox'),
//       maxResults: z
//         .number()
//         .optional()
//         .describe('The maximum number of results to return')
//         .default(5),
//       labelIds: z.array(z.string()).optional().describe('The labels to filter emails'),
//       pageToken: z.string().optional().describe('The page token to continue listing emails'),
//     }),
//     execute: async (params) => {
//       return await agent.list(params);
//     },
//   });

const markAsRead = (connectionId: string) =>
  tool({
    description: 'Mark emails as read',
    parameters: z.object({
      threadIds: z.array(z.string()).describe('The IDs of the threads to mark as read'),
    }),
    execute: async ({ threadIds }) => {
      const { stub: agent } = await getZeroAgent(connectionId);
      await Promise.all(
        threadIds.map((threadId) => agent.modifyThreadLabelsInDB(threadId, [], ['UNREAD'])),
      );
      return { threadIds, success: true };
    },
  });

const markAsUnread = (connectionId: string) =>
  tool({
    description: 'Mark emails as unread',
    parameters: z.object({
      threadIds: z.array(z.string()).describe('The IDs of the threads to mark as unread'),
    }),
    execute: async ({ threadIds }) => {
      const { stub: agent } = await getZeroAgent(connectionId);
      await Promise.all(
        threadIds.map((threadId) => agent.modifyThreadLabelsInDB(threadId, ['UNREAD'], [])),
      );
      return { threadIds, success: true };
    },
  });

const modifyLabels = (connectionId: string) =>
  tool({
    description: 'Modify labels on emails',
    parameters: z.object({
      threadIds: z.array(z.string()).describe('The IDs of the threads to modify'),
      options: z.object({
        addLabels: z
          .array(z.string())
          .default([])
          .describe('The labels to add, an array of label names'),
        removeLabels: z
          .array(z.string())
          .default([])
          .describe('The labels to remove, an array of label names'),
      }),
    }),
    execute: async ({ threadIds, options }) => {
      const { stub: agent } = await getZeroAgent(connectionId);
      await Promise.all(
        threadIds.map((threadId) =>
          agent.modifyThreadLabelsInDB(threadId, options.addLabels, options.removeLabels),
        ),
      );
      return { threadIds, options, success: true };
    },
  });

const getUserLabels = (connectionId: string) =>
  tool({
    description: 'Get all user labels',
    parameters: z.object({}),
    execute: async () => {
      const { stub: agent } = await getZeroAgent(connectionId);
      return await agent.getUserLabels();
    },
  });

const sendEmail = (connectionId: string) =>
  tool({
    description: 'Send a new email',
    parameters: z.object({
      to: z.array(
        z.object({
          email: z.string().describe('The email address of the recipient'),
          name: z.string().optional().describe('The name of the recipient'),
        }),
      ),
      subject: z.string().describe('The subject of the email'),
      message: z.string().describe('The body of the email'),
      cc: z
        .array(
          z.object({
            email: z.string().describe('The email address of the recipient'),
            name: z.string().optional().describe('The name of the recipient'),
          }),
        )
        .optional(),
      bcc: z
        .array(
          z.object({
            email: z.string().describe('The email address of the recipient'),
            name: z.string().optional().describe('The name of the recipient'),
          }),
        )
        .optional(),
      threadId: z.string().optional().describe('The ID of the thread to send the email from'),
      // fromEmail: z.string().optional(),
      draftId: z.string().optional().describe('The ID of the draft to send'),
    }),
    execute: async (data) => {
      try {
        const { stub: agent } = await getZeroAgent(connectionId);
        const { draftId, ...mail } = data;

        if (draftId) {
          await agent.sendDraft(draftId, {
            ...mail,
            attachments: [],
            headers: {},
          });
        } else {
          await agent.create({
            ...mail,
            attachments: [],
            headers: {},
          });
        }

        return { success: true };
      } catch (error) {
        console.error('Error sending email:', error);
        throw new Error(
          'Failed to send email: ' + (error instanceof Error ? error.message : String(error)),
        );
      }
    },
  });

const createLabel = (connectionId: string) =>
  tool({
    description: 'Create a new label with custom colors, if it does nto exist already',
    parameters: z.object({
      name: z.string().describe('The name of the label to create'),
      backgroundColor: z
        .string()
        .describe('The background color of the label in hex format')
        .refine((color) => colors.includes(color), {
          message: 'Background color must be one of the predefined colors',
        }),
      textColor: z
        .string()
        .describe('The text color of the label in hex format')
        .refine((color) => colors.includes(color), {
          message: 'Text color must be one of the predefined colors',
        }),
    }),
    execute: async ({ name, backgroundColor, textColor }) => {
      const { stub: agent } = await getZeroAgent(connectionId);
      await agent.createLabel({ name, color: { backgroundColor, textColor } });
      return { name, backgroundColor, textColor, success: true };
    },
  });

const bulkDelete = (connectionId: string) =>
  tool({
    description: 'Move multiple emails to trash by adding the TRASH label',
    parameters: z.object({
      threadIds: z.array(z.string()).describe('Array of email IDs to move to trash'),
    }),
    execute: async ({ threadIds }) => {
      const { stub: agent } = await getZeroAgent(connectionId);
      await Promise.all(
        threadIds.map((threadId) => agent.modifyThreadLabelsInDB(threadId, ['TRASH'], [])),
      );
      return { threadIds, success: true };
    },
  });

const bulkArchive = (connectionId: string) =>
  tool({
    description: 'Move multiple emails to the archive by removing the INBOX label',
    parameters: z.object({
      threadIds: z.array(z.string()).describe('Array of email IDs to move to archive'),
    }),
    execute: async ({ threadIds }) => {
      const { stub: agent } = await getZeroAgent(connectionId);
      await Promise.all(
        threadIds.map((threadId) => agent.modifyThreadLabelsInDB(threadId, [], ['INBOX'])),
      );
      return { threadIds, success: true };
    },
  });

const deleteLabel = (connectionId: string) =>
  tool({
    description: "Delete a label from the user's account",
    parameters: z.object({
      id: z.string().describe('The ID of the label to delete'),
    }),
    execute: async ({ id }) => {
      const { stub: agent } = await getZeroAgent(connectionId);
      await agent.deleteLabel(id);
      return { id, success: true };
    },
  });

const buildGmailSearchQuery = (connectionId: string) =>
  tool({
    description: 'Build a Gmail search query',
    parameters: z.object({
      query: z.string().describe('The search query to build, provided in natural language'),
    }),
    execute: async (params) => {
      console.log('[DEBUG] buildGmailSearchQuery', params);

      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      let sharedAIProfilePrompt = '';
      try {
        const connection = await db.query.connection.findFirst({
          where: (table, { eq }) => eq(table.id, connectionId),
        });
        if (connection?.userId) {
          const zeroDB = await getZeroDB(connection.userId);
          const settings = await zeroDB.findUserSettings();
          sharedAIProfilePrompt = buildAIProfilePrompt(settings?.settings);
        }
      } finally {
        await conn.end();
      }

      const result = await generateText({
        model: resolveModel({ provider: 'auto', modelId: '', ollamaBaseUrl: '', env }),
        system: sharedAIProfilePrompt
          ? `${sharedAIProfilePrompt}\n\n${GmailSearchAssistantSystemPrompt()}`
          : GmailSearchAssistantSystemPrompt(),
        prompt: params.query,
      });
      return {
        content: [
          {
            type: 'text',
            text: result.text,
          },
        ],
      };
    },
  });

const getCurrentDate = () =>
  tool({
    description: 'Get the current date',
    parameters: z.object({}).default({}),
    execute: async () => {
      console.log('[DEBUG] getCurrentDate');

      return {
        content: [
          {
            type: 'text',
            text: getCurrentDateContext(),
          },
        ],
      };
    },
  });

// ── Meeting tools — gives the AI "second brain" access to meeting recaps ──

const listMeetingsTool = (userId: string) =>
  tool({
    description:
      'List the user\'s recent meetings with their status and AI summary. Use this to answer questions like "What meetings did I have this week?" or "Summarize my latest meeting".',
    parameters: z.object({
      limit: z.number().default(10).describe('Max number of meetings to return'),
      status: z.string().optional().describe('Filter by status: scheduled, recording, ready, failed'),
    }),
    execute: async ({ limit, status }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const conditions = [eq(meeting.userId, userId)];
        if (status) conditions.push(eq(meeting.status, status as any));

        const meetings = await db
          .select({
            id: meeting.id,
            title: meeting.title,
            startsAt: meeting.startsAt,
            status: meeting.status,
            aiSummary: meeting.aiSummary,
          })
          .from(meeting)
          .where(and(...conditions))
          .orderBy(desc(meeting.startsAt))
          .limit(limit);

        return meetings.map((m) => ({
          id: m.id,
          title: m.title,
          startsAt: m.startsAt?.toISOString(),
          status: m.status,
          hasSummary: !!m.aiSummary,
          summary: m.aiSummary ? m.aiSummary.slice(0, 500) : null,
        }));
      } finally {
        await conn.end();
      }
    },
  });

const getMeetingSummaryTool = (userId: string) =>
  tool({
    description:
      'Get the full AI summary and action items for a specific meeting. Use after listing meetings to get detailed recap.',
    parameters: z.object({
      meetingId: z.string().describe('The meeting ID to get the summary for'),
    }),
    execute: async ({ meetingId }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const [m] = await db
          .select()
          .from(meeting)
          .where(and(eq(meeting.id, meetingId), eq(meeting.userId, userId)))
          .limit(1);

        if (!m) return { error: 'Meeting not found' };

        return {
          id: m.id,
          title: m.title,
          startsAt: m.startsAt?.toISOString(),
          status: m.status,
          summary: m.aiSummary,
          actionItems: m.actionItems,
          participants: m.participants,
        };
      } finally {
        await conn.end();
      }
    },
  });

const searchMeetingTranscriptTool = (userId: string) =>
  tool({
    description:
      'Search through meeting transcripts for specific content. Use to find what was said about a topic across meetings.',
    parameters: z.object({
      query: z.string().describe('The search term to find in transcripts'),
      meetingId: z.string().optional().describe('Optional: limit search to a specific meeting'),
      limit: z.number().default(20).describe('Max number of transcript segments to return'),
    }),
    execute: async ({ query, meetingId, limit }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        // Get user's meetings first to enforce access control
        const userMeetings = await db
          .select({ id: meeting.id, title: meeting.title })
          .from(meeting)
          .where(
            meetingId
              ? and(eq(meeting.id, meetingId), eq(meeting.userId, userId))
              : eq(meeting.userId, userId),
          );

        if (userMeetings.length === 0) return { segments: [], message: 'No meetings found' };

        const meetingIds = userMeetings.map((m) => m.id);
        const meetingTitleMap = Object.fromEntries(userMeetings.map((m) => [m.id, m.title]));

        // Escape SQL LIKE wildcards in user-supplied search string
        const escapedQuery = query.replace(/[%_\\]/g, '\\$&');

        // Search transcript segments — use LIKE for text search
        const meetingFilter =
          meetingIds.length === 1
            ? eq(meetingTranscript.meetingId, meetingIds[0]!)
            : inArray(meetingTranscript.meetingId, meetingIds);

        const segments = await db
          .select()
          .from(meetingTranscript)
          .where(and(meetingFilter, like(meetingTranscript.text, `%${escapedQuery}%`)))
          .limit(limit);

        return {
          segments: segments.map((s) => ({
            meetingId: s.meetingId,
            meetingTitle: meetingTitleMap[s.meetingId] ?? 'Unknown',
            speaker: s.speakerName,
            text: s.text,
            timestamp: s.startTime,
          })),
        };
      } finally {
        await conn.end();
      }
    },
  });

export const webSearch = () =>
  tool({
    description: 'Search the web for information using Perplexity AI',
    parameters: z.object({
      query: z.string().describe('The query to search the web for'),
    }),
    execute: async ({ query }) => {
      try {
        const response = await generateText({
          model: perplexity('sonar'),
          messages: [
            { role: 'system', content: 'Be precise and concise.' },
            { role: 'system', content: 'Do not include sources in your response.' },
            { role: 'system', content: 'Do not use markdown formatting in your response.' },
            { role: 'user', content: query },
          ],
          maxTokens: 1024,
        });

        return response.text;
      } catch (error) {
        console.error('Error searching the web:', error);
        throw new Error('Failed to search the web');
      }
    },
  });

// ── Task tools — let the assistant manage the user's tasks (mirrors tasks.create) ──

const createTaskTool = (userId: string) =>
  tool({
    description:
      "Create a new task/to-do for the user. Use whenever the user asks to add a task, to-do, or reminder. If a relative due date is mentioned (e.g. 'tomorrow'), call getCurrentDate first and pass an absolute ISO 8601 datetime.",
    parameters: z.object({
      title: z.string().describe('Short title of the task'),
      description: z.string().optional().describe('Optional longer details'),
      priority: z
        .enum(['none', 'low', 'medium', 'high'])
        .optional()
        .describe('Task priority (default none)'),
      dueDate: z
        .string()
        .optional()
        .nullable()
        .describe('Due date as an ISO 8601 datetime string, or null for no due date'),
    }),
    execute: async ({ title, description, priority, dueDate }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const id = crypto.randomUUID();
        const now = new Date();
        const [created] = await db
          .insert(task)
          .values({
            id,
            userId,
            title,
            description: description ?? '',
            status: 'todo',
            priority: priority ?? 'none',
            dueDate: dueDate ? new Date(dueDate) : null,
            folderId: null,
            createdAt: now,
            updatedAt: now,
          })
          .returning();
        return {
          success: true,
          task: {
            id: created?.id,
            title: created?.title,
            priority: created?.priority,
            dueDate: created?.dueDate,
          },
        };
      } finally {
        await conn.end();
      }
    },
  });

const listTasksTool = (userId: string) =>
  tool({
    description:
      "List the user's tasks. Use to answer questions about to-dos, or to find a task's id before completing or updating it.",
    parameters: z.object({
      status: z.enum(['todo', 'doing', 'done']).optional().describe('Filter by status'),
      limit: z.number().default(25).describe('Max tasks to return'),
    }),
    execute: async ({ status, limit }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const conditions = [eq(task.userId, userId)];
        if (status) conditions.push(eq(task.status, status));
        const rows = await db
          .select({
            id: task.id,
            title: task.title,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
          })
          .from(task)
          .where(and(...conditions))
          .orderBy(desc(task.createdAt))
          .limit(limit);
        return { tasks: rows };
      } finally {
        await conn.end();
      }
    },
  });

const completeTaskTool = (userId: string) =>
  tool({
    description:
      "Mark a task as done. Call listTasks first to find the task id if you don't already have it.",
    parameters: z.object({
      taskId: z.string().describe('The id of the task to mark complete'),
    }),
    execute: async ({ taskId }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const [updated] = await db
          .update(task)
          .set({ status: 'done', updatedAt: new Date() })
          .where(and(eq(task.id, taskId), eq(task.userId, userId)))
          .returning();
        if (!updated) return { success: false, error: 'Task not found' };
        return { success: true, task: { id: updated.id, title: updated.title, status: updated.status } };
      } finally {
        await conn.end();
      }
    },
  });

const updateTaskTool = (userId: string) =>
  tool({
    description:
      "Update an existing task's fields (title, description, priority, status, due date). Call listTasks to find the id first.",
    parameters: z.object({
      taskId: z.string().describe('The id of the task to update'),
      title: z.string().optional(),
      description: z.string().optional(),
      priority: z.enum(['none', 'low', 'medium', 'high']).optional(),
      status: z.enum(['todo', 'doing', 'done']).optional(),
      dueDate: z
        .string()
        .optional()
        .nullable()
        .describe('ISO 8601 datetime, or null to clear the due date'),
    }),
    execute: async ({ taskId, title, description, priority, status, dueDate }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const patch: Record<string, any> = { updatedAt: new Date() };
        if (title !== undefined) patch.title = title;
        if (description !== undefined) patch.description = description;
        if (priority !== undefined) patch.priority = priority;
        if (status !== undefined) patch.status = status;
        if (dueDate !== undefined) patch.dueDate = dueDate ? new Date(dueDate) : null;
        const [updated] = await db
          .update(task)
          .set(patch)
          .where(and(eq(task.id, taskId), eq(task.userId, userId)))
          .returning();
        if (!updated) return { success: false, error: 'Task not found' };
        return { success: true, task: { id: updated.id, title: updated.title, status: updated.status } };
      } finally {
        await conn.end();
      }
    },
  });

// ── Calendar tool — create events on the user's primary Google Calendar ──
// Reuses the Google client + fetch helper from the calendar tRPC route.

const createEventTool = (connectionId: string) =>
  tool({
    description:
      "Create an event on the user's primary Google Calendar. For timed events pass ISO 8601 datetimes WITH a timezone offset (e.g. 2026-06-15T09:00:00-04:00); call getCurrentDate first if you need the current date/zone. For all-day events set allDay=true and pass date-only YYYY-MM-DD for start and end (Google treats end as EXCLUSIVE, so a single-day event ends the next day).",
    parameters: z.object({
      summary: z.string().describe('Event title'),
      start: z.string().describe('ISO 8601 datetime (timed) or YYYY-MM-DD (all-day)'),
      end: z.string().describe('ISO 8601 datetime (timed) or YYYY-MM-DD (all-day, exclusive)'),
      allDay: z.boolean().optional().default(false),
      description: z.string().optional(),
      location: z.string().optional(),
    }),
    execute: async ({ summary, start, end, allDay, description, location }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const [c] = await db
          .select({ refreshToken: connection.refreshToken, providerId: connection.providerId })
          .from(connection)
          .where(eq(connection.id, connectionId))
          .limit(1);
        if (!c || c.providerId !== 'google') {
          return { success: false, error: 'No Google calendar is connected' };
        }
        if (!c.refreshToken) {
          return { success: false, error: 'Calendar connection is missing a refresh token' };
        }
        const auth = buildAuthClient(c.refreshToken);
        const body = allDay
          ? { summary, description, location, start: { date: start }, end: { date: end } }
          : { summary, description, location, start: { dateTime: start }, end: { dateTime: end } };
        const created = await calendarFetchJSON<{ id: string }>(
          auth,
          `/calendars/${encodeURIComponent('primary')}/events`,
          { method: 'POST', body },
        );
        return { success: true, event: { id: created?.id, summary } };
      } finally {
        await conn.end();
      }
    },
  });

// ── Second-brain context tools — read-only access to the assistant's derived
// memory (person/workstream/open-loop tables populated by the briefing sync in
// trpc/routes/assistant.ts). Lets chat answer "what did I promise Anna?" or
// "where is project X?" without a live inbox search. Summaries are LLM-derived
// from the user's own emails — same trust level as thread bodies.

/** Strip SQL LIKE wildcards from user-supplied search fragments. */
const sanitizeLike = (q: string) => q.replace(/[%_]/g, ' ').trim();

const getPersonContextTool = (userId: string) =>
  tool({
    description:
      "Get the user's relationship memory for a contact: relationship summary, promises the user made to them, their unresolved asks, and recent thread ids. Use FIRST for questions about a person ('what did I promise Anna?', 'where are we with John?') before searching the inbox. Match by email or name.",
    parameters: z.object({
      person: z.string().describe('Email address or name (fragment ok) of the contact'),
    }),
    execute: async ({ person }) => {
      const q = sanitizeLike(person);
      if (!q) return { people: [] };
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const rows = await db
          .select()
          .from(assistantPersonMemory)
          .where(
            and(
              eq(assistantPersonMemory.userId, userId),
              or(
                ilike(assistantPersonMemory.email, `%${q}%`),
                ilike(assistantPersonMemory.displayName, `%${q}%`),
              ),
            ),
          )
          .orderBy(desc(assistantPersonMemory.lastInteractionAt))
          .limit(3);
        return {
          people: rows.map((r) => ({
            email: r.email,
            displayName: r.displayName,
            company: r.company,
            relationshipSummary: r.relationshipSummary,
            promisesIMade: r.promises.slice(0, 8),
            theirUnresolvedAsks: r.unresolvedAsks.slice(0, 8),
            lastInteractionAt: r.lastInteractionAt,
            recentThreadIds: r.recentThreadIds.slice(0, 5),
          })),
        };
      } finally {
        await conn.end();
      }
    },
  });

const getWorkstreamContextTool = (userId: string) =>
  tool({
    description:
      "Get the user's project/topic memory ('workstreams'): summary, pending decisions, risks, people involved, next milestone. Use for questions about a project or topic ('where is the redesign?', 'what's blocked?'). Omit query to list active workstreams.",
    parameters: z.object({
      query: z
        .string()
        .optional()
        .describe('Project/topic name fragment to match; omit to list active workstreams'),
    }),
    execute: async ({ query }) => {
      const q = query ? sanitizeLike(query) : '';
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const rows = await db
          .select()
          .from(assistantWorkstreamMemory)
          .where(
            and(
              eq(assistantWorkstreamMemory.userId, userId),
              q
                ? or(
                    ilike(assistantWorkstreamMemory.key, `%${q}%`),
                    ilike(assistantWorkstreamMemory.title, `%${q}%`),
                    ilike(assistantWorkstreamMemory.summary, `%${q}%`),
                  )
                : eq(assistantWorkstreamMemory.status, 'active'),
            ),
          )
          .orderBy(desc(assistantWorkstreamMemory.updatedAt))
          .limit(q ? 5 : 10);
        return {
          workstreams: rows.map((r) => ({
            key: r.key,
            title: r.title,
            status: r.status,
            summary: r.summary,
            pendingDecisions: r.pendingDecisions.slice(0, 8),
            risks: r.risks.slice(0, 8),
            relatedPeople: r.relatedPeople.slice(0, 10),
            nextMilestone: r.nextMilestone,
            relatedThreadIds: r.relatedThreadIds.slice(0, 5),
            updatedAt: r.updatedAt,
          })),
        };
      } finally {
        await conn.end();
      }
    },
  });

const getOpenLoopsTool = (userId: string) =>
  tool({
    description:
      "List the user's open loops — commitments and threads needing attention (needs_reply, waiting_on_other, deadline_risk, meeting_follow_up, decision_needed). Use for 'what needs my attention?', 'what am I waiting on?', 'anything I dropped?'. Filter by queue or person when asked about a specific slice.",
    parameters: z.object({
      queue: z
        .enum(['needs_you', 'waiting_on', 'scheduling', 'drafts_ready', 'likely_dropped'])
        .optional()
        .describe('Filter to one queue'),
      personEmail: z.string().optional().describe('Filter to loops involving this contact email'),
      limit: z.number().min(1).max(30).default(15).describe('Max loops to return'),
    }),
    execute: async ({ queue, personEmail, limit }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const conditions = [
          eq(assistantOpenLoop.userId, userId),
          eq(assistantOpenLoop.status, 'open'),
        ];
        if (queue) conditions.push(eq(assistantOpenLoop.queue, queue));
        if (personEmail) {
          const p = sanitizeLike(personEmail);
          if (p) conditions.push(ilike(assistantOpenLoop.personEmail, `%${p}%`));
        }
        const rows = await db
          .select({
            type: assistantOpenLoop.type,
            queue: assistantOpenLoop.queue,
            title: assistantOpenLoop.title,
            summary: assistantOpenLoop.summary,
            actionLine: assistantOpenLoop.actionLine,
            personEmail: assistantOpenLoop.personEmail,
            workstreamKey: assistantOpenLoop.workstreamKey,
            confidencePct: assistantOpenLoop.confidencePct,
            sourceThreadId: assistantOpenLoop.sourceThreadId,
            updatedAt: assistantOpenLoop.updatedAt,
          })
          .from(assistantOpenLoop)
          .where(and(...conditions))
          .orderBy(desc(assistantOpenLoop.updatedAt))
          .limit(limit);
        return { openLoops: rows };
      } finally {
        await conn.end();
      }
    },
  });

export const tools = async (connectionId: string, ragEffect: boolean = false) => {
  // Resolve userId from connectionId for meeting tools
  let userId: string | null = null;
  try {
    const { db: lookupDb, conn: lookupConn } = createDb(env.HYPERDRIVE.connectionString);
    try {
      const [connRow] = await lookupDb
        .select({ userId: connection.userId })
        .from(connection)
        .where(eq(connection.id, connectionId))
        .limit(1);
      userId = connRow?.userId ?? null;
    } finally {
      await lookupConn.end();
    }
  } catch {
    // Best effort — meeting tools won't be available if lookup fails
  }

  // Build user-scoped tools dynamically — only include when userId is resolved
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const meetingTools: Record<string, any> = {};
  if (userId) {
    meetingTools[Tools.ListMeetings] = listMeetingsTool(userId);
    meetingTools[Tools.GetMeetingSummary] = getMeetingSummaryTool(userId);
    meetingTools[Tools.SearchMeetingTranscript] = searchMeetingTranscriptTool(userId);

    // Second-brain memory reads (person/workstream/open-loop) — read-only,
    // always available like other read tools.
    meetingTools[Tools.GetPersonContext] = getPersonContextTool(userId);
    meetingTools[Tools.GetWorkstreamContext] = getWorkstreamContextTool(userId);
    meetingTools[Tools.GetOpenLoops] = getOpenLoopsTool(userId);

    // Task tools. Reads are always available; writes respect the user's
    // `aiCanWriteTasks` permission (Settings → AI → Permissions), which was
    // previously saved but never enforced server-side.
    meetingTools[Tools.ListTasks] = listTasksTool(userId);
    let aiCanWriteTasks = true;
    let aiCanWriteCalendar = true;
    try {
      const zeroDB = await getZeroDB(userId);
      const s = await zeroDB.findUserSettings();
      aiCanWriteTasks = s?.settings?.aiCanWriteTasks ?? true;
      aiCanWriteCalendar = s?.settings?.aiCanWriteCalendar ?? true;
    } catch {
      // best effort — default to allowed
    }
    if (aiCanWriteTasks) {
      meetingTools[Tools.CreateTask] = createTaskTool(userId);
      meetingTools[Tools.UpdateTask] = updateTaskTool(userId);
      meetingTools[Tools.CompleteTask] = completeTaskTool(userId);
    }
    if (aiCanWriteCalendar) {
      meetingTools[Tools.CreateEvent] = createEventTool(connectionId);
    }
  }

  const _tools = {
    [Tools.GetThread]: getEmail(),
    [Tools.GetThreadSummary]: getThreadSummary(connectionId),
    [Tools.ComposeEmail]: composeEmailTool(connectionId),
    [Tools.MarkThreadsRead]: markAsRead(connectionId),
    [Tools.MarkThreadsUnread]: markAsUnread(connectionId),
    [Tools.ModifyLabels]: modifyLabels(connectionId),
    [Tools.GetUserLabels]: getUserLabels(connectionId),
    [Tools.SendEmail]: sendEmail(connectionId),
    [Tools.CreateLabel]: createLabel(connectionId),
    [Tools.BulkDelete]: bulkDelete(connectionId),
    [Tools.BulkArchive]: bulkArchive(connectionId),
    [Tools.DeleteLabel]: deleteLabel(connectionId),
    [Tools.BuildGmailSearchQuery]: buildGmailSearchQuery(connectionId),
    [Tools.GetCurrentDate]: getCurrentDate(),
    [Tools.WebSearch]: webSearch(),
    ...meetingTools,
    [Tools.InboxRag]: tool({
      description:
        'Search the inbox for emails using natural language. Returns only an array of threadIds.',
      parameters: z.object({
        query: z.string().describe('The query to search the inbox for'),
        maxResults: z.number().describe('The maximum number of results to return').default(10),
        folder: z.string().describe('The folder to search the inbox for').default('inbox'),
      }),
      execute: async ({ query, maxResults, folder }) => {
        const { stub: agent } = await getZeroAgent(connectionId);
        const res = await agent.searchThreads({ query, maxResults, folder });
        return res.threadIds;
      },
    }),
  };
  if (ragEffect) return _tools;
  return {
    ..._tools,
    [Tools.InboxRag]: tool({
      description:
        'Search the inbox for emails using natural language. Returns only an array of threadIds.',
      parameters: z.object({
        query: z.string().describe('The query to search the inbox for'),
      }),
    }),
  };
};
