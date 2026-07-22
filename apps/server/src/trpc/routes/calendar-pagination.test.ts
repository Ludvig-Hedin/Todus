import { collectAllPages } from './calendar-pagination';
import { describe, expect, it, vi } from 'vitest';

describe('collectAllPages', () => {
  it('follows nextPageToken and returns every item in order', async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce({ items: [{ id: 'a' }], nextPageToken: 'page-2' })
      .mockResolvedValueOnce({ items: [{ id: 'b' }] });

    const items = await collectAllPages<{ id: string }>(fetchPage);

    expect(items.map((item) => item.id)).toEqual(['a', 'b']);
    expect(fetchPage).toHaveBeenCalledTimes(2);
    expect(fetchPage).toHaveBeenNthCalledWith(1, undefined);
    expect(fetchPage).toHaveBeenNthCalledWith(2, 'page-2');
  });

  it('stops safely when Google repeats a page token', async () => {
    const onRepeatedToken = vi.fn();
    const fetchPage = vi
      .fn()
      .mockResolvedValue({ items: [{ id: 'a' }], nextPageToken: 'same-token' });

    const items = await collectAllPages<{ id: string }>(fetchPage, { onRepeatedToken });

    expect(items).toHaveLength(2);
    expect(fetchPage).toHaveBeenCalledTimes(2);
    expect(onRepeatedToken).toHaveBeenCalledOnce();
  });

  it('preserves a caller limit while following partial pages', async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce({ items: [{ id: 'a' }], nextPageToken: 'page-2' })
      .mockResolvedValueOnce({ items: [{ id: 'b' }, { id: 'c' }], nextPageToken: 'page-3' });

    const items = await collectAllPages<{ id: string }>(fetchPage, { maxItems: 2 });

    expect(items.map((item) => item.id)).toEqual(['a', 'b']);
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });
});
