import {
  account,
  connection,
  note,
  session,
  verification,
  user,
  userHotkeys,
  userSettings,
  writingStyleMatrix,
  emailTemplate,
} from './db/schema';
import {
  createUpdatedMatrixFromNewEmail,
  initializeStyleMatrixFromEmail,
  type EmailMatrix,
  type WritingStyleMatrix,
} from './services/writing-style-service';
import {
  toAttachmentFiles,
  type SerializedAttachment,
  type AttachmentFile,
} from './lib/attachments';
import { SyncThreadsCoordinatorWorkflow } from './workflows/sync-threads-coordinator-workflow';
import { WorkerEntrypoint, DurableObject, RpcTarget } from 'cloudflare:workers';
// import { instrument, type ResolveConfigFn } from '@microlabs/otel-cf-workers';
import { getZeroAgent, getZeroDB, verifyToken } from './lib/server-utils';
import { SyncThreadsWorkflow } from './workflows/sync-threads-workflow';
import { ShardRegistry, ZeroAgent, ZeroDriver } from './routes/agent';
import { ThreadSyncWorker } from './routes/agent/sync-worker';
import { eq, and, desc, asc, inArray, gt } from 'drizzle-orm';
import { oAuthDiscoveryMetadata } from 'better-auth/plugins';
import { EProviders, type IEmailSendBatch } from './types';
import { ThinkingMCP } from './lib/sequential-thinking';
import { serializeSignedCookie } from 'better-call';

import { recallWebhookRouter } from './routes/recall-webhook';
import { autumnWebhookRouter } from './routes/autumn-webhook';
import { contextStorage } from 'hono/context-storage';
import { getBrowserTimezone } from './lib/timezones';
import { defaultUserSettings } from './lib/schemas';
import { createLocalJWKSet, jwtVerify } from 'jose';
import { enableBrainFunction } from './lib/brain';
import { env, setEnv, type ZeroEnv } from './env';
import { trpcServer } from '@hono/trpc-server';
import { agentsMiddleware } from 'hono-agents';
import { ZeroMCP } from './routes/agent/mcp';
import { publicRouter } from './routes/auth';
import { WorkflowRunner } from './pipelines';
import { autumnApi } from './routes/autumn';
import { initTracing } from './lib/tracing';
import type { HonoContext } from './ctx';
import { createDb, type DB } from './db';
import { createAuth } from './lib/auth';
import { aiRouter } from './routes/ai';
import { appRouter } from './trpc';
import { cors } from 'hono/cors';
import { Hono } from 'hono';

const SENTRY_HOST = 'o4509328786915328.ingest.us.sentry.io';
const SENTRY_PROJECT_IDS = new Set(['4509328795303936']);
const NATIVE_SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 90;

const createNativeSessionToken = () => {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
};

export class DbRpcDO extends RpcTarget {
  constructor(
    private mainDo: ZeroDB,
    private userId: string,
  ) {
    super();
  }

  async findUser(): Promise<typeof user.$inferSelect | undefined> {
    return await this.mainDo.findUser(this.userId);
  }

  async findUserConnection(
    connectionId: string,
  ): Promise<typeof connection.$inferSelect | undefined> {
    return await this.mainDo.findUserConnection(this.userId, connectionId);
  }

  async updateUser(data: Partial<typeof user.$inferInsert>) {
    return await this.mainDo.updateUser(this.userId, data);
  }

  async deleteConnection(connectionId: string) {
    return await this.mainDo.deleteConnection(connectionId, this.userId);
  }

  async findFirstConnection(): Promise<typeof connection.$inferSelect | undefined> {
    return await this.mainDo.findFirstConnection(this.userId);
  }

  async findManyConnections(): Promise<(typeof connection.$inferSelect)[]> {
    return await this.mainDo.findManyConnections(this.userId);
  }

  async findManyNotesByThreadId(threadId: string): Promise<(typeof note.$inferSelect)[]> {
    return await this.mainDo.findManyNotesByThreadId(this.userId, threadId);
  }

  async createNote(payload: Omit<typeof note.$inferInsert, 'userId'>) {
    return await this.mainDo.createNote(this.userId, payload as typeof note.$inferInsert);
  }

  async updateNote(noteId: string, payload: Partial<typeof note.$inferInsert>) {
    return await this.mainDo.updateNote(this.userId, noteId, payload);
  }

  async updateManyNotes(
    notes: { id: string; order: number; isPinned?: boolean | null }[],
  ): Promise<boolean> {
    return await this.mainDo.updateManyNotes(this.userId, notes);
  }

  async findManyNotesByIds(noteIds: string[]): Promise<(typeof note.$inferSelect)[]> {
    return await this.mainDo.findManyNotesByIds(this.userId, noteIds);
  }

  async deleteNote(noteId: string) {
    return await this.mainDo.deleteNote(this.userId, noteId);
  }

  async findNoteById(noteId: string): Promise<typeof note.$inferSelect | undefined> {
    return await this.mainDo.findNoteById(this.userId, noteId);
  }

  async findHighestNoteOrder(): Promise<{ order: number } | undefined> {
    return await this.mainDo.findHighestNoteOrder(this.userId);
  }

  async deleteUser() {
    return await this.mainDo.deleteUser(this.userId);
  }

  async findUserSettings(): Promise<typeof userSettings.$inferSelect | undefined> {
    return await this.mainDo.findUserSettings(this.userId);
  }

  async findUserHotkeys(): Promise<(typeof userHotkeys.$inferSelect)[]> {
    return await this.mainDo.findUserHotkeys(this.userId);
  }

  async insertUserHotkeys(shortcuts: (typeof userHotkeys.$inferInsert)[]) {
    return await this.mainDo.insertUserHotkeys(this.userId, shortcuts);
  }

  async insertUserSettings(settings: typeof defaultUserSettings) {
    return await this.mainDo.insertUserSettings(this.userId, settings);
  }

  async updateUserSettings(settings: typeof defaultUserSettings) {
    return await this.mainDo.updateUserSettings(this.userId, settings);
  }

  async createConnection(
    providerId: EProviders,
    email: string,
    updatingInfo: {
      expiresAt: Date;
      scope: string;
    },
  ): Promise<{ id: string }[]> {
    return await this.mainDo.createConnection(providerId, email, this.userId, updatingInfo);
  }

  async findConnectionById(
    connectionId: string,
  ): Promise<typeof connection.$inferSelect | undefined> {
    return await this.mainDo.findConnectionById(connectionId);
  }

  async syncUserMatrix(connectionId: string, emailStyleMatrix: EmailMatrix) {
    return await this.mainDo.syncUserMatrix(connectionId, emailStyleMatrix);
  }

  async findWritingStyleMatrix(
    connectionId: string,
  ): Promise<typeof writingStyleMatrix.$inferSelect | undefined> {
    return await this.mainDo.findWritingStyleMatrix(connectionId);
  }

  async deleteActiveConnection(connectionId: string) {
    return await this.mainDo.deleteActiveConnection(this.userId, connectionId);
  }

  async updateConnection(
    connectionId: string,
    updatingInfo: Partial<typeof connection.$inferInsert>,
  ) {
    return await this.mainDo.updateConnection(connectionId, updatingInfo);
  }

  async listEmailTemplates(): Promise<(typeof emailTemplate.$inferSelect)[]> {
    return await this.mainDo.findManyEmailTemplates(this.userId);
  }

  async createEmailTemplate(payload: Omit<typeof emailTemplate.$inferInsert, 'userId'>) {
    return await this.mainDo.createEmailTemplate(this.userId, payload);
  }

  async deleteEmailTemplate(templateId: string) {
    return await this.mainDo.deleteEmailTemplate(this.userId, templateId);
  }

  async updateEmailTemplate(templateId: string, data: Partial<typeof emailTemplate.$inferInsert>) {
    return await this.mainDo.updateEmailTemplate(this.userId, templateId, data);
  }
}

