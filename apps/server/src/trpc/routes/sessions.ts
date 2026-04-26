import { session, sessionMetadata } from '../../db/schema';
import { and, desc, eq, gt, inArray } from 'drizzle-orm';
import { privateProcedure, router } from '../trpc';
import { createDb } from '../../db';
import { env } from '../../env';
import { z } from 'zod';

const getDb = () => createDb(env.HYPERDRIVE.connectionString);

const isMissingSessionMetadataRelationError = (error: unknown) =>
  error instanceof Error &&
  error.message.includes('relation "mail0_session_metadata" does not exist');

type CloudflareRequest = Request & {
  cf?: {
    city?: string;
    region?: string;
    country?: string;
  };
};

function parseUserAgent(userAgent?: string | null) {
  if (!userAgent) {
    return {
      browserName: 'Unknown',
      osName: 'Unknown',
      deviceType: 'Unknown',
      deviceLabel: 'Unknown device',
    };
  }

  // Detect native Swift/CFNetwork user agents before falling through to
  // browser heuristics. URLSession on iOS/macOS sends strings like:
  //   "Todus/3 CFNetwork/1568.100.1 Darwin/24.0.0"   (iOS / macOS app)
  //   "CFNetwork/1568.100.1 Darwin/24.0.0"            (older builds)
  // Check for the macOS app bundle name first, then fall back to iOS for
  // any other CFNetwork UA (iOS devices are far more common).
  if (/CFNetwork/i.test(userAgent)) {
    const isMacApp = /Todus-Mac|TodusMac/i.test(userAgent);
    const osName = isMacApp ? 'macOS' : 'iOS';
    const deviceType = isMacApp ? 'Desktop' : 'Mobile';
    const deviceLabel = isMacApp ? 'Todus · macOS' : 'Todus · iOS';
    return { browserName: 'Todus', osName, deviceType, deviceLabel };
  }

  const browsers = [
    { name: 'Edge', regex: /Edg\/([0-9.]+)/i },
    { name: 'Chrome', regex: /Chrome\/([0-9.]+)/i },
    { name: 'Firefox', regex: /Firefox\/([0-9.]+)/i },
    { name: 'Safari', regex: /Safari\/([0-9.]+)/i },
  ];

  const operatingSystems = [
    { name: 'iOS', regex: /iPhone|iPad|iPod/i },
    { name: 'Android', regex: /Android/i },
    { name: 'macOS', regex: /Mac OS X/i },
    { name: 'Windows', regex: /Windows NT/i },
    { name: 'Linux', regex: /Linux/i },
  ];

  const deviceType = /iPad|Tablet/i.test(userAgent)
    ? 'Tablet'
    : /Mobile|Android|iPhone/i.test(userAgent)
      ? 'Mobile'
      : /Macintosh|Windows|Linux/i.test(userAgent)
        ? 'Desktop'
        : 'Unknown';

  const browserName = browsers.find((browser) => browser.regex.test(userAgent))?.name ?? 'Unknown';
  const osName = operatingSystems.find((os) => os.regex.test(userAgent))?.name ?? 'Unknown';

  let deviceLabel = `${browserName} · ${osName}`;
  if (deviceType === 'Mobile' && /iPhone/i.test(userAgent)) {
    deviceLabel = 'iPhone · iOS';
  } else if (deviceType === 'Tablet' && /iPad/i.test(userAgent)) {
    deviceLabel = 'iPad · iOS';
  } else if (deviceType === 'Mobile' && /Android/i.test(userAgent)) {
    deviceLabel = 'Android · Mobile';
  } else if (deviceType === 'Desktop') {
    deviceLabel = `${browserName} · ${osName}`;
  }

  return {
    browserName,
    osName,
    deviceType,
    deviceLabel,
  };
}

function formatLocation(parts: {
  city?: string | null;
  region?: string | null;
  country?: string | null;
}) {
  const values = [parts.city, parts.region, parts.country].filter(Boolean);
  return values.length > 0 ? values.join(', ') : 'Unavailable';
}

