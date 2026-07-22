import { getScheduledEmailStateTtlSeconds } from './scheduled-email';
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