class ZeroDB extends DurableObject<ZeroEnv> {
  db: DB = createDb(this.env.HYPERDRIVE.connectionString).db;

  async setMetaData(userId: string) {
    return new DbRpcDO(this, userId);
  }

  async findUser(userId: string): Promise<typeof user.$inferSelect | undefined> {
    return await this.db.query.user.findFirst({
      where: eq(user.id, userId),
    });
  }

  async findUserConnection(
    userId: string,
    connectionId: string,
  ): Promise<typeof connection.$inferSelect | undefined> {
    return await this.db.query.connection.findFirst({
      where: and(eq(connection.userId, userId), eq(connection.id, connectionId)),
    });
  }

  async updateUser(userId: string, data: Partial<typeof user.$inferInsert>) {
    return await this.db.update(user).set(data).where(eq(user.id, userId));
  }

  async deleteConnection(connectionId: string, userId: string) {
    const connections = await this.findManyConnections(userId);
    if (connections.length <= 1) {
      throw new Error('Cannot delete the last connection. At least one connection is required.');
    }
    return await this.db
      .delete(connection)
      .where(and(eq(connection.id, connectionId), eq(connection.userId, userId)));
  }

  async findFirstConnection(userId: string): Promise<typeof connection.$inferSelect | undefined> {
    return await this.db.query.connection.findFirst({
      where: eq(connection.userId, userId),
    });
  }

  async findManyConnections(userId: string): Promise<(typeof connection.$inferSelect)[]> {
    return await this.db.query.connection.findMany({
      where: eq(connection.userId, userId),
    });
  }

  async findManyNotesByThreadId(
    userId: string,
    threadId: string,
  ): Promise<(typeof note.$inferSelect)[]> {
    return await this.db.query.note.findMany({
      where: and(eq(note.userId, userId), eq(note.threadId, threadId)),
      orderBy: [desc(note.isPinned), asc(note.order), desc(note.createdAt)],
    });
  }

  async createNote(userId: string, payload: typeof note.$inferInsert) {
    return await this.db
      .insert(note)
      .values({
        ...payload,
        userId,
        createdAt: new Date(),
        updatedAt: new Date(),
      })
      .returning();
  }

  async updateNote(
    userId: string,
    noteId: string,
    payload: Partial<typeof note.$inferInsert>,
  ): Promise<typeof note.$inferSelect | undefined> {
    const [updated] = await this.db
      .update(note)
      .set({
        ...payload,
        updatedAt: new Date(),
      })
      .where(and(eq(note.id, noteId), eq(note.userId, userId)))
      .returning();
    return updated;
  }

  async updateManyNotes(
    userId: string,
    notes: { id: string; order: number; isPinned?: boolean | null }[],
  ): Promise<boolean> {
    return await this.db.transaction(async (tx) => {
      for (const n of notes) {
        const updateData: Record<string, unknown> = {
          order: n.order,
          updatedAt: new Date(),
        };

        if (n.isPinned !== undefined) {
          updateData.isPinned = n.isPinned;
        }
        await tx
          .update(note)
          .set(updateData)
          .where(and(eq(note.id, n.id), eq(note.userId, userId)));
      }
      return true;
    });
  }

  async findManyNotesByIds(
    userId: string,
    noteIds: string[],
  ): Promise<(typeof note.$inferSelect)[]> {
    return await this.db.query.note.findMany({
      where: and(eq(note.userId, userId), inArray(note.id, noteIds)),
    });
  }

  async deleteNote(userId: string, noteId: string) {
    return await this.db.delete(note).where(and(eq(note.id, noteId), eq(note.userId, userId)));
  }

  async findNoteById(
    userId: string,
    noteId: string,
  ): Promise<typeof note.$inferSelect | undefined> {
    return await this.db.query.note.findFirst({
      where: and(eq(note.id, noteId), eq(note.userId, userId)),
    });
  }

  async findHighestNoteOrder(userId: string): Promise<{ order: number } | undefined> {
    return await this.db.query.note.findFirst({
      where: eq(note.userId, userId),
      orderBy: desc(note.order),
      columns: { order: true },
    });
  }

  async deleteUser(userId: string) {
    return await this.db.transaction(async (tx) => {
      await tx.delete(connection).where(eq(connection.userId, userId));
      await tx.delete(account).where(eq(account.userId, userId));
      await tx.delete(session).where(eq(session.userId, userId));
      await tx.delete(userSettings).where(eq(userSettings.userId, userId));
      await tx.delete(user).where(eq(user.id, userId));
      await tx.delete(userHotkeys).where(eq(userHotkeys.userId, userId));
    });
  }

  async findUserSettings(userId: string): Promise<typeof userSettings.$inferSelect | undefined> {
    return await this.db.query.userSettings.findFirst({
      where: eq(userSettings.userId, userId),
    });
  }

  async findUserHotkeys(userId: string): Promise<(typeof userHotkeys.$inferSelect)[]> {
    return await this.db.query.userHotkeys.findMany({
      where: eq(userHotkeys.userId, userId),
    });
  }

  async insertUserHotkeys(userId: string, shortcuts: (typeof userHotkeys.$inferInsert)[]) {
    return await this.db
      .insert(userHotkeys)
      .values({
        userId,
        shortcuts,
        createdAt: new Date(),
        updatedAt: new Date(),
      })
      .onConflictDoUpdate({
        target: userHotkeys.userId,
        set: {
          shortcuts,
          updatedAt: new Date(),
        },
      });
  }

