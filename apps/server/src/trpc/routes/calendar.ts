/**
 * Google Calendar tRPC router.
 *
 * Uses the user's stored Google OAuth refresh token to call the
 * Google Calendar REST API v3 directly (no extra npm package needed —
 * `google-auth-library`'s OAuth2Client already handles auto-refresh).
 *
 * Exposed procedures:
 *   calendar.events — list events for a given time window
 *   calendar.calendars — list the user's calendar list (for multi-cal support)
 *   calendar.eventsMulti — list events across multiple connections in parallel
 *   calendar.createEvent / updateEvent / deleteEvent — write operations
 */
import { activeConnectionProcedure, multiConnectionProcedure, router } from '../trpc';
import { OAuth2Client } from 'google-auth-library';
import { TRPCError } from '@trpc/server';
import { env } from '../../env';
import { z } from 'zod';
import { getZeroDB } from '../../lib/server-utils';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Returns a fresh OAuth2Client pre-loaded with the connection's refresh token.
 * Calling `getAccessToken()` on the returned client will auto-refresh if needed.
 */
export function buildAuthClient(refreshToken: string): OAuth2Client {
  const auth = new OAuth2Client(env.GOOGLE_CLIENT_ID, env.GOOGLE_CLIENT_SECRET);
  auth.setCredentials({ refresh_token: refreshToken });
  return auth;
}

/**
 * Wraps a Google Calendar REST fetch with auth.
 * Throws TRPC UNAUTHORIZED if the connection has no refresh token,
 * or INTERNAL_SERVER_ERROR on fetch failures.
 */
/** Returned when the user's Google token lacks the `calendar.readonly` scope. */
export class CalendarScopeMissingError extends Error {
  constructor() { super('Calendar scope missing'); }
}

async function calendarFetch<T>(
  auth: OAuth2Client,
  path: string,
  params: Record<string, string> = {},
): Promise<T> {
  const { token } = await auth.getAccessToken();
  if (!token) throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Could not refresh Google token' });

  const url = new URL(`https://www.googleapis.com/calendar/v3${path}`);
  for (const [k, v] of Object.entries(params)) {
    url.searchParams.set(k, v);
  }

  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!res.ok) {
    if (res.status === 401) throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Google Calendar access denied' });
    // 403 typically means the token doesn't have the calendar scope yet
    // (user authenticated before we added calendar.readonly). Signal this specially
    // so the caller can prompt a re-auth rather than surfacing a generic error.
    if (res.status === 403) throw new CalendarScopeMissingError();
    throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: `Google Calendar API error: ${res.status}` });
  }

  return res.json() as Promise<T>;
}

/**
 * Wraps a Google Calendar REST mutation (POST/PATCH/DELETE).
 * Same auth + 401/403 handling as `calendarFetch`, but takes a method and JSON body.
 */
export async function calendarFetchJSON<T>(
  auth: OAuth2Client,
  path: string,
  options: {
    method: 'POST' | 'PATCH' | 'DELETE' | 'PUT';
    body?: unknown;
    params?: Record<string, string>;
  },
): Promise<T | null> {
  const { token } = await auth.getAccessToken();
  if (!token) throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Could not refresh Google token' });

  const url = new URL(`https://www.googleapis.com/calendar/v3${path}`);
  for (const [k, v] of Object.entries(options.params ?? {})) {
    url.searchParams.set(k, v);
  }

  const res = await fetch(url.toString(), {
    method: options.method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });

  if (!res.ok) {
    if (res.status === 401) throw new TRPCError({ code: 'UNAUTHORIZED', message: 'Google Calendar access denied' });
    if (res.status === 403) throw new CalendarScopeMissingError();
    if (res.status === 404) throw new TRPCError({ code: 'NOT_FOUND', message: 'Calendar event not found' });
    const errorBody = await res.text().catch(() => '');
    throw new TRPCError({
      code: 'INTERNAL_SERVER_ERROR',
      message: `Google Calendar API error: ${res.status} ${errorBody}`,
    });
  }

  // DELETE returns 204 no content
  if (res.status === 204) return null;
  return res.json() as Promise<T>;
}

// ─── Types ────────────────────────────────────────────────────────────────────

