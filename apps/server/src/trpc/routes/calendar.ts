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
 */
import { activeConnectionProcedure, router } from '../trpc';
import { OAuth2Client } from 'google-auth-library';
import { TRPCError } from '@trpc/server';
import { env } from '../../env';
import { z } from 'zod';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Returns a fresh OAuth2Client pre-loaded with the connection's refresh token.
 * Calling `getAccessToken()` on the returned client will auto-refresh if needed.
 */
function buildAuthClient(refreshToken: string): OAuth2Client {
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
        .map((e) => ({
          id: e.id,
          title: e.summary ?? '(No title)',
          description: e.description ?? null,
          location: e.location ?? null,
          // All-day events use `date` (no time); timed events use `dateTime`
          startTime: e.start.dateTime ?? e.start.date ?? '',
          endTime: e.end.dateTime ?? e.end.date ?? '',
          allDay: !e.start.dateTime,
          color: e.colorId ? (GOOGLE_CALENDAR_COLORS[e.colorId] ?? '#5484ed') : '#5484ed',
          htmlLink: e.htmlLink ?? null,
          organizer: e.organizer?.displayName ?? e.organizer?.email ?? null,
          isOrganizer: e.organizer?.self ?? false,
        }));

      return { events, scopeMissing: false };
    }),

  /**
   * List the user's Google Calendar list (for multi-calendar display).
   * Returns only calendars the user can read.
   */
  calendars: activeConnectionProcedure.query(async ({ ctx }) => {
    const { activeConnection } = ctx;

    if (activeConnection.providerId !== 'google') {
      return { calendars: [], scopeMissing: false };
    }

    if (!activeConnection.refreshToken) {
      throw new TRPCError({ code: 'UNAUTHORIZED', message: 'No refresh token available' });
    }

    const auth = buildAuthClient(activeConnection.refreshToken);

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
});
