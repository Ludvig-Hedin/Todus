export function parseGroupMessagesCursor(cursor: string): { cursorDate: Date; cursorId: string } {
  const separatorIndex = cursor.lastIndexOf(':');
  if (separatorIndex <= 0 || separatorIndex === cursor.length - 1) {
    throw new Error('Invalid cursor format');
  }

  const timestamp = cursor.slice(0, separatorIndex);
  const cursorId = cursor.slice(separatorIndex + 1);
  const cursorDate = new Date(timestamp);

  if (Number.isNaN(cursorDate.getTime())) {
    throw new Error('Invalid cursor timestamp');
  }

  return { cursorDate, cursorId };
}