interface GCalEvent {
  id: string;
  summary?: string;
  description?: string;
  location?: string;
  start: { dateTime?: string; date?: string; timeZone?: string };
  end: { dateTime?: string; date?: string; timeZone?: string };
  status?: string;
  htmlLink?: string;
  colorId?: string;
  organizer?: { email: string; displayName?: string; self?: boolean };
  attendees?: { email: string; displayName?: string; responseStatus?: string }[];
}

interface GCalEventsResponse {
  items: GCalEvent[];
  nextPageToken?: string;
  summary?: string;
  timeZone?: string;
}

interface GCalCalendar {
  id: string;
  summary: string;
  description?: string;
  backgroundColor?: string;
  foregroundColor?: string;
  primary?: boolean;
  accessRole: string;
}

interface GCalCalendarListResponse {
  items: GCalCalendar[];
}

// Google's colorId → hex mapping (background colors)
const GOOGLE_CALENDAR_COLORS: Record<string, string> = {
  '1': '#a4bdfc', '2': '#7ae7bf', '3': '#dbadff', '4': '#ff887c',
  '5': '#fbd75b', '6': '#ffb878', '7': '#46d6db', '8': '#e1e1e1',
  '9': '#5484ed', '10': '#51b749', '11': '#dc2127',
};

// ─── Router ───────────────────────────────────────────────────────────────────

