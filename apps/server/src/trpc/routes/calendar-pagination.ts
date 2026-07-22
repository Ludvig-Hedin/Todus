export interface CalendarPage<T> {
  items?: T[];
  nextPageToken?: string;
}

interface PaginationOptions {
  maxPages?: number;
  maxItems?: number;
  onRepeatedToken?: () => void;
  onPageCap?: () => void;
}

/** Collects token-paginated Google Calendar responses in server order. */
export async function collectAllPages<T>(
  fetchPage: (pageToken?: string) => Promise<CalendarPage<T>>,
  options: PaginationOptions = {},
): Promise<T[]> {
  const maxPages = options.maxPages ?? 20;
  const items: T[] = [];
  const seenTokens = new Set<string>();
  let pageToken: string | undefined;

  for (let page = 0; page < maxPages; page += 1) {
    const data = await fetchPage(pageToken);
    items.push(...(data.items ?? []));
    if (options.maxItems !== undefined && items.length >= options.maxItems) {
      return items.slice(0, options.maxItems);
    }

    const next = data.nextPageToken;
    if (!next) return items;
    if (seenTokens.has(next)) {
      options.onRepeatedToken?.();
      return items;
    }
    seenTokens.add(next);
    pageToken = next;
  }

  options.onPageCap?.();
  return items;
}
