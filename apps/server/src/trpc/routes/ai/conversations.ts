import { aiConversation } from '../../../db/schema';
import { privateProcedure } from '../../trpc';
import { createDb } from '../../../db';
import { eq, and, desc } from 'drizzle-orm';
import { env } from '../../../env';
import { z } from 'zod';
import { TRPCError } from '@trpc/server';

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
      createdAt: z.string().datetime().optional(),
    }),
  )
  .mutation(async ({ ctx, input }) => {
    const { db, conn } = getDb();
    try {
      const now = new Date();
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
        const [updated] = await db
          .update(aiConversation)
          .set({
            title: input.title,
            messages: input.messages,
            updatedAt: now,
          })
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
          title: input.title,
          messages: input.messages,
          createdAt: input.createdAt ? new Date(input.createdAt) : now,
          updatedAt: now,
        });
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
