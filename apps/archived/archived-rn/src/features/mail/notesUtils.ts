type NoteLike = {
  isPinned?: boolean | null;
  order?: number | null;
};

export function sortThreadNotes<T extends NoteLike>(notes: T[]): T[] {
  return [...notes].sort((a, b) => {
    const pinDelta = Number(Boolean(b?.isPinned)) - Number(Boolean(a?.isPinned));
    if (pinDelta !== 0) return pinDelta;
    const orderA = typeof a?.order === 'number' ? a.order : 0;
    const orderB = typeof b?.order === 'number' ? b.order : 0;
    return orderA - orderB;
  });
}