  async insertUserSettings(userId: string, settings: typeof defaultUserSettings) {
    return await this.db.insert(userSettings).values({
      id: crypto.randomUUID(),
      userId,
      settings,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  }

  async updateUserSettings(userId: string, settings: typeof defaultUserSettings) {
    return await this.db
      .insert(userSettings)
      .values({
        id: crypto.randomUUID(),
        userId,
        settings,
        createdAt: new Date(),
        updatedAt: new Date(),
      })
      .onConflictDoUpdate({
        target: userSettings.userId,
        set: {
          settings,
          updatedAt: new Date(),
        },
      });
  }

  async createConnection(
    providerId: EProviders,
    email: string,
    userId: string,
    updatingInfo: {
      expiresAt: Date;
      scope: string;
    },
  ): Promise<{ id: string }[]> {
    return await this.db
      .insert(connection)
      .values({
        ...updatingInfo,
        providerId,
        id: crypto.randomUUID(),
        email,
        userId,
        createdAt: new Date(),
        updatedAt: new Date(),
      })
      .onConflictDoUpdate({
        target: [connection.email, connection.userId],
        set: {
          ...updatingInfo,
          updatedAt: new Date(),
        },
      })
      .returning({ id: connection.id });
  }

  /**
   * @param connectionId Dangerous, use findUserConnection instead
   * @returns
   */
  async findConnectionById(
    connectionId: string,
  ): Promise<typeof connection.$inferSelect | undefined> {
    return await this.db.query.connection.findFirst({
      where: eq(connection.id, connectionId),
    });
  }

  async syncUserMatrix(connectionId: string, emailStyleMatrix: EmailMatrix) {
    await this.db.transaction(async (tx) => {
      const [existingMatrix] = await tx
        .select({
          numMessages: writingStyleMatrix.num_messages,
          style: writingStyleMatrix.style,
        })
        .from(writingStyleMatrix)
        .where(eq(writingStyleMatrix.connection_id, connectionId));

      if (existingMatrix) {
        const newStyle = createUpdatedMatrixFromNewEmail(
          existingMatrix.numMessages,
          existingMatrix.style as WritingStyleMatrix,
          emailStyleMatrix,
        );

        await tx
          .update(writingStyleMatrix)
          .set({
            num_messages: existingMatrix.numMessages + 1,
            style: newStyle,
          })
          .where(eq(writingStyleMatrix.connection_id, connectionId));
      } else {
        const newStyle = initializeStyleMatrixFromEmail(emailStyleMatrix);

        await tx
          .insert(writingStyleMatrix)
          .values({
            connection_id: connectionId,
            num_messages: 1,
            style: newStyle,
            updated_at: new Date(),
          })
          .onConflictDoNothing();
      }
    });
  }

  async findWritingStyleMatrix(
    connectionId: string,
  ): Promise<typeof writingStyleMatrix.$inferSelect | undefined> {
    return await this.db.query.writingStyleMatrix.findFirst({
      where: eq(writingStyleMatrix.connection_id, connectionId),
      columns: {
        num_messages: true,
        style: true,
        updated_at: true,
        connection_id: true,
      },
    });
  }

  async deleteActiveConnection(userId: string, connectionId: string) {
    return await this.db
      .delete(connection)
      .where(and(eq(connection.userId, userId), eq(connection.id, connectionId)));
  }

  async updateConnection(
    connectionId: string,
    updatingInfo: Partial<typeof connection.$inferInsert>,
  ) {
    return await this.db
      .update(connection)
      .set(updatingInfo)
      .where(eq(connection.id, connectionId));
  }

  async findManyEmailTemplates(userId: string): Promise<(typeof emailTemplate.$inferSelect)[]> {
    return await this.db.query.emailTemplate.findMany({
      where: eq(emailTemplate.userId, userId),
      orderBy: desc(emailTemplate.updatedAt),
    });
  }

  async createEmailTemplate(
    userId: string,
    payload: Omit<typeof emailTemplate.$inferInsert, 'userId'>,
  ) {
    return await this.db
      .insert(emailTemplate)
      .values({
        ...payload,
        userId,
        id: crypto.randomUUID(),
        createdAt: new Date(),
        updatedAt: new Date(),
      })
      .returning();
  }

  async deleteEmailTemplate(userId: string, templateId: string) {
    return await this.db
      .delete(emailTemplate)
      .where(and(eq(emailTemplate.id, templateId), eq(emailTemplate.userId, userId)));
  }

  async updateEmailTemplate(
    userId: string,
    templateId: string,
    data: Partial<typeof emailTemplate.$inferInsert>,
  ) {
    return await this.db
      .update(emailTemplate)
      .set({ ...data, updatedAt: new Date() })
      .where(and(eq(emailTemplate.id, templateId), eq(emailTemplate.userId, userId)))
      .returning();
  }
}

// Utility function to hash IP addresses for PII protection
function hashIpAddress(ip: string | undefined): string | undefined {
  if (!ip) return undefined;

  // Simple but effective hash for IP addresses
  // This preserves uniqueness while protecting PII
  const salt = 'zero-mail-ip-salt-2024'; // Consider using env variable for production
  let hash = 0;
  const str = ip + salt;

  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash; // Convert to 32bit integer
  }

  // Return a prefixed hex representation
  return `ip_${Math.abs(hash).toString(16).padStart(8, '0')}`;
}

const api = new Hono<HonoContext>()
  .use(contextStorage())
  .use('*', async (c, next) => {
    // Public routes don't need auth or DB — skip the heavy middleware
    const path = new URL(c.req.url).pathname;
    if (path.startsWith('/api/public/') || path === '/api/public') {
      return next();
    }

    // Initialize request tracing using headers (no context pollution)
    const traceId = c.req.header('X-Trace-ID') || crypto.randomUUID();
    const requestId = c.req.header('X-Request-Id') || crypto.randomUUID();

    // Set trace ID in response headers for client correlation
    c.header('X-Trace-ID', traceId);
    c.header('X-Request-ID', requestId);

    // Store trace ID in context variables for TRPC access
    c.set('traceId', traceId);
    c.set('requestId', requestId);

    const { TraceContext } = await import('./lib/trace-context');

    // Create trace for this request
    const rawIp = c.req.header('CF-Connecting-IP') || c.req.header('X-Forwarded-For');
    const trace = TraceContext.createTrace(traceId, {
      requestId,
      ip: hashIpAddress(rawIp), // Hash IP address to protect PII
      userAgent: c.req.header('User-Agent'),
    });

    // Start authentication span
    const authSpan = TraceContext.startSpan(
      traceId,
      'authentication',
      {
        method: c.req.method,
        url: c.req.url,
        hasAuthHeader: !!c.req.header('Authorization'),
      },
      {
        'auth.method': c.req.header('Authorization') ? 'bearer_token' : 'session_cookie',
      },
    );

    const auth = createAuth();
    c.set('auth', auth);
    // Named `authSession` to avoid shadowing the Drizzle `session` schema table import,
    // which is needed for the session token DB lookup fallback below.
    const authSession = await auth.api.getSession({ headers: c.req.raw.headers });
    c.set('sessionUser', authSession?.user);

    if (c.req.header('Authorization') && !authSession?.user) {
      // Start token verification span
      const tokenSpan = TraceContext.startSpan(
        traceId,
        'token_verification',
        {
          tokenPresent: true,
        },
        {
          'auth.token_type': 'jwt',
        },
      );

      const token = c.req.header('Authorization')?.split(' ')[1];

      if (token) {
        let resolved = false;

        // Strategy 1: JWT verification (for tokens issued by the jwt() plugin)
        try {
          const localJwks = await auth.api.getJwks();
          const jwks = createLocalJWKSet(localJwks);

          const { payload } = await jwtVerify(token, jwks);
          const userId = payload.sub;

          if (userId) {
            const db = await getZeroDB(userId);
            const user = await db.findUser();
            if (user) {
              c.set('sessionUser', user);
              resolved = true;

              TraceContext.completeSpan(traceId, tokenSpan.id, {
                success: true,
                userId,
              });
            } else {
              // JWT decoded successfully and identified a userId, but no matching
              // user row exists. The user was deleted out from under a still-valid
              // token — terminal. Mark as resolved so Strategies 2/3 don't run and
              // re-complete this span (which would clobber the `user_not_found`
              // metadata recorded here). The request continues unauthenticated.
              resolved = true;
              TraceContext.completeSpan(traceId, tokenSpan.id, {
                success: false,
                reason: 'user_not_found',
                userId,
              });
            }
          }
        } catch {
          // Not a JWT — try session token strategies below
        }

        // Strategy 2: Raw native session token → resolve directly from the DB.
        // /auth/mobile-token returns Better Auth session.session.token, which is the
        // raw session token stored in the session table. Resolving this directly is
        // more reliable than reconstructing a signed cookie on the fly.
        if (!resolved) {
          const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
          try {
            const [activeSession] = await db
              .select({ userId: session.userId })
              .from(session)
              .where(and(eq(session.token, token), gt(session.expiresAt, new Date())))
              .limit(1);

            if (activeSession?.userId) {
              const nativeUser = await db.query.user.findFirst({
                where: eq(user.id, activeSession.userId),
              });

              if (nativeUser) {
                c.set('sessionUser', nativeUser);
                resolved = true;

                TraceContext.completeSpan(traceId, tokenSpan.id, {
                  success: true,
                  userId: nativeUser.id,
                  authMethod: 'raw_session_token_db_lookup',
                });
              }
            }
          } catch (err) {
            const error = err instanceof Error ? err : new Error(String(err));
            console.error('[auth/mobile-token] Raw session token DB lookup failed', error);
            TraceContext.completeSpan(traceId, tokenSpan.id, {
              success: false,
              error: error.message,
            });
          } finally {
            await conn.end();
          }
        }

        // Strategy 3: Raw session token → sign as cookie → re-resolve via Better Auth.
        // Keep the cookie rehydration path as a fallback for compatibility with
        // any token variants that aren't stored directly in the session table.
        if (!resolved) {
          try {
            const cookiePrefix = env.NODE_ENV === 'development' ? 'better-auth-dev' : 'better-auth';
            const signedToken = (
              await serializeSignedCookie('', token, env.BETTER_AUTH_SECRET)
            ).replace('=', '');

            const cookieSession = await auth.api.getSession({
              headers: new Headers({
                cookie: `${cookiePrefix}.session_token=${signedToken}`,
                origin: 'https://todus.app',
              }),
            });

            if (cookieSession?.user) {
              c.set('sessionUser', cookieSession.user);
              resolved = true;

              TraceContext.completeSpan(traceId, tokenSpan.id, {
                success: true,
                userId: cookieSession.user.id,
                authMethod: 'session_token_as_cookie',
              });
            }
          } catch {
            // Session token resolution failed
          }
        }

        if (!resolved) {
          TraceContext.completeSpan(traceId, tokenSpan.id, {
            success: false,
            reason: 'all_token_strategies_failed',
          });
        }
      } else {
        TraceContext.completeSpan(traceId, tokenSpan.id, {
          success: false,
          reason: 'no_token_provided',
        });
      }
    }

    // Complete auth span
    TraceContext.completeSpan(traceId, authSpan.id, {
      authenticated: !!c.var.sessionUser,
      userId: c.var.sessionUser?.id,
      authMethod: authSession?.user ? 'session' : c.req.header('Authorization') ? 'token' : 'none',
    });

    // Update trace metadata with user info
    trace.metadata.userId = c.var.sessionUser?.id;
    trace.metadata.sessionId = c.var.sessionUser?.id || 'anonymous';

    // Start request processing span
    const requestSpan = TraceContext.startSpan(traceId, 'request_processing', {
      authenticated: !!c.var.sessionUser,
      path: new URL(c.req.url).pathname,
    });

    try {
      await next();
      // Don't complete the request span here - let TRPC middleware handle it
    } catch (error) {
      TraceContext.completeSpan(
        traceId,
        requestSpan.id,
        {
          success: false,

          statusCode: c.res.status,
        },
        error instanceof Error ? error.message : 'Unknown request error',
      );
      throw error;
    }
    // Note: Trace will be completed by TRPC middleware after logging

    c.set('sessionUser', undefined);
    c.set('auth', undefined as any);
  })
  .route('/ai', aiRouter)
  .route('/autumn', autumnApi)
  .route('/public', publicRouter)
  .get('/auth/me', async (c) => {
    // Returns the authenticated user's profile from the middleware context.
    // Better Auth's HTTP get-session endpoint doesn't resolve bearer tokens,
    // but the Hono middleware (auth.api.getSession + JWT fallback) does.
    // Native apps (iOS/macOS) use this instead of /auth/get-session.
    const user = c.var.sessionUser;
    if (!user) {
      return c.json({ user: null }, 401);
    }
    return c.json({ user });
  })
  .get('/auth/mobile-token', async (c) => {
    // Bridge endpoint: converts a cookie-based web session into a dual-token pair
    // for native iOS/macOS apps:
    //   1. Short-lived JWT (15min) — "access token" for stateless API auth
    //   2. Raw session token (90-day sliding) — "refresh token" for getting new JWTs
    //
    // Native apps use the JWT for all API calls (verified via JWKS, no DB lookup).
    // When the JWT expires, they call /auth/refresh-native-token with the session
    // token to transparently get a fresh JWT. Users stay signed in indefinitely
    // as long as they use the app within any 90-day window.
    //
    // IMPORTANT: We return an HTML page with a JavaScript redirect instead of
    // a 302 redirect. iOS's ASWebAuthenticationSession (used by expo-web-browser)
    // unreliably intercepts HTTP 302 redirects to custom URL schemes (todus://)
    // through long redirect chains (Google → better-auth → mobile-token → todus://).
    // A JS-based redirect from an HTML page is the standard workaround.
    const auth = c.var.auth;
    const session = await auth.api.getSession({ headers: c.req.raw.headers });
    if (!session?.session?.token) {
      return c.redirect(`${env.VITE_PUBLIC_APP_URL}/login?error=no_session`);
    }
    const jwtToken = await auth.api.getToken({
      headers: c.req.raw.headers,
    });

    if (!jwtToken?.token) {
      return c.redirect(`${env.VITE_PUBLIC_APP_URL}/login?error=no_native_token`);
    }

    // Raw session token as refresh token — 90-day sliding window via updateAge.
    // Stored in Keychain on native apps, used only to obtain fresh JWTs.
    const refreshToken = session.session.token;

    // Build the deep link URL with both tokens for the native app
    const redirectUrl = c.req.query('redirect') || 'todus://auth-callback';
    const separator = redirectUrl.includes('?') ? '&' : '?';
    const sessionIdParam = session.session.id
      ? `&sessionId=${encodeURIComponent(session.session.id)}`
      : '';
    const deepLink = `${redirectUrl}${separator}token=${encodeURIComponent(jwtToken.token)}&refreshToken=${encodeURIComponent(refreshToken)}${sessionIdParam}`;

    // Return an HTML page that triggers the deep link via JavaScript.
    // This is more reliable than a 302 redirect for custom URL schemes on iOS.
    return c.html(`<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Redirecting...</title></head>
<body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:system-ui;background:#000;color:#fff">
<p>Redirecting to Todus…</p>
<script>window.location.href=${JSON.stringify(deepLink)};</script>
</body>
</html>`);
  })
  .post('/auth/refresh-native-token', async (c) => {
    // Refresh endpoint for native apps: exchanges a raw session token (refresh token)
    // for a fresh short-lived JWT (access token). This is the core of the access+refresh
    // pattern — native apps call this when their JWT expires (every ~15min) to get a
    // new one without requiring user interaction. The raw session token has a 90-day
    // sliding window (extended daily via Better Auth's updateAge), so users stay
    // signed in indefinitely as long as they use the app within any 90-day window.
    //
    // Security: The refresh token is validated through Better Auth's session resolution
    // (cookie-signing + getSession), which checks the session table and extends expiresAt.
    // If the session has been revoked (e.g., "sign out of all devices"), this returns 401.
    const body = await c.req
      .json<{ refreshToken?: string }>()
      .catch((): { refreshToken?: string } | null => null);
    const refreshToken = body?.refreshToken;

    if (!refreshToken) {
      return c.json({ error: 'Missing refresh token' }, 400);
    }

    try {
      const auth = createAuth();
      const mintJwtFromHeaders = async (headers: Headers) => {
        const session = await auth.api.getSession({ headers });
        if (!session?.user) {
          return null;
        }

        const jwtToken = await auth.api.getToken({ headers });
        if (!jwtToken?.token) return null;
        // Return both the JWT and the session ID so native apps can track
        // which session they are currently running in (for "This device" labelling
        // and the X-Todus-Session-Id request header used by sessions.list).
        return { token: jwtToken.token, sessionId: session.session?.id ?? null };
      };

      // Compatibility: native clients can still persist either:
      // 1. a bearer-plugin token from `set-auth-token`, or
      // 2. the raw Better Auth session token from `/auth/mobile-token`.
      // Try the bearer path first, then fall back to rehydrating the raw session
      // token as a signed cookie so older clients keep refreshing successfully.
      const bearerHeaders = new Headers({
        authorization: `Bearer ${refreshToken}`,
        origin: 'https://todus.app',
      });
      let result = await mintJwtFromHeaders(bearerHeaders).catch(() => null);

      if (!result) {
        const cookiePrefix = env.NODE_ENV === 'development' ? 'better-auth-dev' : 'better-auth';
        const signedToken = (
          await serializeSignedCookie('', refreshToken, env.BETTER_AUTH_SECRET)
        ).replace('=', '');

        const cookieHeaders = new Headers({
          cookie: `${cookiePrefix}.session_token=${signedToken}`,
          origin: 'https://todus.app',
        });
        result = await mintJwtFromHeaders(cookieHeaders).catch(() => null);
      }

      if (!result) {
        return c.json({ error: 'Session expired' }, 401);
      }

      return c.json({
        token: result.token,
        sessionId: result.sessionId,
        expiresIn: 900, // 15 minutes in seconds
      });
    } catch (err) {
      console.error('[auth/refresh-native-token] Error:', err);
      return c.json({ error: 'Token refresh failed' }, 500);
    }
  })
  .post('/auth/native-email-otp/verify', async (c) => {
    const body = await c.req
      .json<{ email?: string; otp?: string }>()
      .catch((): { email?: string; otp?: string } | null => null);
    const email = body?.email?.trim().toLowerCase();
    const otp = body?.otp?.trim();

    if (!email || !otp) {
      return c.json({ error: 'Missing email or OTP' }, 400);
    }

    const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
    try {
      const identifier = `sign-in-otp-${email}`;
      const [storedVerification] = await db
        .select()
        .from(verification)
        .where(eq(verification.identifier, identifier))
        .orderBy(desc(verification.expiresAt), desc(verification.createdAt))
        .limit(1);

      if (!storedVerification) {
        return c.json({ error: 'Invalid OTP' }, 400);
      }

      if (storedVerification.expiresAt < new Date()) {
        await db.delete(verification).where(eq(verification.id, storedVerification.id));
        return c.json({ error: 'OTP expired' }, 400);
      }

      const separatorIndex = storedVerification.value.lastIndexOf(':');
      const storedOtp =
        separatorIndex >= 0
          ? storedVerification.value.slice(0, separatorIndex)
          : storedVerification.value;
      const attempts =
        separatorIndex >= 0
          ? Number.parseInt(storedVerification.value.slice(separatorIndex + 1), 10) || 0
          : 0;

      if (attempts >= 3) {
        await db.delete(verification).where(eq(verification.id, storedVerification.id));
        return c.json({ error: 'Too many attempts' }, 403);
      }

      if (storedOtp !== otp) {
        await db
          .update(verification)
          .set({ value: `${storedOtp}:${attempts + 1}`, updatedAt: new Date() })
          .where(eq(verification.id, storedVerification.id));
        return c.json({ error: 'Invalid OTP' }, 400);
      }

      await db.delete(verification).where(eq(verification.id, storedVerification.id));

      const now = new Date();
      let [authUser] = await db
        .select({
          id: user.id,
          email: user.email,
          emailVerified: user.emailVerified,
          name: user.name,
          image: user.image,
          createdAt: user.createdAt,
          updatedAt: user.updatedAt,
        })
        .from(user)
        .where(eq(user.email, email))
        .limit(1);

      if (!authUser) {
        const userId = crypto.randomUUID();
        const [createdUser] = await db
          .insert(user)
          .values({
            id: userId,
            email,
            emailVerified: true,
            name: '',
            image: null,
            createdAt: now,
            updatedAt: now,
          })
          .returning({
            id: user.id,
            email: user.email,
            emailVerified: user.emailVerified,
            name: user.name,
            image: user.image,
            createdAt: user.createdAt,
            updatedAt: user.updatedAt,
          });
        authUser = createdUser;

        try {
          const zeroDb = await getZeroDB(userId);
          const existingSettings = await zeroDb.findUserSettings();
          if (!existingSettings) {
            await zeroDb.insertUserSettings({
              ...defaultUserSettings,
              timezone: getBrowserTimezone(),
            });
          }
        } catch (error) {
          console.error('[auth/native-email-otp] Failed to create default settings', {
            userId,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      } else if (!authUser.emailVerified) {
        await db
          .update(user)
          .set({ emailVerified: true, updatedAt: now })
          .where(eq(user.id, authUser.id));
        authUser = { ...authUser, emailVerified: true, updatedAt: now };
      }

      const sessionId = crypto.randomUUID();
      const token = createNativeSessionToken();
      const expiresAt = new Date(now.getTime() + NATIVE_SESSION_MAX_AGE_SECONDS * 1000);

      await db.insert(session).values({
        id: sessionId,
        token,
        userId: authUser.id,
        expiresAt,
        createdAt: now,
        updatedAt: now,
        ipAddress: c.req.header('CF-Connecting-IP') ?? null,
        userAgent: c.req.header('User-Agent') ?? null,
      });

      return c.json({
        token,
        sessionId,
        user: {
          id: authUser.id,
          email: authUser.email,
          emailVerified: authUser.emailVerified,
          name: authUser.name,
          image: authUser.image,
          createdAt: authUser.createdAt,
          updatedAt: authUser.updatedAt,
        },
      });
    } catch (error) {
      console.error('[auth/native-email-otp] Verification failed', error);
      return c.json({ error: 'Verification failed' }, 500);
    } finally {
      await conn.end();
    }
  })
  .post('/auth/native-link-social', async (c) => {
    const auth = c.var.auth;
    const sessionUser = c.var.sessionUser;
    const authHeader = c.req.header('Authorization');

    if (!sessionUser?.id || !authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }

    const rawToken = authHeader.slice('Bearer '.length).trim();
    if (!rawToken) {
      return c.json({ error: 'Missing bearer token' }, 401);
    }

    const {
      provider,
      callbackURL,
      disableRedirect,
      errorCallbackURL,
      scopes,
      requestSignUp,
      refreshToken,
    } =
      await c.req.json<{
        provider: string;
        callbackURL?: string;
        disableRedirect?: boolean;
        errorCallbackURL?: string;
        scopes?: string[];
        requestSignUp?: boolean;
        refreshToken?: string;
      }>();

    const { db } = createDb(env.HYPERDRIVE.connectionString);
    const trimmedRefreshToken = refreshToken?.trim();
    const sessionLookup = db
      .select({ token: session.token })
      .from(session)
      .where(
        trimmedRefreshToken
          ? and(
              eq(session.userId, sessionUser.id),
              eq(session.token, trimmedRefreshToken),
              gt(session.expiresAt, new Date()),
            )
          : and(eq(session.userId, sessionUser.id), gt(session.expiresAt, new Date())),
      );
    const [activeSession] = trimmedRefreshToken
      ? await sessionLookup.limit(1)
      : await sessionLookup.orderBy(desc(session.updatedAt), desc(session.createdAt)).limit(1);

    if (!activeSession?.token) {
      return c.json(
        {
          error: trimmedRefreshToken
            ? 'Native session expired. Please sign in again before linking Gmail.'
            : 'No active Better Auth session found for account linking.',
        },
        401,
      );
    }

    const cookiePrefix = env.NODE_ENV === 'development' ? 'better-auth-dev' : 'better-auth';
    const signedSessionToken = (
      await serializeSignedCookie('', activeSession.token, env.BETTER_AUTH_SECRET)
    ).replace('=', '');

    const forwardedHeaders = new Headers(c.req.raw.headers);
    forwardedHeaders.delete('authorization');
    const existingCookies = forwardedHeaders.get('cookie');
    forwardedHeaders.set(
      'cookie',
      existingCookies
        ? `${existingCookies}; ${cookiePrefix}.session_token=${signedSessionToken}`
        : `${cookiePrefix}.session_token=${signedSessionToken}`,
    );
    forwardedHeaders.set('content-type', 'application/json');

    const forwardedRequest = new Request(new URL('/api/auth/link-social', c.req.url).toString(), {
      method: 'POST',
      headers: forwardedHeaders,
      body: JSON.stringify({
        provider,
        callbackURL,
        disableRedirect,
        errorCallbackURL,
        scopes,
        requestSignUp,
      }),
      redirect: 'manual',
    });

    return await auth.handler(forwardedRequest);
  })
  .on(['GET', 'POST', 'OPTIONS'], '/auth/*', async (c) => {
    const authPath = new URL(c.req.url).pathname;
    try {
      return await c.var.auth.handler(c.req.raw);
    } catch (err) {
      // better-auth throws Response objects on errors (CSRF, validation, etc.)
      // Log the details so we can debug instead of returning empty 500s
      if (err instanceof Response) {
        const body = await err
          .clone()
          .text()
          .catch(() => '');
        console.error('[auth] better-auth threw Response:', err.status, body);
        return err;
      }
      // Anything that isn't a Response is an unhandled exception — log the
      // path, message, and stack so the next failure isn't an opaque 500.
      console.error('[auth] unhandled exception in better-auth handler', {
        path: authPath,
        error: err instanceof Error ? err.message : String(err),
        stack: err instanceof Error ? err.stack : undefined,
      });
      // Surface a JSON 500 instead of letting it bubble out as an empty body.
      return c.json(
        {
          error: 'Internal Server Error',
          message: err instanceof Error ? err.message : 'Unknown error',
          path: authPath,
        },
        500,
      );
    }
  })
  .use(
    '/trpc/*',
    trpcServer({
      // `fetchRequestHandler` strips `endpoint` from the *full* request pathname
      // (`new URL(req.url).pathname`), e.g. `/api/trpc/meet.listMeetings` → remainder
      // must be `meet.listMeetings`. With `endpoint: '/trpc'` the remainder became
      // `trpc/meet...` and every procedure 404’d. The prefix to strip is `/api/trpc`.
      endpoint: '/api/trpc',
      router: appRouter,
      createContext: (_, c) => {
        return { c, auth: c.var['auth'], sessionUser: c.var['sessionUser'], db: c.var['db'] };
      },
      allowMethodOverride: true,
      onError: (opts) => {
        console.error('Error in TRPC handler:', opts.error);
      },
    }),
  )
  .onError(async (err, c) => {
    if (err instanceof Response) return err;
    console.error('Error in Hono handler:', err);
    return c.json(
      {
        error: 'Internal Server Error',
        message: err instanceof Error ? err.message : 'Unknown error',
      },
      500,
    );
  });

const app = new Hono<HonoContext>()
  .use(
    '*',
    cors({
      origin: (origin) => {
        if (!origin) return null;
        let hostname: string;
        try {
          hostname = new URL(origin).hostname;
        } catch {
          return null;
        }
        // Hardcoded fallback domains to ensure CORS works even if env.COOKIE_DOMAIN
        // isn't populated yet (Cloudflare Workers static env timing edge case).
        const allowedDomains = ['todus.app', 'localhost'];
        const cookieDomain = env.COOKIE_DOMAIN;
        if (cookieDomain && !allowedDomains.includes(cookieDomain)) {
          allowedDomains.push(cookieDomain);
        }
        for (const domain of allowedDomains) {
          if (hostname === domain || hostname.endsWith('.' + domain)) {
            return origin;
          }
        }
        return null;
      },
      credentials: true,
      allowHeaders: ['Content-Type', 'Authorization'],
      exposeHeaders: ['X-Zero-Redirect'],
    }),
  )
  .get('.well-known/oauth-authorization-server', async (c) => {
    const auth = createAuth();
    return oAuthDiscoveryMetadata(auth)(c.req.raw);
  })
  .mount(
    '/sse',
    async (request, env, ctx) => {
      const authBearer = request.headers.get('Authorization');
      if (!authBearer) {
        console.log('No auth provided');
        return new Response('Unauthorized', { status: 401 });
      }
      const auth = createAuth();
      const session = await auth.api.getMcpSession({ headers: request.headers });
      if (!session) {
        console.log('Invalid auth provided', Array.from(request.headers.entries()));
        return new Response('Unauthorized', { status: 401 });
      }
      ctx.props = {
        userId: session?.userId,
      };
      return ZeroMCP.serveSSE('/sse', { binding: 'ZERO_MCP' }).fetch(request, env, ctx);
    },
    { replaceRequest: false },
  )
  .mount(
    '/mcp/thinking/sse',
    async (request, env, ctx) => {
      return ThinkingMCP.serveSSE('/mcp/thinking/sse', { binding: 'THINKING_MCP' }).fetch(
        request,
        env,
        ctx,
      );
    },
    { replaceRequest: false },
  )
  .mount(
    '/mcp',
    async (request, env, ctx) => {
      const authBearer = request.headers.get('Authorization');
      if (!authBearer) {
        return new Response('Unauthorized', { status: 401 });
      }
      const auth = createAuth();
      const session = await auth.api.getMcpSession({ headers: request.headers });
      if (!session) {
        console.log('Invalid auth provided', Array.from(request.headers.entries()));
        return new Response('Unauthorized', { status: 401 });
      }
      ctx.props = {
        userId: session?.userId,
      };
      return ZeroMCP.serve('/mcp', { binding: 'ZERO_MCP' }).fetch(request, env, ctx);
    },
    { replaceRequest: false },
  )
  .route('/api', api)
  // Recall.ai webhooks must be outside /api — they have no session cookie/token
  .route('/webhooks/recall', recallWebhookRouter)
  // Autumn webhooks: same reason — Autumn calls us server-to-server, no auth.
  .route('/webhooks/autumn', autumnWebhookRouter)
  .use(
    '*',
    agentsMiddleware({
      options: {
        onBeforeConnect: (c) => {
          if (!c.headers.get('Cookie')) {
            return new Response('Unauthorized', { status: 401 });
          }
        },
      },
    }),
  )
  .get('/health', (c) => c.json({ message: 'Todus Server is Up!' }))
  // One-shot admin endpoint. Production DB lives behind Hyperdrive and the
  // direct connection string isn't available locally for `drizzle-kit migrate`,
  // so this runs SQL via the same HYPERDRIVE binding the worker uses. Gated by
  // a single-use token. REMOVE after use.
  //
  // Modes:
  //   POST /admin/run-migrations           → apply schema fixes
  //   POST /admin/run-migrations?mode=info → describe current DB schema
  .post('/admin/run-migrations', async (c) => {
    const ONE_SHOT_TOKEN = 'f9864a95de7160e0c2e0b6afb15b53b12c17bfb44e4aa2ea6810fdb473ccf7d2';
    const auth = c.req.header('Authorization');
    const expected = `Bearer ${ONE_SHOT_TOKEN}`;
    if (!auth || auth !== expected) {
      return c.json({ error: 'unauthorized' }, 401);
    }

    const mode = new URL(c.req.url).searchParams.get('mode') ?? 'apply';
    const { conn } = createDb(env.HYPERDRIVE.connectionString);

    try {
      if (mode === 'info') {
        // Inspect what's actually in the production DB so we know which
        // migrations are missing.
        const tables =
          await conn`SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'mail0_%' ORDER BY tablename`;
        const userColumns =
          await conn`SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'mail0_user' ORDER BY ordinal_position`;
        const accountColumns =
          await conn`SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'mail0_account' ORDER BY ordinal_position`;
        const sessionColumns =
          await conn`SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'mail0_session' ORDER BY ordinal_position`;
        return c.json({
          ok: true,
          mode: 'info',
          tables: tables.map((t: { tablename: string }) => t.tablename),
          mail0_user_columns: userColumns,
          mail0_account_columns: accountColumns,
          mail0_session_columns: sessionColumns,
        });
      }

      // 0050 columns on mail0_user — use IF NOT EXISTS for idempotence.
      const statements: Array<{ label: string; sql: string }> = [
        {
          label: '0050: mail0_user.plan',
          sql: `ALTER TABLE "mail0_user" ADD COLUMN IF NOT EXISTS "plan" text DEFAULT 'free' NOT NULL`,
        },
        {
          label: '0050: mail0_user.subscription_status',
          sql: `ALTER TABLE "mail0_user" ADD COLUMN IF NOT EXISTS "subscription_status" text DEFAULT 'active' NOT NULL`,
        },
        {
          label: '0050: mail0_user.ai_usage_used',
          sql: `ALTER TABLE "mail0_user" ADD COLUMN IF NOT EXISTS "ai_usage_used" double precision DEFAULT 0 NOT NULL`,
        },
        {
          label: '0050: mail0_user.ai_usage_limit',
          sql: `ALTER TABLE "mail0_user" ADD COLUMN IF NOT EXISTS "ai_usage_limit" double precision DEFAULT 0 NOT NULL`,
        },
        {
          label: '0050: mail0_user.ai_usage_reset_at',
          sql: `ALTER TABLE "mail0_user" ADD COLUMN IF NOT EXISTS "ai_usage_reset_at" timestamp`,
        },
      ];

      const results: Array<{ statement: string; ok: boolean; error?: string }> = [];
      for (const stmt of statements) {
        try {
          await conn.unsafe(stmt.sql);
          results.push({ statement: stmt.label, ok: true });
          console.log(`[admin/run-migrations] applied: ${stmt.label}`);
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          results.push({ statement: stmt.label, ok: false, error: message });
          console.error(`[admin/run-migrations] failed: ${stmt.label}`, message);
        }
      }

      const allOk = results.every((r) => r.ok);
      return c.json({ ok: allOk, results }, allOk ? 200 : 207);
    } finally {
      await conn.end();
    }
  })
  .get('/', (c) => c.redirect(`${env.VITE_PUBLIC_APP_URL}`))
  .post('/monitoring/sentry', async (c) => {
    try {
      const envelopeBytes = await c.req.arrayBuffer();
      const envelope = new TextDecoder().decode(envelopeBytes);
      const piece = envelope.split('\n')[0];
      const header = JSON.parse(piece);
      const dsn = new URL(header['dsn']);
      const project_id = dsn.pathname?.replace('/', '');

      if (dsn.hostname !== SENTRY_HOST) {
        throw new Error(`Invalid sentry hostname: ${dsn.hostname}`);
      }

      if (!project_id || !SENTRY_PROJECT_IDS.has(project_id)) {
        throw new Error(`Invalid sentry project id: ${project_id}`);
      }

      const upstream_sentry_url = `https://${SENTRY_HOST}/api/${project_id}/envelope/`;
      await fetch(upstream_sentry_url, {
        method: 'POST',
        body: envelopeBytes,
      });

      return c.json({}, { status: 200 });
    } catch (e) {
      console.error('error tunneling to sentry', e);
      return c.json({ error: 'error tunneling to sentry' }, { status: 500 });
    }
  })
  .post('/a8n/notify/:providerId', async (c) => {
    const tracer = initTracing();
    const span = tracer.startSpan('a8n_notify', {
      attributes: {
        'provider.id': c.req.param('providerId'),
        'notification.type': 'email_notification',
        'http.method': c.req.method,
        'http.url': c.req.url,
      },
    });

    try {
      if (!c.req.header('Authorization')) {
        span.setAttributes({ 'auth.status': 'missing' });
        return c.json({ error: 'Unauthorized' }, { status: 401 });
      }
      if (env.DISABLE_WORKFLOWS === 'true') {
        span.setAttributes({ 'workflows.disabled': true });
        return c.json({ message: 'OK' }, { status: 200 });
      }
      const providerId = c.req.param('providerId');
      if (providerId === EProviders.google) {
        const body = await c.req.json<{ historyId: string }>();
        const subHeader = c.req.header('x-goog-pubsub-subscription-name');

        span.setAttributes({
          'history.id': body.historyId,
          'subscription.name': subHeader || 'missing',
        });

        if (!subHeader) {
          console.log('[GOOGLE] no subscription header', body);
          span.setAttributes({ 'error.type': 'missing_subscription_header' });
          return c.json({}, { status: 200 });
        }
        const isValid = await verifyToken(c.req.header('Authorization')!.split(' ')[1]);
        if (!isValid) {
          console.log('[GOOGLE] invalid request', body);
          span.setAttributes({ 'auth.status': 'invalid' });
          return c.json({}, { status: 200 });
        }

        span.setAttributes({ 'auth.status': 'valid' });

        try {
          await env.thread_queue.send({
            providerId,
            historyId: body.historyId,
            subscriptionName: subHeader,
          });
          span.setAttributes({ 'queue.message_sent': true });
        } catch (error) {
          console.error('Error sending to thread queue', error, {
            providerId,
            historyId: body.historyId,
            subscriptionName: subHeader,
          });
          span.recordException(error as Error);
          span.setStatus({ code: 2, message: (error as Error).message });
        }
        return c.json({ message: 'OK' }, { status: 200 });
      }
    } catch (error) {
      span.recordException(error as Error);
      span.setStatus({ code: 2, message: (error as Error).message });
      throw error;
    } finally {
      span.end();
    }
  });
const handler = {
  async fetch(request: Request, env: ZeroEnv, ctx: ExecutionContext): Promise<Response> {
    setEnv(env);
    return app.fetch(request, env, ctx);
  },
};

// const config: ResolveConfigFn = (env: ZeroEnv) => {
//   return {
//     exporter: {
//       url: env.OTEL_EXPORTER_OTLP_ENDPOINT || 'https://api.axiom.co/v1/traces',
//       headers: env.OTEL_EXPORTER_OTLP_HEADERS
//         ? Object.fromEntries(
//             env.OTEL_EXPORTER_OTLP_HEADERS.split(',').map((header: string) => {
//               const [key, value] = header.split('=');
//               return [key.trim(), value.trim()];
//             }),
//           )
//         : {},
//     },
//     service: {
//       name: env.OTEL_SERVICE_NAME || 'todus-email-server',
//       version: '1.0.0',
//     },
//   };
// };

export default class Entry extends WorkerEntrypoint<ZeroEnv> {
  async fetch(request: Request): Promise<Response> {
    return handler.fetch(request, this.env, this.ctx);
  }
  async queue(
    batch: MessageBatch<unknown> | { queue: string; messages: Array<{ body: IEmailSendBatch }> },
  ) {
    setEnv(this.env);
    switch (true) {
      case batch.queue.startsWith('subscribe-queue'): {
        console.log('batch', batch);
        await Promise.all(
          batch.messages.map(async (msg: any) => {
            const connectionId = msg.body.connectionId;
            const providerId = msg.body.providerId;
            try {
              await enableBrainFunction({ id: connectionId, providerId });
            } catch (error) {
              console.error(
                `Failed to enable brain function for connection ${connectionId}:`,
                error,
              );
            }
          }),
        );
        console.log('[SUBSCRIBE_QUEUE] batch done');
        return;
      }
      case batch.queue.startsWith('send-email-queue'): {
        await Promise.all(
          batch.messages.map(async (msg: any) => {
            const { messageId, connectionId, mail } = msg.body;
            const { pending_emails_status: statusKV, pending_emails_payload: payloadKV } = this
              .env as { pending_emails_status: KVNamespace; pending_emails_payload: KVNamespace };

            try {
              const status = await statusKV.get(messageId);
              if (status === 'cancelled') {
                console.log(`Email ${messageId} cancelled – skipping send.`);
                return;
              }

              let payload = mail;
              if (!payload) {
                const stored = await payloadKV.get(messageId);
                if (!stored) {
                  console.error(`No payload found for scheduled email ${messageId}`);
                  return;
                }
                payload = JSON.parse(stored);
              }

              const agent = await getZeroAgent(connectionId, this.ctx);

              if (Array.isArray((payload as any).attachments)) {
                const attachments = (payload as any).attachments;

                const processedAttachments = await Promise.all(
                  attachments.map(
                    async (att: SerializedAttachment | AttachmentFile, index: number) => {
                      if ('arrayBuffer' in att && typeof att.arrayBuffer === 'function') {
                        return { attachment: att as AttachmentFile, index };
                      } else {
                        const processed = toAttachmentFiles([att as SerializedAttachment]);
                        return { attachment: processed[0], index };
                      }
                    },
                  ),
                );

                const orderedAttachments = Array.from({ length: attachments.length });
                processedAttachments.forEach(({ attachment, index }) => {
                  orderedAttachments[index] = attachment;
                });

                (payload as any).attachments = orderedAttachments;
              }

              if ('draftId' in (payload as any) && (payload as any).draftId) {
                const { draftId, ...rest } = payload as any;
                await agent.stub.sendDraft(draftId, rest as any);
              } else {
                await agent.stub.create(payload as any);
              }

              await statusKV.delete(messageId);
              await payloadKV.delete(messageId);
              console.log(`Email ${messageId} sent successfully`);
            } catch (error) {
              console.error(`Failed to send scheduled email ${messageId}:`, error);
              await statusKV.delete(messageId);
              await payloadKV.delete(messageId);
            }
          }),
        );
        return;
      }
      case batch.queue.startsWith('thread-queue'): {
        const tracer = initTracing();

        await Promise.all(
          batch.messages.map(async (msg: any) => {
            const span = tracer.startSpan('thread_queue_processing', {
              attributes: {
                'provider.id': msg.body.providerId,
                'history.id': msg.body.historyId,
                'subscription.name': msg.body.subscriptionName,
                'queue.name': batch.queue,
              },
            });

            try {
              const providerId = msg.body.providerId;
              const historyId = msg.body.historyId;
              const subscriptionName = msg.body.subscriptionName;

              const workflowRunner = env.WORKFLOW_RUNNER.get(env.WORKFLOW_RUNNER.newUniqueId());
              const result = await workflowRunner.runMainWorkflow({
                providerId,
                historyId,
                subscriptionName,
              });
              console.log('[THREAD_QUEUE] result', result);
              span.setAttributes({
                'workflow.result': typeof result === 'string' ? result : JSON.stringify(result),
                'workflow.success': true,
              });
            } catch (error) {
              console.error('Error running workflow', error);
              span.recordException(error as Error);
              span.setStatus({ code: 2, message: (error as Error).message });
            } finally {
              span.end();
            }
          }),
        );
        break;
      }
    }
  }
  async scheduled() {
    setEnv(this.env);
    console.log('Running scheduled tasks...');

    await this.processScheduledEmails();

    await this.processExpiredSubscriptions();
  }

  private async processScheduledEmails() {
    console.log('Checking for scheduled emails ready to be queued...');
    const { scheduled_emails: scheduledKV, send_email_queue } = this.env as {
      scheduled_emails: KVNamespace;
      send_email_queue: Queue<IEmailSendBatch>;
    };

    try {
      const now = Date.now();
      const twelveHoursFromNow = now + 12 * 60 * 60 * 1000;

      let cursor: string | undefined = undefined;
      const batchSize = 1000;

      do {
        const listResp: {
          keys: { name: string }[];
          cursor?: string;
        } = await scheduledKV.list({ cursor, limit: batchSize });
        cursor = listResp.cursor;

        for (const key of listResp.keys) {
          try {
            const scheduledData = await scheduledKV.get(key.name);
            if (!scheduledData) continue;

            const { messageId, connectionId, sendAt } = JSON.parse(scheduledData);

            if (sendAt <= twelveHoursFromNow) {
              const delaySeconds = Math.max(0, Math.floor((sendAt - now) / 1000));

              console.log(`Queueing scheduled email ${messageId} with ${delaySeconds}s delay`);

              const queueBody: IEmailSendBatch = {
                messageId,
                connectionId,
                sendAt,
              };

              await send_email_queue.send(queueBody, { delaySeconds });
              await scheduledKV.delete(key.name);

              console.log(`Successfully queued scheduled email ${messageId}`);
            }
          } catch (error) {
            console.error('Failed to process scheduled email key', key.name, error);
          }
        }
      } while (cursor);
    } catch (error) {
      console.error('Error processing scheduled emails:', error);
    }
  }

  private async processExpiredSubscriptions() {
    console.log('[SCHEDULED] Checking for expired subscriptions...');
    const { db, conn } = createDb(this.env.HYPERDRIVE.connectionString);
    const allAccounts = await db.query.connection.findMany({
      where: (fields, { isNotNull, and }) =>
        and(isNotNull(fields.accessToken), isNotNull(fields.refreshToken)),
    });
    await conn.end();
    console.log('[SCHEDULED] allAccounts', allAccounts.length);
    const now = new Date();
    const fiveDaysAgo = new Date(now.getTime() - 5 * 24 * 60 * 60 * 1000);

    const expiredSubscriptions: Array<{ connectionId: string; providerId: EProviders }> = [];

    const nowTs = Date.now();

    const unsnoozeMap: Record<string, { threadIds: string[]; keyNames: string[] }> = {};

    let cursor: string | undefined = undefined;
    do {
      const listResp: {
        keys: { name: string; metadata?: { wakeAt?: string } }[];
        cursor?: string;
      } = await this.env.snoozed_emails.list({ cursor, limit: 1000 });
      cursor = listResp.cursor;

      for (const key of listResp.keys) {
        try {
          const wakeAtIso = key.metadata?.wakeAt as string | undefined;
          if (!wakeAtIso) continue;
          const wakeAt = new Date(wakeAtIso).getTime();
          if (wakeAt > nowTs) continue;

          const [threadId, connectionId] = key.name.split('__');
          if (!threadId || !connectionId) continue;

          if (!unsnoozeMap[connectionId]) {
            unsnoozeMap[connectionId] = { threadIds: [], keyNames: [] };
          }
          unsnoozeMap[connectionId].threadIds.push(threadId);
          unsnoozeMap[connectionId].keyNames.push(key.name);
        } catch (error) {
          console.error('Failed to prepare unsnooze for key', key.name, error);
        }
      }
    } while (cursor);

    // await Promise.all(
    //   Object.entries(unsnoozeMap).map(async ([connectionId, { threadIds, keyNames }]) => {
    //     try {
    //       const { stub: agent } = await getZeroAgent(connectionId, this.ctx);
    //       await agent.queue('unsnoozeThreadsHandler', { connectionId, threadIds, keyNames });
    //     } catch (error) {
    //       console.error('Failed to enqueue unsnooze tasks', { connectionId, threadIds, error });
    //     }
    //   }),
    // );

    await Promise.all(
      allAccounts.map(async ({ id, providerId }) => {
        const lastSubscribed = await this.env.gmail_sub_age.get(`${id}__${providerId}`);

        if (lastSubscribed) {
          const subscriptionDate = new Date(lastSubscribed);
          if (subscriptionDate < fiveDaysAgo) {
            console.log(`[SCHEDULED] Found expired Google subscription for connection: ${id}`);
            expiredSubscriptions.push({ connectionId: id, providerId: providerId as EProviders });
          }
        } else {
          expiredSubscriptions.push({ connectionId: id, providerId: providerId as EProviders });
        }
      }),
    );

    // Send expired subscriptions to queue for renewal
    if (expiredSubscriptions.length > 0) {
      console.log(
        `[SCHEDULED] Sending ${expiredSubscriptions.length} expired subscriptions to renewal queue`,
      );
      await Promise.all(
        expiredSubscriptions.map(async ({ connectionId, providerId }) => {
          await this.env.subscribe_queue.send({ connectionId, providerId });
        }),
      );
    }

    console.log(
      `[SCHEDULED] Processed ${allAccounts.keys.length} accounts, found ${expiredSubscriptions.length} expired subscriptions`,
    );
  }
}

export {
  ZeroAgent,
  ZeroMCP,
  ZeroDB,
  ZeroDriver,
  ThinkingMCP,
  WorkflowRunner,
  ThreadSyncWorker,
  SyncThreadsWorkflow,
  SyncThreadsCoordinatorWorkflow,
  ShardRegistry,
};
