import {
  findLegacyConnections,
  getActiveConnection,
  getZeroDB,
  isMissingConnectionColorError,
  type LegacyConnectionRow,
} from '../../lib/server-utils';
import { createRateLimiterMiddleware, privateProcedure, publicProcedure, router } from '../trpc';
import { Ratelimit } from '@upstash/ratelimit';
import { TRPCError } from '@trpc/server';
import { z } from 'zod';
import { userSettingsSchema } from '../../lib/schemas';

/** Default color palette for multi-account visual differentiation */
const CONNECTION_COLORS = [
  '#007AFF',
  '#34C759',
  '#FF9500',
  '#AF52DE',
  '#FF3B30',
  '#5AC8FA',
  '#A2845E',
  '#FF2D55',
];
const deriveConnectionColor = (connection: { id: string; color: string | null }) => {
  if (connection.color) return connection.color;
  const hash = Array.from(connection.id).reduce((total, char) => total + char.charCodeAt(0), 0);
  return CONNECTION_COLORS[hash % CONNECTION_COLORS.length];
};

async function loadConnectionsWithFallback(userId: string): Promise<LegacyConnectionRow[]> {
  const db = await getZeroDB(userId);
  try {
    return await db.findManyConnections();
  } catch (error) {
    if (!isMissingConnectionColorError(error)) {
      throw error;
    }

    console.warn(
      '[connections.list] Falling back to legacy connection query because mail0_connection.color is missing',
    );

    return await findLegacyConnections(userId);
  }
}

export const connectionsRouter = router({
  list: privateProcedure
    .use(
      createRateLimiterMiddleware({
        limiter: Ratelimit.slidingWindow(120, '1m'),
        generatePrefix: ({ sessionUser }) => `ratelimit:get-connections-${sessionUser?.id}`,
      }),
    )
    .query(async ({ ctx }) => {
      const { sessionUser } = ctx;
      const connections = await loadConnectionsWithFallback(sessionUser.id);

      const disconnectedIds = connections
        .filter((c) => !c.accessToken || !c.refreshToken)
        .map((c) => c.id);

      return {
        connections: connections.map((connection) => {
          return {
            id: connection.id,
            email: connection.email,
            name: connection.name,
            picture: connection.picture,
            createdAt: connection.createdAt,
            providerId: connection.providerId,
            color: deriveConnectionColor(connection),
          };
        }),
        disconnectedIds,
      };
    }),
  setDefault: privateProcedure
    .input(z.object({ connectionId: z.string() }))
    .mutation(async ({ input, ctx }) => {
      const { connectionId } = input;
      const user = ctx.sessionUser;
      const db = await getZeroDB(user.id);
      const foundConnection = await db.findUserConnection(connectionId);
      if (!foundConnection) throw new TRPCError({ code: 'NOT_FOUND' });
      await db.updateUser({ defaultConnectionId: connectionId });
    }),
  delete: privateProcedure
    .input(z.object({ connectionId: z.string() }))
    .mutation(async ({ input, ctx }) => {
      const { connectionId } = input;
      const user = ctx.sessionUser;
      const db = await getZeroDB(user.id);
      const currentUser = await db.findUser();
      const shouldClearDefault = currentUser?.defaultConnectionId === connectionId;
      await db.deleteConnection(connectionId);

      if (shouldClearDefault) {
        await db.updateUser({ defaultConnectionId: null });
      }

      // Sweep stale calendar visibility prefs / default-calendar entries
      // tied to this connection so the settings JSON doesn't grow unbounded
      // and so re-adding the same email doesn't restore a hidden state.
      // We bypass `mergeUserSettings` here because deletion of map keys is
      // not expressible as a merge — we need to write the cleaned object verbatim.
      try {
        const existing: any = await db.findUserSettings();
        if (existing?.settings) {
          const parsed = userSettingsSchema.safeParse(existing.settings);
          if (parsed.success) {
            const prev = parsed.data.calendarPreferences;
            const prefix = `google:${connectionId}:`;
            const accountKey = `google:${connectionId}`;
            const filteredHidden = prev.hiddenCalendarIds.filter((id) => !id.startsWith(prefix));
            const { [accountKey]: _removed, ...remainingDefaults } = prev.defaultCalendarByAccount;
            const cleanedDefault =
              prev.defaultCalendarId?.startsWith(prefix) ? undefined : prev.defaultCalendarId;

            const changed =
              filteredHidden.length !== prev.hiddenCalendarIds.length ||
              Object.keys(remainingDefaults).length !==
                Object.keys(prev.defaultCalendarByAccount).length ||
              cleanedDefault !== prev.defaultCalendarId;

            if (changed) {
              const next = userSettingsSchema.parse({
                ...parsed.data,
                calendarPreferences: {
                  ...prev,
                  hiddenCalendarIds: filteredHidden,
                  defaultCalendarByAccount: remainingDefaults,
                  defaultCalendarId: cleanedDefault,
                },
              });
              await db.updateUserSettings(next);
            }
          }
        }
      } catch (error) {
        // Don't fail the disconnect on settings sweep errors — the connection
        // is already gone, stale prefs are a soft issue.
        console.warn('[connections.delete] Failed to sweep calendar prefs', {
          connectionId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }),
  getDefault: publicProcedure.query(async ({ ctx }) => {
    if (!ctx.sessionUser) return null;
    const connection = await getActiveConnection();
    if (!connection) return null;
    return {
      id: connection.id,
      email: connection.email,
      name: connection.name,
      picture: connection.picture,
      createdAt: connection.createdAt,
      providerId: connection.providerId,
      color: deriveConnectionColor(connection),
    };
  }),
  /** Update a connection's display color */
  updateColor: privateProcedure
    .input(
      z.object({
        connectionId: z.string(),
        color: z.string().regex(/^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/),
      }),
    )
    .mutation(async ({ input, ctx }) => {
      const { connectionId, color } = input;
      const db = await getZeroDB(ctx.sessionUser.id);
      const foundConnection = await db.findUserConnection(connectionId);
      if (!foundConnection) throw new TRPCError({ code: 'NOT_FOUND' });
      await db.updateConnection(connectionId, { color });
    }),
});
