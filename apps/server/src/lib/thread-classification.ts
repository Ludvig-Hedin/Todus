import { stripHtml } from 'string-strip-html';
import type { getThread } from './server-utils';

/**
 * Shared email thread classification primitives.
 *
 * This module is the single source of truth for the keyword/sender regexes,
 * the `ThreadKind` type, and `classifyThreadKind`. It preserves the SUPERSET
 * of the behavior that previously lived (and drifted) in
 * `trpc/routes/assistant.ts` and `trpc/routes/mail-assistant.ts`:
 *   - `RECEIPT_PHRASE_KEYWORDS` strong-receipt early return
 *   - the broader `NOREPLY_SENDER_PATTERN` (assistant.ts variant)
 * Both routers import from here so the two surfaces can never drift again.
 */

export const REPLY_KEYWORDS =
  /\b(reply|respond|follow up|can you|could you|would you|let me know|please|need|review|send|confirm)\b/i;
export const MEETING_KEYWORDS =
  /\b(meeting|schedule|calendar|appointment|call|zoom|teams|meet|availability|reschedule)\b/i;
export const URGENT_KEYWORDS =
  /\b(urgent|asap|today|immediately|priority|by end of day|deadline)\b/i;
export const AUTOMATED_KEYWORDS = /\b(no-?reply|unsubscribe|notification|automated|do not reply)\b/i;

export const VERIFICATION_KEYWORDS =
  /\b(verification|one[- ]?time|otp|verify your|confirmation code|security code|2fa|two[- ]?factor|magic link|sign[- ]?in code|access code|passcode)\b/i;

// Strong receipt phrases — these alone are enough to classify a thread as a
// receipt regardless of sender automation signal. Currency tokens were
// previously OR'd in here, but newsletters/marketing emails routinely include
// prices, so we keep them as a soft signal only.
export const RECEIPT_PHRASE_KEYWORDS =
  /\b(receipt|invoice|order\s*#?\d|payment\s+(received|confirmation)|order\s+(confirmation|summary)|tax\s+invoice|your\s+purchase|amount\s+paid|amount\s+charged|amount\s+billed|charge\s+(receipt|confirmation)|payment\s+method|billed\s+to|paid\s+to|transaction\s+(id|details)|refund\s+confirmation|subscription\s+renewed|your\s+(payment|charge|order)\s+(was|is))\b/i;
export const RECEIPT_KEYWORDS = new RegExp(
  `${RECEIPT_PHRASE_KEYWORDS.source}|\\$\\s?\\d|(?:USD|EUR|GBP|JPY|SEK|NOK|DKK|kr)\\s?\\d`,
  'i',
);

export const MARKETING_SENDER_PATTERN =
  /(news|newsletter|updates|digest|marketing|hello|info|hi|team)@/i;
export const NOREPLY_SENDER_PATTERN =
  /(no[- ]?reply|do[- ]?not[- ]?reply|notification|notifications|alerts?|automated|billing|payments?|receipts?|invoices?|subscriptions?|orders?|accounts?|support|hello|noreply|donotreply|mailer-daemon|postmaster|notifications?-noreply)@/i;
export const SHORT_CODE_PATTERN = /\b\d{4,8}\b/;

export type ThreadKind =
  | 'verification'
  | 'receipt'
  | 'marketing'
  | 'notification'
  | 'conversational';

export const THREAD_KIND_VALUES = [
  'verification',
  'receipt',
  'marketing',
  'notification',
  'conversational',
] as const satisfies readonly ThreadKind[];

function cleanText(value: string | null | undefined) {
  if (!value) return '';
  return stripHtml(value).result.replace(/\s+/g, ' ').trim();
}

export function latestMessageText(thread: Awaited<ReturnType<typeof getThread>>['result']) {
  const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
  return cleanText(latest?.decodedBody || latest?.body || '');
}

export function classifyThreadKind(
  thread: Awaited<ReturnType<typeof getThread>>['result'],
): ThreadKind {
  const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
  if (!latest) return 'conversational';
  const subject = latest.subject ?? '';
  const senderEmail = (latest.sender?.email ?? '').toLowerCase();
  const bodyText = latestMessageText(thread);
  const haystack = `${subject} ${bodyText}`;
  // Marketing senders (news@, hello@, team@, etc.) count as automated for
  // classification.
  const isAutomatedSender =
    NOREPLY_SENDER_PATTERN.test(senderEmail) ||
    AUTOMATED_KEYWORDS.test(senderEmail) ||
    MARKETING_SENDER_PATTERN.test(senderEmail);
  const automated = AUTOMATED_KEYWORDS.test(haystack) || isAutomatedSender;
  const singleMessage = thread.messages.length <= 1;

  // Verification / OTP — typically a short single message from a no-reply
  // sender containing a code.
  if (
    singleMessage &&
    (isAutomatedSender || automated) &&
    VERIFICATION_KEYWORDS.test(haystack) &&
    SHORT_CODE_PATTERN.test(bodyText)
  ) {
    return 'verification';
  }

  // Strong receipt phrases (e.g. "tax invoice", "amount paid", "your purchase")
  // are enough on their own to classify as a receipt — many vendors send
  // receipts from `support@`, `accounts@`, or even a personal-looking address
  // that doesn't trip the no-reply pattern, and incorrectly classifying these
  // as conversational was producing bogus "Urgent reply" briefing entries.
  if (RECEIPT_PHRASE_KEYWORDS.test(haystack)) {
    return 'receipt';
  }

  // Receipt / invoice / subscription renewal — automated sender + transactional
  // language (including soft currency signals).
  if ((isAutomatedSender || automated) && RECEIPT_KEYWORDS.test(haystack)) {
    return 'receipt';
  }

  // Marketing / newsletter — broad sender alias + automated.
  if (isAutomatedSender && MARKETING_SENDER_PATTERN.test(senderEmail)) {
    return 'marketing';
  }

  // Generic automated notification — automated keywords or no-reply sender,
  // no other category matched.
  if (automated) {
    return 'notification';
  }

  return 'conversational';
}