async function upsertCurrentSessionMetadata(input: {
  userId: string;
  sessionId?: string | null;
  request: Request;
}) {
  if (!input.sessionId) {
    return;
  }

  const request = input.request as CloudflareRequest;
  const userAgent = request.headers.get('user-agent');
  const platform = request.headers.get('x-todus-platform')?.trim().toLowerCase() ?? '';
  let parsed = parseUserAgent(userAgent);
  // Native apps send the same CFNetwork User-Agent on iOS and macOS; prefer explicit platform.
  if (platform === 'macos') {
    parsed = {
      browserName: 'Todus',
      osName: 'macOS',
      deviceType: 'Desktop',
      deviceLabel: 'Todus · macOS',
    };
  } else if (platform === 'ios') {
    parsed = {
      browserName: 'Todus',
      osName: 'iOS',
      deviceType: 'Mobile',
      deviceLabel: 'Todus · iOS',
    };
  }
  const now = new Date();

  const cfCountry = request.headers.get('cf-ipcountry');

  const city = request.cf?.city ?? null;
  const region = request.cf?.region ?? null;
  const country = request.cf?.country ?? cfCountry ?? null;

  const { db, conn } = getDb();
  try {
    await db
      .insert(sessionMetadata)
      .values({
        sessionId: input.sessionId,
        userId: input.userId,
        deviceLabel: parsed.deviceLabel,
        deviceType: parsed.deviceType,
        osName: parsed.osName,
        browserName: parsed.browserName,
        city,
        region,
        country,
        lastSeenAt: now,
        createdAt: now,
        updatedAt: now,
      })
      .onConflictDoUpdate({
        target: sessionMetadata.sessionId,
        set: {
          deviceLabel: parsed.deviceLabel,
          deviceType: parsed.deviceType,
          osName: parsed.osName,
          browserName: parsed.browserName,
          city,
          region,
          country,
          lastSeenAt: now,
          updatedAt: now,
        },
      });
  } catch (error) {
    if (isMissingSessionMetadataRelationError(error)) {
      console.warn(
        '[sessions.upsertCurrentSessionMetadata] Skipping session metadata upsert because mail0_session_metadata is missing',
      );
      return;
    }
    throw error;
  } finally {
    await conn.end();
  }
}

async function resolveCurrentSessionId(input: {
  userId: string;
  auth: {
    api: {
      getSession: (args: {
        headers: Headers;
      }) => Promise<{ session?: { id?: string | null } } | null>;
    };
  };
  request: Request;
}) {
  const authSession = await input.auth.api.getSession({ headers: input.request.headers });
  if (authSession?.session?.id) {
    return authSession.session.id;
  }

  const authHeader = input.request.headers.get('authorization');
  const hintedSessionId = input.request.headers.get('x-todus-session-id');
  // Explicit null/empty check so the Bearer branch below only runs when slice() is safe.
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    if (!hintedSessionId) {
      return null;
    }

    const { db, conn } = getDb();
    try {
      const [activeSession] = await db
        .select({ id: session.id })
        .from(session)
        .where(
          and(
            eq(session.id, hintedSessionId),
            eq(session.userId, input.userId),
            gt(session.expiresAt, new Date()),
          ),
        )
        .limit(1);

      return activeSession?.id ?? null;
    } finally {
      await conn.end();
    }
  }

  const rawToken = authHeader.slice('Bearer '.length).trim();
  if (!rawToken) {
    if (!hintedSessionId) {
      return null;
    }

    const { db, conn } = getDb();
    try {
      const [activeSession] = await db
        .select({ id: session.id })
        .from(session)
        .where(
          and(
            eq(session.id, hintedSessionId),
            eq(session.userId, input.userId),
            gt(session.expiresAt, new Date()),
          ),
        )
        .limit(1);

      return activeSession?.id ?? null;
    } finally {
      await conn.end();
    }
  }

  const { db, conn } = getDb();
  try {
    const [activeSession] = await db
      .select({ id: session.id })
      .from(session)
      .where(and(eq(session.token, rawToken), gt(session.expiresAt, new Date())))
      .limit(1);

    if (activeSession?.id) {
      return activeSession.id;
    }

    if (!hintedSessionId) {
      return null;
    }

    const [hintedSession] = await db
      .select({ id: session.id })
      .from(session)
      .where(
        and(
          eq(session.id, hintedSessionId),
          eq(session.userId, input.userId),
          gt(session.expiresAt, new Date()),
        ),
      )
      .limit(1);

    return hintedSession?.id ?? null;
  } finally {
    await conn.end();
  }
}