export const calendarRouter = router({
  /**
   * List calendar events for a time window.
   * Uses the Google Calendar API `events.list` endpoint on the primary calendar.
   * Falls back to listing all active calendars if the primary calendar scope
   * doesn't cover all events.
   */
  events: activeConnectionProcedure
    .input(
      z.object({
        /** ISO 8601 datetime string — start of range */
        timeMin: z.string(),
        /** ISO 8601 datetime string — end of range */
        timeMax: z.string(),
        /** Optional calendar ID — defaults to "primary" */
        calendarId: z.string().optional().default('primary'),
        /** Max results to return per calendar (capped at 250 by Google) */
        maxResults: z.number().min(1).max(250).optional().default(100),
      }),
    )
    .query(async ({ ctx, input }) => {
      const { activeConnection } = ctx;

      // Only Google connections have Calendar API access
      if (activeConnection.providerId !== 'google') {
        return { events: [], scopeMissing: false };
      }

      if (!activeConnection.refreshToken) {
        throw new TRPCError({ code: 'UNAUTHORIZED', message: 'No refresh token available' });
      }

      const auth = buildAuthClient(activeConnection.refreshToken);

      let data: GCalEventsResponse;
      try {
        data = await calendarFetch<GCalEventsResponse>(
          auth,
          `/calendars/${encodeURIComponent(input.calendarId)}/events`,
          {
            timeMin: input.timeMin,
            timeMax: input.timeMax,
            maxResults: String(input.maxResults),
            singleEvents: 'true',      // expand recurring events into instances
            orderBy: 'startTime',
          },
        );
      } catch (err) {
        // Token lacks calendar.readonly — tell the frontend to prompt a re-auth
        if (err instanceof CalendarScopeMissingError) return { events: [], scopeMissing: true };
        throw err;
      }

      const events = (data.items ?? [])
        .filter((e) => e.status !== 'cancelled')
        .flatMap((e) => {
          const startTime = e.start.dateTime ?? e.start.date;
          const endTime = e.end.dateTime ?? e.end.date;
          if (!startTime || !endTime) {
            console.warn('[calendar.events] Skipping event with missing bounds', {
              id: e.id,
              summary: e.summary,
            });
            return [];
          }

          return [{
            id: e.id,
            title: e.summary ?? '(No title)',
            description: e.description ?? null,
            location: e.location ?? null,
            // All-day events use `date` (no time); timed events use `dateTime`
            startTime,
            endTime,
            allDay: !e.start.dateTime,
            color: e.colorId ? (GOOGLE_CALENDAR_COLORS[e.colorId] ?? '#5484ed') : '#5484ed',
            htmlLink: e.htmlLink ?? null,
            organizer: e.organizer?.displayName ?? e.organizer?.email ?? null,
            isOrganizer: e.organizer?.self ?? false,
          }];
        });

      return { events, scopeMissing: false };
    }),

  /**
   * List the user's Google Calendar list (for multi-calendar display).
   * Returns only calendars the user can read.
   */
  calendars: activeConnectionProcedure
    .input(
      z
        .object({
          // When set, list calendars for this specific connection instead of the
          // user's default — required so multi-account clients can fetch (and
          // correctly label) each Google account's calendars. Omitted = default
          // connection (backward compatible; the web client passes no input).
          connectionId: z.string().optional(),
        })
        .optional(),
    )
    .query(async ({ ctx, input }) => {
      const { activeConnection } = ctx;

      // Resolve the target connection. `findUserConnection` is user-scoped, so a
      // client can only ever read its own connections (no IDOR).
      let targetConnection = activeConnection;
      if (input?.connectionId && input.connectionId !== activeConnection.id) {
        const db = await getZeroDB(ctx.sessionUser.id);
        const found = await db.findUserConnection(input.connectionId);
        if (found) targetConnection = found;
      }

      if (targetConnection.providerId !== 'google') {
        return { calendars: [], scopeMissing: false };
      }

      if (!targetConnection.refreshToken) {
        throw new TRPCError({ code: 'UNAUTHORIZED', message: 'No refresh token available' });
      }

      const auth = buildAuthClient(targetConnection.refreshToken);

    let data: GCalCalendarListResponse;
    try {
      data = await calendarFetch<GCalCalendarListResponse>(
        auth,
        '/users/me/calendarList',
        { minAccessRole: 'reader', maxResults: '50' },
      );
    } catch (err) {
      if (err instanceof CalendarScopeMissingError) return { calendars: [], scopeMissing: true };
      throw err;
    }

    const calendars = (data.items ?? []).map((c) => ({
      id: c.id,
      name: c.summary,
      color: c.backgroundColor ?? '#5484ed',
      primary: c.primary ?? false,
    }));

    return { calendars, scopeMissing: false };
  }),

  /** Fetch calendar events from ALL connections in parallel — for unified calendar view */
  eventsMulti: multiConnectionProcedure
    .input(
      z.object({
        timeMin: z.string(),
        timeMax: z.string(),
        /** Default calendar id used when a connection has no per-connection list in `calendarIds` */
        calendarId: z.string().optional().default('primary'),
        maxResults: z.number().min(1).max(250).optional().default(100),
        /** Filter to specific connection IDs (omit for all) */
        connectionIds: z.array(z.string()).optional(),
        /**
         * Per-connection list of calendar IDs to fetch from.
         * Map of `connectionId -> string[]`. Connections not present in the map
         * fall back to fetching only from `calendarId` (default 'primary').
         * Pass an empty array to skip a connection entirely.
         */
        calendarIds: z.record(z.string(), z.array(z.string())).optional(),
      }),
    )
    .query(async ({ ctx, input }) => {
      const { connections } = ctx;

      // Filter to requested connections, or use all
      const targetConnections = input.connectionIds
        ? connections.filter((c) => input.connectionIds!.includes(c.id))
        : connections;

      // Only Google connections support Calendar API
      const googleConnections = targetConnections.filter(
        (c) => c.providerId === 'google' && c.refreshToken,
      );

      // Build the calendar list to fetch per connection. Default to the input's
      // `calendarId` (typically 'primary') if no per-connection list given.
      const buildCalendarList = (connId: string): string[] => {
        const explicit = input.calendarIds?.[connId];
        if (explicit !== undefined) return explicit; // may be empty array → skip
        return [input.calendarId];
      };

      type PerConnResult = {
        connectionId: string;
        connectionEmail: string;
        connectionColor: string | null;
        events: Array<{
          id: string;
          title: string;
          description: string | null;
          location: string | null;
          startTime: string;
          endTime: string;
          allDay: boolean;
          color: string;
          htmlLink: string | null;
          organizer: string | null;
          isOrganizer: boolean;
          calendarId: string;
        }>;
        scopeMissing: boolean;
      };

      const results = await Promise.allSettled(
        googleConnections.map(async (conn): Promise<PerConnResult> => {
          const calendarsToFetch = buildCalendarList(conn.id);
          if (calendarsToFetch.length === 0) {
            return {
              connectionId: conn.id,
              connectionEmail: conn.email,
              connectionColor: conn.color,
              events: [],
              scopeMissing: false,
            };
          }

          const auth = buildAuthClient(conn.refreshToken!);
          let scopeMissing = false;
          const allEvents: PerConnResult['events'] = [];

          // Fetch each calendar sequentially per connection to keep the overall
          // request budget reasonable. Cross-connection parallelism is preserved
          // via the outer Promise.allSettled. A failure on one calendar must not
          // discard events already collected from earlier calendars on the same
          // connection — record the error and continue.
          for (const calendarId of calendarsToFetch) {
            try {
              const data = await calendarFetch<GCalEventsResponse>(
                auth,
                `/calendars/${encodeURIComponent(calendarId)}/events`,
                {
                  timeMin: input.timeMin,
                  timeMax: input.timeMax,
                  maxResults: String(input.maxResults),
                  singleEvents: 'true',
                  orderBy: 'startTime',
                },
              );

              for (const e of data.items ?? []) {
                if (e.status === 'cancelled') continue;
                const startTime = e.start.dateTime ?? e.start.date;
                const endTime = e.end.dateTime ?? e.end.date;
                if (!startTime || !endTime) continue;

                allEvents.push({
                  id: e.id,
                  title: e.summary ?? '(No title)',
                  description: e.description ?? null,
                  location: e.location ?? null,
                  startTime,
                  endTime,
                  allDay: !e.start.dateTime,
                  color: e.colorId ? (GOOGLE_CALENDAR_COLORS[e.colorId] ?? '#5484ed') : '#5484ed',
                  htmlLink: e.htmlLink ?? null,
                  organizer: e.organizer?.displayName ?? e.organizer?.email ?? null,
                  isOrganizer: e.organizer?.self ?? false,
                  calendarId,
                });
              }
            } catch (err) {
              if (err instanceof CalendarScopeMissingError) {
                scopeMissing = true;
                break; // No point trying other calendars on this connection
              }
              // Per-calendar transient failure (e.g. 5xx, 404). Log and keep the
              // partial results from earlier calendars + continue with the rest.
              console.error(
                `[calendar.eventsMulti] connection=${conn.id} calendar=${calendarId} failed:`,
                err,
              );
            }
          }

          return {
            connectionId: conn.id,
            connectionEmail: conn.email,
            connectionColor: conn.color,
            events: allEvents,
            scopeMissing,
          };
        }),
      );

      // Merge results
      const allEvents: Array<{
        id: string; title: string; description: string | null; location: string | null;
        startTime: string; endTime: string; allDay: boolean; color: string;
        htmlLink: string | null; organizer: string | null; isOrganizer: boolean;
        connectionId: string; connectionEmail: string; connectionColor: string | null;
        calendarId: string;
      }> = [];
      const errors: Array<{ connectionId: string; connectionEmail: string; error: string }> = [];
      let anyScopeMissing = false;

      for (const result of results) {
        if (result.status === 'fulfilled') {
          const { connectionId, connectionEmail, connectionColor, events, scopeMissing } = result.value;
          if (scopeMissing) anyScopeMissing = true;
          for (const event of events) {
            allEvents.push({ ...event, connectionId, connectionEmail, connectionColor });
          }
        } else {
          const connIndex = results.indexOf(result);
          const conn = googleConnections[connIndex];
          if (conn) {
            errors.push({
              connectionId: conn.id,
              connectionEmail: conn.email,
              error: result.reason instanceof Error ? result.reason.message : 'Unknown error',
            });
          }
        }
      }

      // Sort by start time
      allEvents.sort((a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime());

      return { events: allEvents, errors, scopeMissing: anyScopeMissing };
    }),

  // ─── Write procedures ──────────────────────────────────────────────────────
  // All three return `{ scopeMissing: true }` instead of throwing when the
  // user's token lacks the new full `calendar` scope, so the iOS / macOS
  // clients can surface a non-blocking "Reconnect to enable editing" banner.

  /** Create an event on a Google calendar. */
  createEvent: activeConnectionProcedure
    .input(
      z.object({
        calendarId: z.string().default('primary'),
        summary: z.string(),
        description: z.string().optional(),
        location: z.string().optional(),
        start: z.object({
          dateTime: z.string().optional(),
          date: z.string().optional(),
          timeZone: z.string().optional(),
        }),
        end: z.object({
          dateTime: z.string().optional(),
          date: z.string().optional(),
          timeZone: z.string().optional(),
        }),
        attendees: z
          .array(
            z.object({
              email: z.string(),
              displayName: z.string().optional(),
            }),
          )
          .optional(),
        colorId: z.string().optional(),
        reminders: z
          .object({
            useDefault: z.boolean().optional(),
            overrides: z
              .array(
                z.object({
                  method: z.enum(['email', 'popup']),
                  minutes: z.number(),
                }),
              )
              .optional(),
          })
          .optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      if (activeConnection.providerId !== 'google') {
        return { scopeMissing: false, event: null };
      }
      if (!activeConnection.refreshToken) {
        throw new TRPCError({ code: 'UNAUTHORIZED', message: 'No refresh token available' });
      }

      const auth = buildAuthClient(activeConnection.refreshToken);
      const { calendarId, ...body } = input;

      try {
        const created = await calendarFetchJSON<GCalEvent>(
          auth,
          `/calendars/${encodeURIComponent(calendarId)}/events`,
          {
            method: 'POST',
            body,
            params: input.attendees && input.attendees.length > 0 ? { sendUpdates: 'all' } : {},
          },
        );
        return { scopeMissing: false, event: created };
      } catch (err) {
        if (err instanceof CalendarScopeMissingError) return { scopeMissing: true, event: null };
        throw err;
      }
    }),

  /** Patch (partial-update) an event. Uses events.patch so unspecified fields are preserved. */
  updateEvent: activeConnectionProcedure
    .input(
      z.object({
        calendarId: z.string().default('primary'),
        eventId: z.string(),
        patch: z.object({
          summary: z.string().optional(),
          description: z.string().optional(),
          location: z.string().optional(),
          start: z
            .object({
              dateTime: z.string().optional(),
              date: z.string().optional(),
              timeZone: z.string().optional(),
            })
            .optional(),
          end: z
            .object({
              dateTime: z.string().optional(),
              date: z.string().optional(),
              timeZone: z.string().optional(),
            })
            .optional(),
          attendees: z
            .array(
              z.object({
                email: z.string(),
                displayName: z.string().optional(),
              }),
            )
            .optional(),
          colorId: z.string().optional(),
        }),
        sendUpdates: z.enum(['all', 'externalOnly', 'none']).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      if (activeConnection.providerId !== 'google') {
        return { scopeMissing: false, event: null };
      }
      if (!activeConnection.refreshToken) {
        throw new TRPCError({ code: 'UNAUTHORIZED', message: 'No refresh token available' });
      }

      const auth = buildAuthClient(activeConnection.refreshToken);

      try {
        const updated = await calendarFetchJSON<GCalEvent>(
          auth,
          `/calendars/${encodeURIComponent(input.calendarId)}/events/${encodeURIComponent(input.eventId)}`,
          {
            method: 'PATCH',
            body: input.patch,
            params: input.sendUpdates ? { sendUpdates: input.sendUpdates } : {},
          },
        );
        return { scopeMissing: false, event: updated };
      } catch (err) {
        if (err instanceof CalendarScopeMissingError) return { scopeMissing: true, event: null };
        throw err;
      }
    }),

  /** Delete an event from a Google calendar. */
  deleteEvent: activeConnectionProcedure
    .input(
      z.object({
        calendarId: z.string().default('primary'),
        eventId: z.string(),
        sendUpdates: z.enum(['all', 'externalOnly', 'none']).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { activeConnection } = ctx;
      if (activeConnection.providerId !== 'google') {
        return { scopeMissing: false, success: false };
      }
      if (!activeConnection.refreshToken) {
        throw new TRPCError({ code: 'UNAUTHORIZED', message: 'No refresh token available' });
      }

      const auth = buildAuthClient(activeConnection.refreshToken);

      try {
        await calendarFetchJSON<null>(
          auth,
          `/calendars/${encodeURIComponent(input.calendarId)}/events/${encodeURIComponent(input.eventId)}`,
          {
            method: 'DELETE',
            params: input.sendUpdates ? { sendUpdates: input.sendUpdates } : {},
          },
        );
        return { scopeMissing: false, success: true };
      } catch (err) {
        if (err instanceof CalendarScopeMissingError) return { scopeMissing: true, success: false };
        throw err;
      }
    }),
});
