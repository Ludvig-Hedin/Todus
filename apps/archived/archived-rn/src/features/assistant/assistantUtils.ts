export function extractResponseText(result: unknown): string {
  if (!result || typeof result !== 'object') {
    return '';
  }
  const asRecord = result as Record<string, unknown>;
  if (typeof asRecord.text === 'string') {
    return asRecord.text;
  }
  if (typeof asRecord.response === 'string') {
    return asRecord.response;
  }
  return '';
}

export function nextStreamCursor(current: number, totalLength: number, chunkSize = 3): number {
  if (totalLength <= 0) return 0;
  return Math.min(totalLength, Math.max(0, current + chunkSize));
}
