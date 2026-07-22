const RETENTION_SECONDS = 60 * 60 * 24;
const MAX_STATE_TTL_SECONDS = 31_556_952;

/** Keep scheduled-mail state until send time plus one day for retries/cancellation. */
export const getScheduledEmailStateTtlSeconds = (delaySeconds: number): number | null => {
  if (!Number.isFinite(delaySeconds) || delaySeconds < 0) return null;
  if (delaySeconds > MAX_STATE_TTL_SECONDS - RETENTION_SECONDS) return null;
  return Math.ceil(delaySeconds) + RETENTION_SECONDS;
};

/** Retry a missing payload only while its scheduled state should still exist. */
export const shouldRetryMissingScheduledEmailPayload = (
  sendAt: number | undefined,
  nowMs: number,
): boolean =>
  typeof sendAt === 'number' &&
  Number.isFinite(sendAt) &&
  Number.isFinite(nowMs) &&
  nowMs < sendAt + RETENTION_SECONDS * 1000;
