import { describe, expect, it } from 'vitest';

import { parseGroupMessagesCursor } from './groups-cursor';

describe('parseGroupMessagesCursor', () => {
  it('parses ISO timestamps that contain colons', () => {
    const parsed = parseGroupMessagesCursor('2026-04-02T12:34:56.789Z:abc123');

    expect(parsed.cursorDate.toISOString()).toBe('2026-04-02T12:34:56.789Z');
    expect(parsed.cursorId).toBe('abc123');
  });

  it('rejects malformed cursors', () => {
    expect(() => parseGroupMessagesCursor('not-a-valid-cursor')).toThrow(
      'Invalid cursor format',
    );
    expect(() => parseGroupMessagesCursor('2026-04-02T12:34:56.789Z:')).toThrow(
      'Invalid cursor format',
    );
  });
});
