import { sharedConversation, aiConversation } from '../../db/schema';
import { privateProcedure, publicProcedure, createRateLimiterMiddleware, router } from '../trpc';
import { Ratelimit } from '@upstash/ratelimit';
import { createDb } from '../../db';
import { eq, and, isNull } from 'drizzle-orm';
import { env } from '../../env';
import { TRPCError } from '@trpc/server';
import { z } from 'zod';

const getDb = () => createDb(env.HYPERDRIVE.connectionString);

// ── Password hashing via Web Crypto (PBKDF2, available natively in CF Workers) ─────────────
// Using 100,000 iterations + SHA-256. No bcrypt/argon2 needed; PBKDF2 is available
// everywhere and is the recommended algorithm for CF Workers edge environments.

async function hashPassword(password: string): Promise<{ hash: string; salt: string }> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100_000, hash: 'SHA-256' },
    keyMaterial,
    256,
  );
  return {
    hash: btoa(String.fromCharCode(...new Uint8Array(bits))),
    salt: btoa(String.fromCharCode(...salt)),
  };
}

async function verifyPassword(password: string, hash: string, salt: string): Promise<boolean> {
  const saltBytes = Uint8Array.from(atob(salt), (c) => c.charCodeAt(0));
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: saltBytes, iterations: 100_000, hash: 'SHA-256' },
    keyMaterial,
    256,
  );
  const candidate = btoa(String.fromCharCode(...new Uint8Array(bits)));
  // Constant-time comparison: compare char-by-char to prevent timing attacks
  if (candidate.length !== hash.length) return false;
  let diff = 0;
  for (let i = 0; i < candidate.length; i++) {
    diff |= candidate.charCodeAt(i) ^ hash.charCodeAt(i);
  }
  return diff === 0;
}

/** Generate a 10-char URL-safe slug */
function generateSlug(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return btoa(String.fromCharCode(...bytes))
    .replace(/[+/=]/g, '')
    .slice(0, 10);
}

function isExpired(expiresAt: Date | null): boolean {
  return expiresAt !== null && expiresAt < new Date();
}

// Rate limiter for public slug fetches: 20 req / 1 min per IP.
// This limits brute-force attempts on password-protected shares.
// The Upstash middleware uses the client IP as the rate-limit key, so per-IP bucketing
// is handled automatically by the createRateLimiterMiddleware helper.
const shareAccessRateLimiter = createRateLimiterMiddleware({
  limiter: Ratelimit.slidingWindow(20, '1 m'),
  generatePrefix: (_ctx, _input) => `share-access`,
});

