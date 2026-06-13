/**
 * Per-calendar visibility for the web calendar — which Google calendars are
 * shown in the grid. Persisted in localStorage (a device-local preference,
 * matching how native handles calendar visibility). Stores the set of HIDDEN
 * calendar ids; everything not in the set is visible.
 *
 * Shared by `/mail/calendar` and `/settings/calendars`; a same-tab custom
 * event plus the cross-tab `storage` event keep both surfaces in sync.
 */
import { useCallback, useEffect, useState } from 'react';

const KEY = 'calendar.hiddenCalendars';
const CHANGE_EVENT = 'calendar-visibility-changed';

function readHidden(): Set<string> {
  if (typeof window === 'undefined') return new Set();
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return new Set();
    const arr: unknown = JSON.parse(raw);
    return Array.isArray(arr)
      ? new Set(arr.filter((x): x is string => typeof x === 'string'))
      : new Set();
  } catch {
    return new Set();
  }
}

function writeHidden(set: Set<string>) {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(KEY, JSON.stringify([...set]));
    window.dispatchEvent(new CustomEvent(CHANGE_EVENT));
  } catch {
    // ignore quota / private mode
  }
}

export function useCalendarVisibility() {
  const [hidden, setHidden] = useState<Set<string>>(() => readHidden());

  // Keep in sync when the other surface (or another tab) changes the set.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const refresh = () => setHidden(readHidden());
    window.addEventListener(CHANGE_EVENT, refresh);
    window.addEventListener('storage', refresh);
    return () => {
      window.removeEventListener(CHANGE_EVENT, refresh);
      window.removeEventListener('storage', refresh);
    };
  }, []);

  const toggle = useCallback((calendarId: string) => {
    setHidden((prev) => {
      const next = new Set(prev);
      if (next.has(calendarId)) next.delete(calendarId);
      else next.add(calendarId);
      writeHidden(next);
      return next;
    });
  }, []);

  const isHidden = useCallback((calendarId: string) => hidden.has(calendarId), [hidden]);

  return { hidden, toggle, isHidden };
}
