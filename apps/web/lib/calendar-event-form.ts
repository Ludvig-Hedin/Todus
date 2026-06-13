/**
 * Pure form <-> Google Calendar payload helpers for the web event editor.
 * No React, no tRPC — fully unit-testable. All-day semantics follow Google:
 * `end.date` is EXCLUSIVE, so the UI's inclusive end date is +1 day on write
 * and -1 day on read.
 */
import { addDays, format, parseISO } from 'date-fns';

export interface EventFormValues {
  title: string;
  allDay: boolean;
  startDate: string; // YYYY-MM-DD
  startTime: string; // HH:mm
  endDate: string; // YYYY-MM-DD (inclusive, as shown to the user)
  endTime: string; // HH:mm
  location: string;
  description: string;
}

export interface EventTimePart {
  dateTime?: string;
  date?: string;
  timeZone?: string;
}

const DATE_FMT = 'yyyy-MM-dd';

export function getLocalTimeZone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  } catch {
    return 'UTC';
  }
}

function shiftDateStr(date: string, days: number): string {
  return format(addDays(parseISO(date), days), DATE_FMT);
}

function composeDate(date: string, time: string): Date {
  return new Date(`${date}T${time || '00:00'}`);
}

function toStartPart(v: EventFormValues, tz: string): EventTimePart {
  if (v.allDay) return { date: v.startDate };
  return { dateTime: composeDate(v.startDate, v.startTime).toISOString(), timeZone: tz };
}

function toEndPart(v: EventFormValues, tz: string): EventTimePart {
  if (v.allDay) return { date: shiftDateStr(v.endDate, 1) }; // exclusive
  return { dateTime: composeDate(v.endDate, v.endTime).toISOString(), timeZone: tz };
}

export function validateForm(v: EventFormValues): string | null {
  if (!v.title.trim()) return 'Title is required';
  if (v.allDay) {
    if (composeDate(v.endDate, '00:00') < composeDate(v.startDate, '00:00')) {
      return 'End date must be on or after the start date';
    }
    return null;
  }
  if (composeDate(v.endDate, v.endTime).getTime() <= composeDate(v.startDate, v.startTime).getTime()) {
    return 'End must be after start';
  }
  return null;
}

export function buildCreatePayload(v: EventFormValues, calendarId = 'primary') {
  const tz = getLocalTimeZone();
  return {
    calendarId,
    summary: v.title.trim(),
    description: v.description.trim() || undefined,
    location: v.location.trim() || undefined,
    start: toStartPart(v, tz),
    end: toEndPart(v, tz),
  };
}

export function buildUpdatePatch(v: EventFormValues) {
  const tz = getLocalTimeZone();
  return {
    summary: v.title.trim(),
    description: v.description.trim() || undefined,
    location: v.location.trim() || undefined,
    start: toStartPart(v, tz),
    end: toEndPart(v, tz),
  };
}

export interface EventLike {
  title: string;
  description: string | null;
  location: string | null;
  startTime: string; // ISO datetime OR YYYY-MM-DD (all-day)
  endTime: string;
  allDay: boolean;
}

export function eventToFormValues(e: EventLike): EventFormValues {
  if (e.allDay) {
    return {
      title: e.title === '(No title)' ? '' : e.title,
      allDay: true,
      startDate: e.startTime.slice(0, 10),
      startTime: '00:00',
      endDate: shiftDateStr(e.endTime.slice(0, 10), -1), // exclusive -> inclusive
      endTime: '00:00',
      location: e.location ?? '',
      description: e.description ?? '',
    };
  }
  const start = parseISO(e.startTime);
  const end = parseISO(e.endTime);
  return {
    title: e.title === '(No title)' ? '' : e.title,
    allDay: false,
    startDate: format(start, DATE_FMT),
    startTime: format(start, 'HH:mm'),
    endDate: format(end, DATE_FMT),
    endTime: format(end, 'HH:mm'),
    location: e.location ?? '',
    description: e.description ?? '',
  };
}

export function bumpEndAfterStart(v: EventFormValues): EventFormValues {
  if (v.allDay) {
    if (composeDate(v.endDate, '00:00') < composeDate(v.startDate, '00:00')) {
      return { ...v, endDate: v.startDate };
    }
    return v;
  }
  const start = composeDate(v.startDate, v.startTime);
  const end = composeDate(v.endDate, v.endTime);
  if (end.getTime() <= start.getTime()) {
    const bumped = new Date(start.getTime() + 60 * 60 * 1000);
    return { ...v, endDate: format(bumped, DATE_FMT), endTime: format(bumped, 'HH:mm') };
  }
  return v;
}

export function emptyFormValues(prefill?: { start?: Date; end?: Date; allDay?: boolean }): EventFormValues {
  const start = prefill?.start ?? new Date();
  const end = prefill?.end ?? new Date(start.getTime() + 60 * 60 * 1000);
  return {
    title: '',
    allDay: prefill?.allDay ?? false,
    startDate: format(start, DATE_FMT),
    startTime: format(start, 'HH:mm'),
    endDate: format(end, DATE_FMT),
    endTime: format(end, 'HH:mm'),
    location: '',
    description: '',
  };
}
