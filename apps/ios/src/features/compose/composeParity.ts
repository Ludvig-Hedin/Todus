export type SendResultLike = {
  success?: boolean;
  error?: string;
  messageId?: string;
  sendAt?: number;
  queued?: boolean;
  scheduled?: boolean;
};

export function uniqueEmails(emails: string[]): string[] {
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const value of emails) {
    const trimmed = value.trim();
    if (!trimmed) continue;
    const normalized = trimmed.toLowerCase();
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    deduped.push(trimmed);
  }
  return deduped;
}

export function splitRecipientInput(value: string): string[] {
  return uniqueEmails(
    value
      .split(',')
      .map((email) => email.trim())
      .filter(Boolean),
  );
}

export function toRecipientObjects(value: string): Array<{ email: string }> {
  return splitRecipientInput(value).map((email) => ({ email }));
}

export function nextDefaultScheduleDate(now = Date.now()): Date {
  const base = new Date(now + 15 * 60 * 1000);
  base.setSeconds(0, 0);
  return base;
}

export function formatScheduleLabel(scheduleAt: string): string {
  const date = new Date(scheduleAt);
  if (Number.isNaN(date.getTime())) {
    return 'Send later';
  }
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
}

export function isSendFailure(result: SendResultLike): boolean {
  return result.success === false;
}

export function isUndoEligibleResult(result: SendResultLike): boolean {
  return Boolean((result.queued || result.scheduled) && result.messageId && result.sendAt);
}