export const sharingRouter = router({
  /** Create a share link for one of the authenticated user's conversations */
  create: privateProcedure
    .input(
      z.object({
        conversationId: z.string(),
        title: z.string().default(''),
        password: z.string().optional(),
        expiresInDays: z.enum(['never', '1', '7', '30']).default('never'),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        // Verify ownership — user can only share their own conversations
        const [convo] = await db
          .select({ id: aiConversation.id, title: aiConversation.title })
          .from(aiConversation)
          .where(
            and(
              eq(aiConversation.id, input.conversationId),
              eq(aiConversation.userId, ctx.sessionUser.id),
            ),
          )
          .limit(1);

        if (!convo) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Conversation not found.' });
        }

        // Hash password if provided
        let passwordHash: string | null = null;
        let passwordSalt: string | null = null;
        if (input.password) {
          const result = await hashPassword(input.password);
          passwordHash = result.hash;
          passwordSalt = result.salt;
        }

        // Compute expiry timestamp
        let expiresAt: Date | null = null;
        if (input.expiresInDays !== 'never') {
          expiresAt = new Date(Date.now() + parseInt(input.expiresInDays) * 86_400_000);
        }

        const slug = generateSlug();
        const id = crypto.randomUUID();
        const title = input.title || convo.title || 'Shared conversation';

        await db.insert(sharedConversation).values({
          id,
          ownerUserId: ctx.sessionUser.id,
          conversationId: input.conversationId,
          slug,
          title,
          passwordHash,
          passwordSalt,
          expiresAt,
        });

        return {
          id,
          slug,
          title,
          expiresAt,
          passwordProtected: !!passwordHash,
        };
      } finally {
        await conn.end();
      }
    }),

  /**
   * Public endpoint: resolve a share slug and return the frozen snapshot.
   * Rate-limited to mitigate brute-force on password-protected shares.
   */
  get: publicProcedure
    .use(shareAccessRateLimiter)
    .input(
      z.object({
        slug: z.string(),
        password: z.string().optional(),
      }),
    )
    .query(async ({ input }) => {
      const { db, conn } = getDb();
      try {
        const [share] = await db
          .select()
          .from(sharedConversation)
          .where(
            and(
              eq(sharedConversation.slug, input.slug),
              isNull(sharedConversation.revokedAt),
            ),
          )
          .limit(1);

        if (!share) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Share not found.' });
        }
        if (isExpired(share.expiresAt)) {
          throw new TRPCError({
            code: 'NOT_FOUND',
            message: 'This shared conversation has expired.',
          });
        }

        // Password gate — return early with flag before loading messages
        if (share.passwordHash) {
          if (!input.password) {
            return { passwordRequired: true as const, title: share.title };
          }
          // Guard against data corruption — passwordSalt must be present when passwordHash is
          if (!share.passwordSalt) {
            throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'Share is misconfigured.' });
          }
          const ok = await verifyPassword(input.password, share.passwordHash, share.passwordSalt);
          if (!ok) {
            throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Incorrect password.' });
          }
        }

        // Load messages from the source conversation
        const [convo] = await db
          .select({ messages: aiConversation.messages })
          .from(aiConversation)
          .where(eq(aiConversation.id, share.conversationId))
          .limit(1);

        if (!convo) {
          throw new TRPCError({
            code: 'NOT_FOUND',
            message: 'The source conversation for this share is no longer available.',
          });
        }

        return {
          passwordRequired: false as const,
          title: share.title,
          createdAt: share.createdAt,
          messages: (convo.messages as Array<{ role: string; content: string }>) ?? [],
        };
      } finally {
        await conn.end();
      }
    }),

  /**
   * Authenticated: copy a shared conversation into the current user's account
   * as a new conversation. Does not link back to the original.
   * Rate-limited to prevent brute-forcing password-protected shares via the import endpoint.
   */
  import: privateProcedure
    .use(shareAccessRateLimiter)
    .input(
      z.object({
        slug: z.string(),
        password: z.string().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const [share] = await db
          .select()
          .from(sharedConversation)
          .where(
            and(
              eq(sharedConversation.slug, input.slug),
              isNull(sharedConversation.revokedAt),
            ),
          )
          .limit(1);

        if (!share) throw new TRPCError({ code: 'NOT_FOUND' });
        if (isExpired(share.expiresAt))
          throw new TRPCError({ code: 'NOT_FOUND', message: 'This link has expired.' });

        if (share.passwordHash) {
          if (!input.password)
            throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Password required.' });
          // Guard against data corruption — passwordSalt must be present when passwordHash is
          if (!share.passwordSalt) {
            throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'Share is misconfigured.' });
          }
          const ok = await verifyPassword(
            input.password,
            share.passwordHash,
            share.passwordSalt,
          );
          if (!ok) throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Incorrect password.' });
        }

        const [convo] = await db
          .select({ messages: aiConversation.messages, title: aiConversation.title })
          .from(aiConversation)
          .where(eq(aiConversation.id, share.conversationId))
          .limit(1);

        const newId = crypto.randomUUID();
        await db.insert(aiConversation).values({
          id: newId,
          userId: ctx.sessionUser.id,
          title: `Copy of: ${share.title || convo?.title || 'Conversation'}`,
          messages: convo?.messages ?? [],
        });

        return { newConversationId: newId };
      } finally {
        await conn.end();
      }
    }),

  /** List the authenticated user's own share links (for settings/sharing page) */
  listMine: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const shares = await db
        .select({
          id: sharedConversation.id,
          slug: sharedConversation.slug,
          title: sharedConversation.title,
          passwordHash: sharedConversation.passwordHash,
          expiresAt: sharedConversation.expiresAt,
          revokedAt: sharedConversation.revokedAt,
          createdAt: sharedConversation.createdAt,
          conversationId: sharedConversation.conversationId,
        })
        .from(sharedConversation)
        .where(eq(sharedConversation.ownerUserId, ctx.sessionUser.id));

      return shares.map((s) => ({
        id: s.id,
        slug: s.slug,
        title: s.title,
        passwordProtected: !!s.passwordHash,
        expiresAt: s.expiresAt,
        revokedAt: s.revokedAt,
        createdAt: s.createdAt,
        conversationId: s.conversationId,
        status: s.revokedAt ? 'revoked' : isExpired(s.expiresAt) ? 'expired' : 'active',
      }));
    } finally {
      await conn.end();
    }
  }),

  /** Revoke a share link — immediately makes the URL unusable */
  revoke: privateProcedure
    .input(z.object({ id: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const updated = await db
          .update(sharedConversation)
          .set({ revokedAt: new Date() })
          .where(
            and(
              eq(sharedConversation.id, input.id),
              eq(sharedConversation.ownerUserId, ctx.sessionUser.id),
            ),
          )
          .returning({ id: sharedConversation.id });
        return { success: updated.length > 0 };
      } finally {
        await conn.end();
      }
    }),

  /** Update expiry or password on an existing active share */
  update: privateProcedure
    .input(
      z.object({
        id: z.string(),
        // null = remove password entirely; undefined = leave unchanged
        password: z.string().nullable().optional(),
        expiresInDays: z.enum(['never', '1', '7', '30']).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const updates: Partial<typeof sharedConversation.$inferInsert> = {};

        if (input.password !== undefined) {
          if (input.password === null) {
            // Explicitly removing password protection
            updates.passwordHash = null;
            updates.passwordSalt = null;
          } else {
            const result = await hashPassword(input.password);
            updates.passwordHash = result.hash;
            updates.passwordSalt = result.salt;
          }
        }

        if (input.expiresInDays !== undefined) {
          updates.expiresAt =
            input.expiresInDays === 'never'
              ? null
              : new Date(Date.now() + parseInt(input.expiresInDays) * 86_400_000);
        }

        // Revoked shares must not be modifiable
        const updated = await db
          .update(sharedConversation)
          .set(updates)
          .where(
            and(
              eq(sharedConversation.id, input.id),
              eq(sharedConversation.ownerUserId, ctx.sessionUser.id),
              isNull(sharedConversation.revokedAt),
            ),
          )
          .returning({ id: sharedConversation.id });

        return { success: updated.length > 0 };
      } finally {
        await conn.end();
      }
    }),
});
