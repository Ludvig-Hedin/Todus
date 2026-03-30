import assert from 'node:assert/strict';
import test from 'node:test';
import {
  formatScheduleLabel,
  isSendFailure,
  isUndoEligibleResult,
  nextDefaultScheduleDate,
  splitRecipientInput,
  toRecipientObjects,
} from './composeParity';

test('splitRecipientInput trims, filters empty values, and deduplicates case-insensitively', () => {
  const recipients = splitRecipientInput(' a@example.com, ,B@example.com, b@example.com ');
  assert.deepEqual(recipients, ['a@example.com', 'B@example.com']);
});

test('toRecipientObjects returns normalized recipient objects', () => {
  const recipients = toRecipientObjects('a@example.com, b@example.com');
  assert.deepEqual(recipients, [{ email: 'a@example.com' }, { email: 'b@example.com' }]);
});

test('nextDefaultScheduleDate is 15 minutes in the future and rounded to minute', () => {
  const now = Date.UTC(2026, 1, 1, 12, 0, 45, 500);
  const next = nextDefaultScheduleDate(now);
  assert.equal(next.getTime(), Date.UTC(2026, 1, 1, 12, 15, 0, 0));
});

test('isSendFailure detects only explicit failed payloads', () => {
  assert.equal(isSendFailure({ success: false, error: 'oops' }), true);
  assert.equal(isSendFailure({ success: true }), false);
  assert.equal(isSendFailure({}), false);
});

test('isUndoEligibleResult detects queued/scheduled send payloads with IDs', () => {
  assert.equal(
    isUndoEligibleResult({
      queued: true,
      messageId: 'm-1',
      sendAt: Date.now() + 15_000,
    }),
    true,
  );
  assert.equal(
    isUndoEligibleResult({
      scheduled: true,
      messageId: 'm-2',
      sendAt: Date.now() + 60_000,
    }),
    true,
  );
  assert.equal(isUndoEligibleResult({ queued: true, sendAt: Date.now() + 15_000 }), false);
  assert.equal(isUndoEligibleResult({ queued: true, messageId: 'm-3' }), false);
});

test('formatScheduleLabel handles invalid dates gracefully', () => {
  assert.equal(formatScheduleLabel('not-a-date'), 'Send later');
});
