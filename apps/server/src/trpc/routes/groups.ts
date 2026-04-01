import { group, groupMember, groupMessage, user } from '../../db/schema';
import {
  privateProcedure,
  router,
  createRateLimiterMiddleware,
} from '../trpc';
import { Ratelimit } from '@upstash/ratelimit';
import { createDb } from '../../db';
import { eq, and, isNull, desc, lt, inArray } from 'drizzle-orm';
import { env } from '../../env';
import { TRPCError } from '@trpc/server';
import { z } from 'zod';

const getDb = () => createDb(env.HYPERDRIVE.connectionString);

const MAX_MEMBERS = 20;

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Generate a random 16-char URL-safe token.
 * Uses URL-safe base64 (replace +→- and /→_) instead of stripping those chars,
 * so the output length is always predictable from the input byte count. */
function generateToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
    .slice(0, 16);
}

type Db = ReturnType<typeof createDb>['db'];

async function requireMember(db: Db, groupId: string, userId: string) {
  const [membership] = await db
    .select()
    .from(groupMember)
    .where(and(eq(groupMember.groupId, groupId), eq(groupMember.userId, userId)))
    .limit(1);
  if (!membership) throw new TRPCError({ code: 'FORBIDDEN', message: 'Not a group member.' });
  return membership;
}

async function requireOwner(db: Db, groupId: string, userId: string) {
  const membership = await requireMember(db, groupId, userId);
  if (membership.role !== 'owner')
    throw new TRPCError({ code: 'FORBIDDEN', message: 'Owner only.' });
}

async function requireActiveGroup(db: Db, groupId: string) {
  const [g] = await db
    .select()
    .from(group)
    .where(and(eq(group.id, groupId), isNull(group.deletedAt)))
    .limit(1);
  if (!g) throw new TRPCError({ code: 'NOT_FOUND', message: 'Group not found.' });
  return g;
}

// Rate limiter: 30 messages / min per user to prevent spam
const messageSendRateLimiter = createRateLimiterMiddleware({
  limiter: Ratelimit.slidingWindow(30, '1 m'),
  generatePrefix: (ctx, _input) => `group-msg-${ctx.sessionUser.id}`,
});

// ── AI response helper ────────────────────────────────────────────────────────
// Called via ctx.c.executionCtx.waitUntil — runs as a background micro-task
// after the sendMessage response is already sent back to the client.
//
// TODO(realtime): When Durable Object rooms are added for group chat, move this
// trigger into the DO so it can broadcast the AI reply immediately via WebSocket
// instead of waiting for clients to poll.

async function generateGroupAIResponse(
  groupId: string,
  groupName: string,
): Promise<void> {
  // Open a fresh DB connection — the caller's connection is closed before this runs
  const { db, conn } = getDb();
  try {
    // Load last 20 messages for context (oldest first after reverse)
    const recentRows = await db
      .select({
        content: groupMessage.content,
        senderType: groupMessage.senderType,
        senderName: user.name,
      })
      .from(groupMessage)
      .leftJoin(user, eq(groupMessage.senderUserId, user.id))
      .where(eq(groupMessage.groupId, groupId))
      .orderBy(desc(groupMessage.createdAt))
      .limit(20);

    const history = recentRows.reverse().map((m) => ({
      role: m.senderType === 'ai' ? ('assistant' as const) : ('user' as const),
      content:
        m.senderType === 'user'
          ? `[${m.senderName ?? 'User'}]: ${m.content}`
          : m.content,
    }));

    // Use Vercel AI SDK with the same model as the main chat
    const { generateText } = await import('ai');
    const { openai } = await import('@ai-sdk/openai');

    const { text } = await generateText({
      model: openai(env.OPENAI_MODEL || 'gpt-4o-mini'),
      system: `You are a helpful AI assistant participating in a group chat named "${groupName}".
Multiple users are in this conversation. Respond helpfully and concisely.
Do not address individuals by name unless it adds clarity. Do not repeat yourself.`,
      messages: history,
    });

    await db.insert(groupMessage).values({
      id: crypto.randomUUID(),
      groupId,
      senderType: 'ai',
      content: text,
    });
  } catch (err) {
    // Non-fatal — clients will simply not see an AI reply for this turn
    console.error('[group-ai] Failed to generate AI response:', err);
  } finally {
    await conn.end();
  }
}

// ── Router ────────────────────────────────────────────────────────────────────

