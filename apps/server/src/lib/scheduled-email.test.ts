import {
  getScheduledEmailStateTtlSeconds,
  shouldRetryMissingScheduledEmailPayload,
} from './scheduled-email';
import { describe, expect, it } from 'vitest';

describe('getScheduledEmailStateTtlSeconds', () => {
  it('keeps payload state beyond a 48-hour schedule', () => {
    expect(getScheduledEmailStateTtlSeconds(48 * 60 * 60)).toBe(72 * 60 * 60);
  });

  it('retains undo-send payloads for one day after delivery', () => {
    expect(getScheduledEmailStateTtlSeconds(15)).toBe(24 * 60 * 60 + 15);
  });

  it('rejects delays whose state cannot fit within the KV maximum TTL', () => {
    expect(getScheduledEmailStateTtlSeconds(365 * 24 * 60 * 60)).toBeNull();
  });
});

describe('shouldRetryMissingScheduledEmailPayload', () => {
  const sendAt = Date.UTC(2026, 6, 22, 12);

  it('retries a transient miss while scheduled state should still exist', () => {
    expect(shouldRetryMissingScheduledEmailPayload(sendAt, sendAt + 60_000)).toBe(true);
  });

  it('treats a missing payload as terminal after the retention window', () => {
    expect(shouldRetryMissingScheduledEmailPayload(sendAt, sendAt + 24 * 60 * 60 * 1000)).toBe(
      false,
    );
  });

  it('treats legacy messages without sendAt as terminal', () => {
    expect(shouldRetryMissingScheduledEmailPayload(undefined, sendAt)).toBe(false);
  });
});
