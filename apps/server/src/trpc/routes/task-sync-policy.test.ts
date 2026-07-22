import { describe, expect, it } from 'vitest';

import { collectDeletionWinsIDs } from './task-sync-policy';

describe('collectDeletionWinsIDs', () => {
  it('keeps persisted tombstones terminal for stale offline upserts', () => {
    const deleted = collectDeletionWinsIDs(
      [{ type: 'upsert', id: 'deleted-on-another-device' }],
      ['deleted-on-another-device'],
    );

    expect(deleted.has('deleted-on-another-device')).toBe(true);
  });

  it('makes deletion win regardless of mutation ordering inside one batch', () => {
    const deleted = collectDeletionWinsIDs(
      [
        { type: 'upsert', id: 'a' },
        { type: 'delete', id: 'a' },
        { type: 'delete', id: 'b' },
        { type: 'upsert', id: 'b' },
      ],
      [],
    );

    expect([...deleted].sort()).toEqual(['a', 'b']);
  });
});