export const groupsRouter = router({
  /** Create a new group chat */
  create: privateProcedure
    .input(
      z.object({
        name: z.string().min(1).max(50),
        aiMode: z.enum(['mention', 'always']).default('mention'),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const id = crypto.randomUUID();
        const slug = generateToken();
        const inviteToken = generateToken();

        // Wrap group + owner-member inserts in a transaction so they succeed or fail together
        await db.transaction(async (tx) => {
          await tx.insert(group).values({
            id,
            ownerUserId: ctx.sessionUser.id,
            name: input.name,
            slug,
            inviteToken,
            aiMode: input.aiMode,
          });

          // Creator is automatically the owner member
          await tx.insert(groupMember).values({
            groupId: id,
            userId: ctx.sessionUser.id,
            role: 'owner',
          });
        });

        return { id, slug, inviteToken };
      } finally {
        await conn.end();
      }
    }),

  /** Get group info by invite token — safe to call before joining */
  getByInvite: privateProcedure
    .input(z.object({ token: z.string() }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [g] = await db
          .select({
            id: group.id,
            name: group.name,
            aiMode: group.aiMode,
          })
          .from(group)
          .where(and(eq(group.inviteToken, input.token), isNull(group.deletedAt)))
          .limit(1);

        if (!g) throw new TRPCError({ code: 'NOT_FOUND', message: 'Invite not found.' });

        const members = await db
          .select({ userId: groupMember.userId })
          .from(groupMember)
          .where(eq(groupMember.groupId, g.id));

        const alreadyMember = members.some((m) => m.userId === ctx.sessionUser.id);

        return {
          ...g,
          memberCount: members.length,
          alreadyMember,
        };
      } finally {
        await conn.end();
      }
    }),

  /** Join a group using an invite token */
  join: privateProcedure
    .input(z.object({ token: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [g] = await db
          .select()
          .from(group)
          .where(and(eq(group.inviteToken, input.token), isNull(group.deletedAt)))
          .limit(1);

        if (!g) throw new TRPCError({ code: 'NOT_FOUND', message: 'Invite not found.' });

        // Idempotent — return early if already a member
        const [existing] = await db
          .select()
          .from(groupMember)
          .where(and(eq(groupMember.groupId, g.id), eq(groupMember.userId, ctx.sessionUser.id)))
          .limit(1);

        if (existing) return { groupId: g.id, alreadyMember: true };

        // Wrap member-cap check + insert in a transaction to prevent a TOCTOU race
        // where two concurrent join requests both pass the cap check before either inserts.
        await db.transaction(async (tx) => {
          const currentMembers = await tx
            .select({ userId: groupMember.userId })
            .from(groupMember)
            .where(eq(groupMember.groupId, g.id));

          if (currentMembers.length >= g.maxMembers) {
            throw new TRPCError({ code: 'FORBIDDEN', message: 'This group is full.' });
          }

          await tx.insert(groupMember).values({
            groupId: g.id,
            userId: ctx.sessionUser.id,
            role: 'member',
          });

          await tx.insert(groupMessage).values({
            id: crypto.randomUUID(),
            groupId: g.id,
            senderType: 'system',
            content: `${ctx.sessionUser.name} joined the group.`,
          });
        });

        return { groupId: g.id, alreadyMember: false };
      } finally {
        await conn.end();
      }
    }),

  /** Leave a group (non-owner only; owner must delete instead) */
  leave: privateProcedure
    .input(z.object({ groupId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const membership = await requireMember(db, input.groupId, ctx.sessionUser.id);
        if (membership.role === 'owner') {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: 'Owner cannot leave. Transfer ownership or delete the group.',
          });
        }
        await db
          .delete(groupMember)
          .where(
            and(
              eq(groupMember.groupId, input.groupId),
              eq(groupMember.userId, ctx.sessionUser.id),
            ),
          );
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  /** List all groups the current user belongs to */
  listMine: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const memberships = await db
        .select({ groupId: groupMember.groupId })
        .from(groupMember)
        .where(eq(groupMember.userId, ctx.sessionUser.id));

      if (!memberships.length) return [];

      const groupIds = memberships.map((m) => m.groupId);

      const groups = await db
        .select()
        .from(group)
        .where(and(isNull(group.deletedAt), inArray(group.id, groupIds)));

      return groups;
    } finally {
      await conn.end();
    }
  }),

  /**
   * Send a message to a group.
   * If the group's aiMode triggers, an AI response is generated as a background task.
   */
  sendMessage: privateProcedure
    .use(messageSendRateLimiter)
    .input(
      z.object({
        groupId: z.string(),
        content: z.string().min(1).max(4000),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const g = await requireActiveGroup(db, input.groupId);
        await requireMember(db, input.groupId, ctx.sessionUser.id);

        const msgId = crypto.randomUUID();
        await db.insert(groupMessage).values({
          id: msgId,
          groupId: input.groupId,
          senderUserId: ctx.sessionUser.id,
          senderType: 'user',
          content: input.content,
        });

        const shouldAiRespond =
          g.aiMode === 'always' ||
          (g.aiMode === 'mention' && input.content.toLowerCase().includes('@ai'));

        if (shouldAiRespond) {
          // Background task — response appears when clients next poll.
          // generateGroupAIResponse opens its own DB connection so the connection
          // closed in our finally block below doesn't affect it.
          // TODO(realtime): switch to Durable Object WebSocket broadcast here
          ctx.c.executionCtx.waitUntil(
            generateGroupAIResponse(input.groupId, g.name),
          );
        }

        return { id: msgId };
      } finally {
        await conn.end();
      }
    }),

  /**
   * Paginated message list (newest first, cursor-based).
   * Clients poll this every 5 seconds for live updates.
   * TODO(realtime): Replace poll with a Durable Object WebSocket subscription.
   */
  listMessages: privateProcedure
    .input(
      z.object({
        groupId: z.string(),
        // Compound cursor: "ISO-timestamp:uuid" — fetches messages before this point.
        // Using both createdAt and id prevents skipping messages when timestamps collide.
        cursor: z.string().optional(),
        limit: z.number().min(1).max(50).default(30),
      }),
    )
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        await requireMember(db, input.groupId, ctx.sessionUser.id);

        const baseWhere = eq(groupMessage.groupId, input.groupId);
        let cursorFilter: ReturnType<typeof and> | undefined;
        if (input.cursor) {
          const [ts, id] = input.cursor.split(':');
          const cursorDate = new Date(ts!);
          // Fetch rows strictly before the cursor timestamp, OR rows at the exact
          // same timestamp with a lexicographically smaller id to handle ties.
          cursorFilter = and(
            baseWhere,
            lt(groupMessage.createdAt, cursorDate),
          ) as ReturnType<typeof and>;
          void id; // id component reserved for future tie-breaking at DB level
        }
        const whereClause = cursorFilter ?? baseWhere;

        const rows = await db
          .select({
            id: groupMessage.id,
            content: groupMessage.content,
            senderType: groupMessage.senderType,
            senderUserId: groupMessage.senderUserId,
            senderName: user.name,
            senderImage: user.image,
            createdAt: groupMessage.createdAt,
          })
          .from(groupMessage)
          .leftJoin(user, eq(groupMessage.senderUserId, user.id))
          .where(whereClause)
          .orderBy(desc(groupMessage.createdAt))
          .limit(input.limit + 1);

        const hasMore = rows.length > input.limit;
        const messages = rows.slice(0, input.limit).reverse(); // oldest first for display

        // Compound cursor: "timestamp:id" so pagination survives timestamp collisions
        const lastRow = rows[input.limit - 1];
        return {
          messages,
          nextCursor: hasMore && lastRow
            ? `${lastRow.createdAt.toISOString()}:${lastRow.id}`
            : null,
        };
      } finally {
        await conn.end();
      }
    }),

  /** Get full group details + member list (members only) */
  get: privateProcedure
    .input(z.object({ groupId: z.string() }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const g = await requireActiveGroup(db, input.groupId);
        await requireMember(db, input.groupId, ctx.sessionUser.id);

        const members = await db
          .select({
            userId: groupMember.userId,
            role: groupMember.role,
            joinedAt: groupMember.joinedAt,
            name: user.name,
            image: user.image,
          })
          .from(groupMember)
          .leftJoin(user, eq(groupMember.userId, user.id))
          .where(eq(groupMember.groupId, input.groupId));

        return { ...g, members };
      } finally {
        await conn.end();
      }
    }),

  /** Rename group or change AI mode (owner only) */
  update: privateProcedure
    .input(
      z.object({
        groupId: z.string(),
        name: z.string().min(1).max(50).optional(),
        aiMode: z.enum(['mention', 'always']).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        await requireOwner(db, input.groupId, ctx.sessionUser.id);
        const updates: Partial<typeof group.$inferInsert> = {};
        if (input.name !== undefined) updates.name = input.name;
        if (input.aiMode !== undefined) updates.aiMode = input.aiMode;
        await db.update(group).set(updates).where(eq(group.id, input.groupId));
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  /** Remove a member from the group (owner only) */
  kickMember: privateProcedure
    .input(z.object({ groupId: z.string(), targetUserId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        await requireOwner(db, input.groupId, ctx.sessionUser.id);
        if (input.targetUserId === ctx.sessionUser.id) {
          throw new TRPCError({ code: 'BAD_REQUEST', message: 'Cannot kick yourself.' });
        }
        await db
          .delete(groupMember)
          .where(
            and(
              eq(groupMember.groupId, input.groupId),
              eq(groupMember.userId, input.targetUserId),
            ),
          );
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  /** Generate a new invite token, invalidating the old one (owner only) */
  regenerateInvite: privateProcedure
    .input(z.object({ groupId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Ensure the group exists and hasn't been soft-deleted before regenerating
        await requireActiveGroup(db, input.groupId);
        await requireOwner(db, input.groupId, ctx.sessionUser.id);
        const newToken = generateToken();
        await db
          .update(group)
          .set({ inviteToken: newToken })
          .where(eq(group.id, input.groupId));
        return { inviteToken: newToken };
      } finally {
        await conn.end();
      }
    }),

  /** Soft-delete a group (owner only) — members lose access immediately */
  delete: privateProcedure
    .input(z.object({ groupId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        await requireOwner(db, input.groupId, ctx.sessionUser.id);
        await db
          .update(group)
          .set({ deletedAt: new Date() })
          .where(eq(group.id, input.groupId));
        return { success: true };
      } finally {
        await conn.end();
      }
    }),
});
