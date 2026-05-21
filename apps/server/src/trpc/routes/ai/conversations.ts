import { aiConversation, taskFolder } from '../../../db/schema';
import { privateProcedure } from '../../trpc';
import { createDb } from '../../../db';
import { eq, and, desc } from 'drizzle-orm';
import { env } from '../../../env';
import { z } from 'zod';
import { TRPCError } from '@trpc/server';
import { addMemories, invalidateMemoryCache, preloadMemories } from '../../../lib/mem0';

const getDb = () => createDb(env.HYPERDRIVE.connectionString);

const savedMessageSchema = z.object({
  role: z.string(),
  content: z.string(),
  mentions: z
    .array(
      z.object({
        type: z.string(),
        id: z.string(),
        label: z.string(),
      }),
    )
    .optional()
    .default([]),
});

// ─── AI Conversation Procedures ─────────────────────────────────────

/** List all saved conversations (newest first, max 50) */
export const listConversations = privateProcedure.query(async ({ ctx }) => {
  const { db, conn } = getDb();
  try {
    const conversations = await db
      .select({
        id: aiConversation.id,
        folderId: aiConversation.folderId,
        title: aiConversation.title,
        createdAt: aiConversation.createdAt,
        updatedAt: aiConversation.updatedAt,
      })
      .from(aiConversation)
      .where(eq(aiConversation.userId, ctx.sessionUser.id))
      .orderBy(desc(aiConversation.updatedAt))
      .limit(50);
    return { conversations };
  } finally {
    await conn.end();
  }
});

/** Get a single conversation with full messages */
export const getConversation = privateProcedure
  .input(z.object({ id: z.string() }))
  .query(async ({ ctx, input }) => {
    const { db, conn } = getDb();
    try {
      const [convo] = await db
        .select()
        .from(aiConversation)
        .where(and(eq(aiConversation.id, input.id), eq(aiConversation.userId, ctx.sessionUser.id)))
        .limit(1);
      return convo ?? null;
    } finally {
      await conn.end();
    }
  });

/** Save or update a conversation */
export const saveConversation = privateProcedure
  .input(
    z.object({
      id: z.string(),
      title: z.string(),
      messages: z.array(savedMessageSchema),
      folderId: z.string().nullable().optional(),
      createdAt: z.string().datetime().optional(),
    }),
  )
  .mutation(async ({ ctx, input }) => {
    const { db, conn } = getDb();
    try {
      const now = new Date();
      if (input.folderId != null) {
        const [folder] = await db
          .select({ id: taskFolder.id })
          .from(taskFolder)
          .where(and(eq(taskFolder.id, input.folderId), eq(taskFolder.userId, ctx.sessionUser.id)))
          .limit(1);

        if (!folder) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'Folder not found.',
          });
        }
      }

      const [existingConversation] = await db
        .select({
          userId: aiConversation.userId,
        })
        .from(aiConversation)
        .where(eq(aiConversation.id, input.id))
        .limit(1);

      if (existingConversation && existingConversation.userId !== ctx.sessionUser.id) {
        throw new TRPCError({
          code: 'FORBIDDEN',
          message: 'Conversation ID belongs to another user.',
        });
      }

      if (existingConversation) {
        const updateData: Record<string, unknown> = {
          title: input.title,
          messages: input.messages,
          updatedAt: now,
        };
        if (input.folderId !== undefined) {
          updateData.folderId = input.folderId ?? null;
        }

        const [updated] = await db
          .update(aiConversation)
          .set(updateData)
          .where(and(eq(aiConversation.id, input.id), eq(aiConversation.userId, ctx.sessionUser.id)))
          .returning({ id: aiConversation.id });

        if (!updated) {
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to update conversation.',
          });
        }
      } else {
        await db.insert(aiConversation).values({
          id: input.id,
          userId: ctx.sessionUser.id,
          folderId: input.folderId ?? null,
          title: input.title,
          messages: input.messages,
          createdAt: input.createdAt ? new Date(input.createdAt) : now,
          updatedAt: now,
        });
      }

      // Mem0 ingestion. The text-chat route (/api/ai/chat) writes memories
      // inline as the stream finishes; voice sessions never go through that
      // route, so the only place voice transcripts can land in Mem0 is here.
      // Without this, "remember X" said over voice would never persist into
      // long-term memory and the next voice session's system prompt would
      // be empty.
      //
      // Pull the most recent user/assistant pair off the saved transcript
      // and fire-and-forget against Mem0. Failures are swallowed by the
      // mem0 client so a Mem0 outage never breaks conversation save.
      const mem0Key = env.MEM0_API_KEY;
      if (mem0Key) {
        const lastUser = [...input.messages].reverse().find((m) => m.role === 'user');
        const lastAssistant = [...input.messages].reverse().find((m) => m.role === 'assistant');
        const userContent = lastUser?.content?.trim() ?? '';
        const assistantContent = lastAssistant?.content?.trim() ?? '';
        // Skip ingestion if either side is empty or trivially short — small
        // utterances ("hi", "ok") just create memory noise.
        if (userContent.length > 0 && assistantContent.length > 10) {
          const userId = ctx.sessionUser.id;
          // Don't await: keep saveConversation latency unaffected. The Worker
          // runtime keeps the promise alive long enough for the POST to land.
          void addMemories(mem0Key, userId, [
            { role: 'user', content: userContent },
            { role: 'assistant', content: assistantContent },
          ])
            .then(() => invalidateMemoryCache(userId, env.prompts_storage))
            .then(() => preloadMemories(userId, env.prompts_storage, mem0Key))
            .catch((error) => {
              console.warn('[saveConversation] Mem0 ingestion failed:', error);
            });
        }
      }

      return { success: true };
    } finally {
      await conn.end();
    }
  });

/** Delete a conversation */
export const deleteConversation = privateProcedure
  .input(z.object({ id: z.string() }))
  .mutation(async ({ ctx, input }) => {
    const { db, conn } = getDb();
    try {
      await db
        .delete(aiConversation)
        .where(and(eq(aiConversation.id, input.id), eq(aiConversation.userId, ctx.sessionUser.id)));
      return { success: true };
    } finally {
      await conn.end();
    }
  });
