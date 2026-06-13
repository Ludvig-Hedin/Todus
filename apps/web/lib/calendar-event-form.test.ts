import { describe, expect, it } from 'vitest';
import {
  type EventFormValues,
  buildCreatePayload,
  buildUpdatePatch,
  eventToFormValues,
  validateForm,
  bumpEndAfterStart,
} from './calendar-event-form';

const timed: EventFormValues = {
  title: 'Standup',
  allDay: false,
  startDate: '2026-06-15',
  startTime: '09:00',
  endDate: '2026-06-15',
  endTime: '09:30',
  location: 'Room 1',
  description: 'Daily',
};

const allDay: EventFormValues = {
  title: 'Conf',
  allDay: true,
  startDate: '2026-06-15',
  startTime: '00:00',
  endDate: '2026-06-15', // inclusive in the UI
  endTime: '00:00',
  location: '',
  description: '',
};

describe('validateForm', () => {
  it('rejects empty title', () => {
    expect(validateForm({ ...timed, title: '  ' })).toMatch(/title/i);
  });
  it('rejects timed end <= start', () => {
    expect(validateForm({ ...timed, endTime: '09:00' })).toMatch(/after/i);
  });
  it('accepts a valid timed event', () => {
    expect(validateForm(timed)).toBeNull();
  });
  it('rejects all-day end before start', () => {
    expect(validateForm({ ...allDay, endDate: '2026-06-14' })).toMatch(/on or after/i);
  });
  it('accepts a valid all-day event', () => {
    expect(validateForm(allDay)).toBeNull();
  });
});

describe('buildCreatePayload', () => {
  it('builds a timed payload with dateTime + timeZone', () => {
    const p = buildCreatePayload(timed, 'primary');
    expect(p.calendarId).toBe('primary');
    expect(p.summary).toBe('Standup');
    expect(p.location).toBe('Room 1');
    expect(p.start.dateTime).toBe(new Date('2026-06-15T09:00').toISOString());
    expect(p.start.date).toBeUndefined();
    expect(typeof p.start.timeZone).toBe('string');
  });
  it('builds an all-day payload with EXCLUSIVE end date (+1 day)', () => {
    const p = buildCreatePayload(allDay, 'primary');
    expect(p.start.date).toBe('2026-06-15');
    expect(p.start.dateTime).toBeUndefined();
    expect(p.end.date).toBe('2026-06-16'); // Google end.date is exclusive
  });
  it('omits empty optional fields', () => {
    const p = buildCreatePayload({ ...timed, location: '', description: '' });
    expect(p.location).toBeUndefined();
    expect(p.description).toBeUndefined();
  });
});

describe('eventToFormValues (edit mode)', () => {
  it('parses a timed event', () => {
    const v = eventToFormValues({
      title: 'Sync',
      description: 'x',
      location: 'y',
      startTime: '2026-06-15T14:00:00.000Z',
      endTime: '2026-06-15T15:00:00.000Z',
      allDay: false,
    });
    expect(v.allDay).toBe(false);
    expect(v.startDate).toBe('2026-06-15');
    expect(v.title).toBe('Sync');
  });
  it('parses an all-day event back to INCLUSIVE end date (-1 day)', () => {
    const v = eventToFormValues({
      title: 'Conf',
      description: null,
      location: null,
      startTime: '2026-06-15',
      endTime: '2026-06-17', // Google exclusive end
      allDay: true,
    });
    expect(v.allDay).toBe(true);
    expect(v.startDate).toBe('2026-06-15');
    expect(v.endDate).toBe('2026-06-16'); // inclusive
  });
});

describe('buildUpdatePatch', () => {
  it('produces a patch matching the create start/end shape', () => {
    const patch = buildUpdatePatch(timed);
    expect(patch.summary).toBe('Standup');
    expect(patch.start.dateTime).toBe(new Date('2026-06-15T09:00').toISOString());
    expect(patch.end.dateTime).toBe(new Date('2026-06-15T09:30').toISOString());
  });
});

describe('bumpEndAfterStart', () => {
  it('moves end to start+1h when end <= new start (timed)', () => {
    const v = bumpEndAfterStart({ ...timed, startTime: '10:00', endTime: '09:30' });
    expect(v.endDate).toBe('2026-06-15');
    expect(v.endTime).toBe('11:00');
  });
  it('leaves a valid end untouched', () => {
    const v = bumpEndAfterStart(timed);
    expect(v.endTime).toBe('09:30');
  });
});