export const sessionsRouter = router({
  list: privateProcedure.query(async ({ ctx }) => {
    const currentSessionId = await resolveCurrentSessionId({
      userId: ctx.sessionUser.id,
      auth: ctx.auth,
      request: ctx.c.req.raw,
    });

    await upsertCurrentSessionMetadata({
      userId: ctx.sessionUser.id,
      sessionId: currentSessionId,
      request: ctx.c.req.raw,
    });

    const { db, conn } = getDb();
    try {
      const rows = await db
        .select({
          id: session.id,
          createdAt: session.createdAt,
          updatedAt: session.updatedAt,
          userAgent: session.userAgent,
        })
        .from(session)
        .where(and(eq(session.userId, ctx.sessionUser.id), gt(session.expiresAt, new Date())))
        .orderBy(desc(session.updatedAt), desc(session.createdAt));

      const sessionIds = rows.map((row) => row.id);
      const metadataRows = sessionIds.length
        ? await db
            .select()
            .from(sessionMetadata)
            .where(
              and(
                eq(sessionMetadata.userId, ctx.sessionUser.id),
                inArray(sessionMetadata.sessionId, sessionIds),
              ),
            )
            .catch((error) => {
              if (isMissingSessionMetadataRelationError(error)) {
                console.warn(
                  '[sessions.list] Falling back to session rows without metadata because mail0_session_metadata is missing',
                );
                return [];
              }
              throw error;
            })
        : [];

      const metadataBySessionId = new Map(metadataRows.map((row) => [row.sessionId, row]));

      return {
        sessions: rows.map((row) => {
          const metadata = metadataBySessionId.get(row.id);
          const parsed = parseUserAgent(row.userAgent);

          return {
            id: row.id,
            device: metadata?.deviceLabel ?? parsed.deviceLabel,
            location: formatLocation({
              city: metadata?.city,
              region: metadata?.region,
              country: metadata?.country,
            }),
            createdAt: row.createdAt,
            updatedAt: metadata?.lastSeenAt ?? row.updatedAt,
            isCurrent: currentSessionId === row.id,
          };
        }),
      };
    } finally {
      await conn.end();
    }
  }),

  revoke: privateProcedure
    .input(z.object({ sessionId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const currentSessionId = await resolveCurrentSessionId({
        userId: ctx.sessionUser.id,
        auth: ctx.auth,
        request: ctx.c.req.raw,
      });
      const { db, conn } = getDb();

      try {
        const [deleted] = await db
          .delete(session)
          .where(and(eq(session.id, input.sessionId), eq(session.userId, ctx.sessionUser.id)))
          .returning({ id: session.id });

        return {
          success: !!deleted,
          revokedCurrent: currentSessionId === input.sessionId,
        };
      } finally {
        await conn.end();
      }
    }),

  revokeAll: privateProcedure.mutation(async ({ ctx }) => {
    const currentSessionId = await resolveCurrentSessionId({
      userId: ctx.sessionUser.id,
      auth: ctx.auth,
      request: ctx.c.req.raw,
    });
    const { db, conn } = getDb();

    try {
      const deletedRows = await db
        .delete(session)
        .where(eq(session.userId, ctx.sessionUser.id))
        .returning({ id: session.id });

      return {
        success: true,
        revokedCount: deletedRows.length,
        revokedCurrent:
          !!currentSessionId && deletedRows.some((row) => row.id === currentSessionId),
      };
    } finally {
      await conn.end();
    }
  }),
});
