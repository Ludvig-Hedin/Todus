import { TRPCError } from '@trpc/server';
import { docWorkspace, doc } from '../../db/schema';
import { privateProcedure, router } from '../trpc';
import { createDb } from '../../db';
import { env } from '../../env';
import { eq, and, asc, or, ilike } from 'drizzle-orm';
import { z } from 'zod';

// Helper to get a direct Drizzle DB connection (same pattern as tasks.ts)
const getDb = () => createDb(env.HYPERDRIVE.connectionString);

// ─── Workspaces Router ─────────────────────────────────────────────────────────

export const docWorkspacesRouter = router({
  list: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const workspaces = await db
        .select()
        .from(docWorkspace)
        .where(eq(docWorkspace.userId, ctx.sessionUser.id))
        .orderBy(asc(docWorkspace.name));

      return { workspaces };
    } finally {
      await conn.end();
    }
  }),

  create: privateProcedure
    .input(
      z.object({
        name: z.string().min(1),
        emoji: z.string().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const id = crypto.randomUUID();
        const now = new Date();

        const [created] = await db
          .insert(docWorkspace)
          .values({
            id,
            userId: ctx.sessionUser.id,
            name: input.name,
            emoji: input.emoji ?? null,
            createdAt: now,
            updatedAt: now,
          })
          .returning();

        return { workspace: created };
      } finally {
        await conn.end();
      }
    }),

  update: privateProcedure
    .input(
      z.object({
        id: z.string(),
        name: z.string().optional(),
        emoji: z.string().nullable().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Build partial update object — only include fields that were provided
        const updateData: Record<string, unknown> = { updatedAt: new Date() };
        if (input.name !== undefined) updateData.name = input.name;
        if (input.emoji !== undefined) updateData.emoji = input.emoji;

        const [updated] = await db
          .update(docWorkspace)
          .set(updateData)
          // Scope to userId to prevent users from modifying other users' workspaces
          .where(and(eq(docWorkspace.id, input.id), eq(docWorkspace.userId, ctx.sessionUser.id)))
          .returning();

        if (!updated) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Workspace not found' });
        }

        return { workspace: updated };
      } finally {
        await conn.end();
      }
    }),

  delete: privateProcedure
    .input(z.object({ id: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Cascade deletion of docs is handled by the DB foreign key constraint
        await db
          .delete(docWorkspace)
          .where(and(eq(docWorkspace.id, input.id), eq(docWorkspace.userId, ctx.sessionUser.id)));

        return { success: true };
      } finally {
        await conn.end();
      }
    }),
});

// ─── Docs Router ───────────────────────────────────────────────────────────────

export const docsRouter = router({
  workspaces: docWorkspacesRouter,

  list: privateProcedure
    .input(
      z.object({
        workspaceId: z.string().optional(),
        parentId: z.string().optional(),
      }).optional().default({}),
    )
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const conditions = [eq(doc.userId, ctx.sessionUser.id)];

        if (input.workspaceId !== undefined) {
          conditions.push(eq(doc.workspaceId, input.workspaceId));
        }
        if (input.parentId !== undefined) {
          conditions.push(eq(doc.parentId, input.parentId));
        }

        const docs = await db
          .select()
          .from(doc)
          .where(and(...conditions))
          // Primary sort by explicit order, secondary by creation time
          .orderBy(asc(doc.order), asc(doc.createdAt));

        return { docs };
      } finally {
        await conn.end();
      }
    }),

  get: privateProcedure
    .input(z.object({ id: z.string() }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [found] = await db
          .select()
          .from(doc)
          // Scope to userId to prevent users from reading other users' docs
          .where(and(eq(doc.id, input.id), eq(doc.userId, ctx.sessionUser.id)));

        if (!found) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Doc not found' });
        }

        return { doc: found };
      } finally {
        await conn.end();
      }
    }),

  create: privateProcedure
    .input(
      z.object({
        workspaceId: z.string().optional(),
        parentId: z.string().optional(),
        title: z.string().optional(),
        emoji: z.string().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const userId = ctx.sessionUser.id;
      const { db, conn } = getDb();
      try {
        // Verify the workspace belongs to this user before creating a doc in it
        if (input.workspaceId) {
          const [ws] = await db
            .select({ id: docWorkspace.id })
            .from(docWorkspace)
            .where(and(eq(docWorkspace.id, input.workspaceId), eq(docWorkspace.userId, userId)));
          if (!ws) throw new TRPCError({ code: 'FORBIDDEN', message: 'Workspace not found' });
        }

        const id = crypto.randomUUID();
        const now = new Date();

        const [created] = await db
          .insert(doc)
          .values({
            id,
            userId,
            workspaceId: input.workspaceId ?? null,
            parentId: input.parentId ?? null,
            title: input.title ?? 'Untitled',
            emoji: input.emoji ?? null,
            content: null,
            contentText: null,
            order: 0,
            createdAt: now,
            updatedAt: now,
          })
          .returning();

        return { doc: created };
      } finally {
        await conn.end();
      }
    }),

  update: privateProcedure
    .input(
      z.object({
        id: z.string(),
        title: z.string().optional(),
        // content is Tiptap JSONContent — accept any shape
        content: z.any().optional(),
        contentText: z.string().optional(),
        emoji: z.string().nullable().optional(),
        order: z.number().optional(),
        linkedThreadId: z.string().nullable().optional(),
        linkedEventId: z.string().nullable().optional(),
        linkedTaskId: z.string().nullable().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Build partial update object — only include fields that were explicitly provided
        const updateData: Record<string, unknown> = { updatedAt: new Date() };
        if (input.title !== undefined) updateData.title = input.title;
        if (input.content !== undefined) updateData.content = input.content;
        if (input.contentText !== undefined) updateData.contentText = input.contentText;
        if (input.emoji !== undefined) updateData.emoji = input.emoji;
        if (input.order !== undefined) updateData.order = input.order;
        if (input.linkedThreadId !== undefined) updateData.linkedThreadId = input.linkedThreadId;
        if (input.linkedEventId !== undefined) updateData.linkedEventId = input.linkedEventId;
        if (input.linkedTaskId !== undefined) updateData.linkedTaskId = input.linkedTaskId;

        const [updated] = await db
          .update(doc)
          .set(updateData)
          // Scope to userId to prevent users from modifying other users' docs
          .where(and(eq(doc.id, input.id), eq(doc.userId, ctx.sessionUser.id)))
          .returning();

        if (!updated) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Doc not found' });
        }

        return { doc: updated };
      } finally {
        await conn.end();
      }
    }),

  delete: privateProcedure
    .input(z.object({ id: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Note: parentId uses onDelete: 'set null' (not cascade) to avoid constraint
        // violations on the self-referential FK. Child docs are NOT auto-deleted here;
        // the caller is responsible for recursive deletion or the UI handles orphan cleanup.
        await db
          .delete(doc)
          .where(and(eq(doc.id, input.id), eq(doc.userId, ctx.sessionUser.id)));

        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  search: privateProcedure
    .input(z.object({ query: z.string().min(1).max(200) }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const docs = await db
          .select()
          .from(doc)
          .where(
            and(
              eq(doc.userId, ctx.sessionUser.id),
              // Search across both title and plaintext content mirror
              or(
                ilike(doc.title, `%${input.query}%`),
                ilike(doc.contentText, `%${input.query}%`),
              ),
            ),
          )
          .limit(20);

        return { docs };
      } finally {
        await conn.end();
      }
    }),
});
