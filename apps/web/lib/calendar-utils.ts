/**
 * Calendar event helpers shared between the Calendar page and CalendarGrid.
 * Centralised so the local-timezone all-day parsing logic exists once — both
 * call sites previously had their own copy, which was a drift hazard.
 */

/**
 * Parse an event's start time as a `Date` in the user's LOCAL timezone.
 *
 * All-day events arrive as bare `YYYY-MM-DD` strings from Google. Calling
 * `new Date("2026-05-17")` parses that as UTC midnight, which is the previous
 * calendar day in every timezone west of UTC (so the event renders on the
 * wrong day for EST/PST users). Splitting the parts and using the `Date(y, m, d)`
 * constructor keeps the result in local time.
 */
export function parseEventStart(event: { startTime: string; allDay?: boolean }): Date {
  if (event.allDay) {
    const [y, m, d] = event.startTime.split('-').map((p) => Number(p));
    if (Number.isFinite(y) && Number.isFinite(m) && Number.isFinite(d)) {
      return new Date(y, (m as number) - 1, d as number);
    }
  }
  return new Date(event.startTime);
}
