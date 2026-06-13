import {
  assistantBriefingSnapshot,
  assistantFeedback,
  assistantOpenLoop,
  assistantPersonMemory,
  assistantPreparedAction,
  assistantWorkstreamMemory,
  meeting,
  task,
} from '../../db/schema';
import {
  getActiveConnection,
  getThread,
  getThreadsFromDB,
  getZeroAgent,
  isMissingConnectionColorError,
} from '../../lib/server-utils';
import {
  AUTOMATED_KEYWORDS,
  MEETING_KEYWORDS,
  REPLY_KEYWORDS,
  THREAD_KIND_VALUES,
  URGENT_KEYWORDS,
  classifyThreadKind,
  latestMessageText,
  type ThreadKind,
} from '../../lib/thread-classification';
import { activeConnectionProcedure, privateProcedure, router } from '../trpc';
import { and, desc, eq, inArray, lte } from 'drizzle-orm';
import { OAuth2Client } from 'google-auth-library';
import { stripHtml } from 'string-strip-html';
import { composeEmail } from './ai/compose';
import { TRPCError } from '@trpc/server';
import { createDb } from '../../db';
import { env } from '../../env';
import { generateActionLines } from '../../lib/assistant-action-line';
import { z } from 'zod';

const assistantLoopTypeSchema = z.enum([
  'needs_reply',
  'waiting_on_other',
  'deadline_risk',
  'meeting_follow_up',
  'decision_needed',
  'draft_ready',
  'research_needed',
]);

const assistantLoopQueueSchema = z.enum([
  'needs_you',
  'waiting_on',
  'scheduling',
  'drafts_ready',
  'likely_dropped',
]);

const assistantLoopStatusSchema = z.enum(['open', 'snoozed', 'done', 'dismissed']);
const assistantPreparedActionTypeSchema = z.enum([
  'draft_reply',
  'create_task',
  'create_event',
  'follow_up',
  'research',
]);
const assistantPreparedActionStatusSchema = z.enum(['pending', 'approved', 'applied', 'dismissed']);
const assistantRiskSchema = z.enum(['low', 'medium', 'high']);

const assistantEvidenceSchema = z.object({
  kind: z.enum(['thread', 'message', 'task', 'event', 'meeting', 'person', 'workstream']),
  id: z.string(),
  label: z.string().nullable(),
});

const assistantOpenLoopSchema = z.object({
  id: z.string(),
  type: assistantLoopTypeSchema,
  queue: assistantLoopQueueSchema,
  status: assistantLoopStatusSchema,
  title: z.string(),
  summary: z.string(),
  confidence: z.number(),
  reason: z.string(),
  suggestedActionLabel: z.string().nullable(),
  /// LLM-generated verb-first sentence ("Reply to Sarah about Q4"). Null when
  /// generation disabled or failed — client falls back to title/summary render.
  actionLine: z.string().nullable(),
  threadId: z.string().nullable(),
  meetingId: z.string().nullable(),
  personEmail: z.string().nullable(),
  workstreamKey: z.string().nullable(),
  lastReviewedAt: z.string().nullable(),
  snoozedUntil: z.string().nullable(),
  evidence: z.array(assistantEvidenceSchema),
});

const assistantPreparedActionSchema = z.object({
  id: z.string(),
  type: assistantPreparedActionTypeSchema,
  status: assistantPreparedActionStatusSchema,
  title: z.string(),
  summary: z.string(),
  confidence: z.number(),
  reason: z.string(),
  preview: z.string().nullable(),
  /// Same as openLoopSchema.actionLine — verb-first sentence; nullable.
  actionLine: z.string().nullable(),
  threadId: z.string().nullable(),
  meetingId: z.string().nullable(),
  personEmail: z.string().nullable(),
  workstreamKey: z.string().nullable(),
  payload: z.record(z.string(), z.unknown()),
  evidence: z.array(assistantEvidenceSchema),
});

const assistantPersonContextSchema = z.object({
  email: z.string(),
  displayName: z.string(),
  company: z.string().nullable(),
  relationshipSummary: z.string(),
  unresolvedAsks: z.array(z.string()),
  promises: z.array(z.string()),
  recentThreadIds: z.array(z.string()),
  recentMeetingIds: z.array(z.string()),
  recentTaskIds: z.array(z.string()),
  openLoopCount: z.number(),
  lastInteractionAt: z.string().nullable(),
});

const assistantWorkstreamContextSchema = z.object({
  key: z.string(),
  title: z.string(),
  summary: z.string(),
  status: z.string(),
  pendingDecisions: z.array(z.string()),
  risks: z.array(z.string()),
  relatedPeople: z.array(z.string()),
  relatedThreadIds: z.array(z.string()),
  relatedMeetingIds: z.array(z.string()),
  relatedTaskIds: z.array(z.string()),
  nextMilestone: z.string().nullable(),
});

const assistantMeetingSummarySchema = z.object({
  id: z.string(),
  title: z.string(),
  startsAt: z.string(),
  status: z.string(),
  aiSummaryReady: z.boolean(),
});

const assistantChangeFeedItemSchema = z.object({
  id: z.string(),
  type: z.enum(['open_loop', 'prepared_action', 'meeting', 'task', 'thread']),
  title: z.string(),
  summary: z.string(),
  occurredAt: z.string(),
});

const assistantBriefPrioritySchema = z.object({
  kind: z.enum(['task', 'open_loop', 'meeting', 'prepared_action']),
  id: z.string(),
  title: z.string(),
  summary: z.string(),
});

const assistantBriefingSchema = z.object({
  generatedAt: z.string(),
  today: z.object({
    nextEvent: assistantMeetingSummarySchema.nullable(),
    topTask: z
      .object({
        id: z.string(),
        title: z.string(),
        dueDate: z.string().nullable(),
        priority: z.string(),
      })
      .nullable(),
    urgentReply: assistantOpenLoopSchema.nullable(),
  }),
  topPriorities: z.array(assistantBriefPrioritySchema),
  needsYou: z.array(assistantOpenLoopSchema),
  waitingOn: z.array(assistantOpenLoopSchema),
  prepared: z.array(assistantPreparedActionSchema),
  upcomingMeetings: z.array(assistantMeetingSummarySchema),
  changedSinceLastTime: z.array(assistantChangeFeedItemSchema),
});

// `THREAD_KIND_VALUES` + the `ThreadKind` type + `classifyThreadKind` and the
// keyword/sender regexes now live in `lib/thread-classification.ts` (shared with
// `mail-assistant.ts`). They are imported at the top of this file.

// Structured "smart action" payloads extracted from low-signal threads.
// These give the client something concrete to render in place of the AI
// card on verification / receipt threads — showing the code or vendor + amount
// is dramatically more useful than hiding everything.
const extractedReceiptSchema = z.object({
  vendor: z.string(),
  amount: z.string().nullable(),
  receivedAt: z.string().nullable(),
});

const assistantThreadContextSchema = z.object({
  threadId: z.string(),
  subject: z.string(),
  summary: z.string(),
  /// One-line headline picked from the most useful signal in the thread:
  /// meeting time, first action item, first question, or summary fallback.
  /// Empty on non-conversational kinds and when nothing useful was found.
  /// Clients prefer this over `summary` when both are present.
  aiLeadLine: z.string().default(''),
  threadKind: z.enum(THREAD_KIND_VALUES).default('conversational'),
  /// Verification code lifted out of the body for one-tap copy. Null on any
  /// non-verification thread or when extraction couldn't find a usable code.
  extractedCode: z.string().nullable().default(null),
  /// Vendor + amount + date for receipt-style threads. Null when not a
  /// receipt or when we couldn't pull a confident amount/date.
  extractedReceipt: extractedReceiptSchema.nullable().default(null),
  recommendation: z.object({
    label: z.string(),
    reason: z.string(),
  }),
  waitingState: z.enum(['waiting_on_me', 'waiting_on_them', 'done', 'unclear']),
  confidence: z.number(),
  riskLevel: assistantRiskSchema,
  reason: z.string(),
  replyNeeded: z.boolean(),
  followUpNeeded: z.boolean(),
  meetingRequested: z.boolean(),
  existingDraft: z.boolean(),
  actionItems: z.array(z.string()),
  researchQueries: z.array(z.string()),
  suggestedTasks: z.array(
    z.object({
      title: z.string(),
      description: z.string().nullable(),
      priority: z.enum(['none', 'low', 'medium', 'high']),
      dueDate: z.string().nullable(),
    }),
  ),
  suggestedEvent: z
    .object({
      title: z.string(),
      startAt: z.string().nullable(),
      endAt: z.string().nullable(),
      location: z.string().nullable(),
      notes: z.string().nullable(),
    })
    .nullable(),
  relatedTasks: z.array(
    z.object({
      id: z.string(),
      title: z.string(),
      status: z.string(),
      dueDate: z.string().nullable(),
    }),
  ),
  relatedMeetings: z.array(assistantMeetingSummarySchema),
  people: z.array(assistantPersonContextSchema),
  openLoops: z.array(assistantOpenLoopSchema),
  preparedActions: z.array(assistantPreparedActionSchema),
  changedSinceLastOpen: z.array(z.string()),
});

const assistantFeedbackInputSchema = z.object({
  targetType: z.enum(['open_loop', 'prepared_action', 'person_memory', 'workstream_memory']),
  targetId: z.string(),
  feedback: z.enum(['helpful', 'not_helpful', 'too_noisy', 'wrong', 'completed']),
  note: z.string().optional(),
});

type DbHandle = Awaited<ReturnType<typeof createDb>>['db'];
type MeetingRow = typeof meeting.$inferSelect;
type TaskRow = typeof task.$inferSelect;
type OpenLoopRow = typeof assistantOpenLoop.$inferSelect;
type PreparedActionRow = typeof assistantPreparedAction.$inferSelect;
type PersonMemoryRow = typeof assistantPersonMemory.$inferSelect;
type WorkstreamMemoryRow = typeof assistantWorkstreamMemory.$inferSelect;
type AssistantEvidence = z.infer<typeof assistantEvidenceSchema>;
type AssistantRisk = z.infer<typeof assistantRiskSchema>;
type WaitingState = z.infer<typeof assistantThreadContextSchema.shape.waitingState>;

type OpenLoopCandidate = {
  uniqueKey: string;
  type: OpenLoopRow['type'];
  queue: OpenLoopRow['queue'];
  status: OpenLoopRow['status'];
  title: string;
  summary: string;
  confidence: number;
  reason: string;
  suggestedActionLabel?: string | null;
  actionLine?: string | null;
  sourceThreadId: string | null;
  sourceMeetingId: string | null;
  sourceTaskId: string | null;
  sourceEventId: string | null;
  personEmail: string | null;
  workstreamKey: string | null;
  evidence: AssistantEvidence[];
};

type PreparedActionCandidate = {
  uniqueKey: string;
  type: PreparedActionRow['type'];
  status: PreparedActionRow['status'];
  title: string;
  summary: string;
  confidence: number;
  reason: string;
  actionLine?: string | null;
  preview?: string | null;
  payload: Record<string, unknown>;
  sourceThreadId: string | null;
  sourceMeetingId: string | null;
  personEmail: string | null;
  workstreamKey: string | null;
  evidence: AssistantEvidence[];
};

function unique<T>(items: T[]) {
  return [...new Set(items)];
}

function cleanText(value: string | null | undefined) {
  if (!value) return '';
  return stripHtml(value).result.replace(/\s+/g, ' ').trim();
}

// Verification keywords used to anchor the *fallback* (unlabelled) code path.
// A bare digit run is only accepted when it sits within ~20 chars of one of
// these so we don't grab order numbers, postal codes, or phone numbers.
const VERIFICATION_CONTEXT_KEYWORDS = /(code|verification|verify|otp|passcode|pin)/i;
// US state names/abbreviations that, when immediately preceding a 5-digit run,
// strongly imply a ZIP code rather than a verification code.
const US_STATE_BEFORE_ZIP =
  /\b(?:A[KLRZ]|C[AOT]|D[CE]|FL|GA|HI|I[ADLN]|K[SY]|LA|M[ADEINOST]|N[CDEHJMVY]|O[HKR]|PA|RI|S[CD]|T[NX]|UT|V[AT]|W[AIVY]|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|virginia|washington|west virginia|wisconsin|wyoming)\s*,?\s*$/i;

/**
 * Decide whether a bare (unlabelled) digit run is a plausible verification
 * code given its surrounding context. Rejects obvious non-codes:
 *   - 10+ digit phone numbers (handled by the 4–8 length cap upstream, but the
 *     raw token here may be longer)
 *   - 5-digit US ZIP codes immediately preceded by a state name/abbreviation
 *   - a pure 4-digit year (1900–2099)
 * and requires the run to sit within ~20 chars of a verification keyword.
 */
function isPlausibleFallbackCode(haystack: string, index: number, token: string): boolean {
  // Phone numbers: a 10+ digit run is never a code. (The `\b\d{4,8}\b` matcher
  // upstream already won't return such a run, but guard here too in case the
  // caller is changed.)
  if (token.length >= 10) return false;

  // Pure 4-digit year (1900–2099) — almost never the verification code even if
  // it happens to sit near a keyword.
  if (/^(?:19|20)\d{2}$/.test(token)) return false;

  const windowStart = Math.max(0, index - 20);
  const before = haystack.slice(windowStart, index);
  const after = haystack.slice(index + token.length, index + token.length + 20);

  // 5-digit US ZIP preceded by a state name/abbreviation.
  if (token.length === 5 && US_STATE_BEFORE_ZIP.test(before)) return false;

  // Require a verification keyword within ~20 chars on either side.
  return VERIFICATION_CONTEXT_KEYWORDS.test(before) || VERIFICATION_CONTEXT_KEYWORDS.test(after);
}

/**
 * Try to pull the verification code out of a verification email body.
 *
 * Strategy: prefer codes that appear right after a verification keyword
 * ("code: 178691", "your code is 178 691"). The fallback (no labelled code)
 * only accepts a bare digit run when it sits within ~20 chars of a
 * verification keyword AND survives the non-code rejection rules in
 * `isPlausibleFallbackCode` (phone numbers, state-prefixed ZIPs, pure years).
 * When nothing confidently qualifies we return null rather than risk handing
 * the user an order number / postal code / phone number. We accept 4-8 digits
 * with an optional single space splitting them in half (e.g. "178 691"
 * rendered for readability). Returns the code with a single space inserted in
 * the middle for any 6+ digit code so the UI can render it readably without
 * doing the formatting itself.
 */
export function extractVerificationCode(body: string): string | null {
  if (!body) return null;
  const haystack = body.replace(/\s+/g, ' ');

  // Look for "<keyword> ... <code>" patterns first — they're the most
  // reliable. The code may have an optional space (Mailchimp / SendGrid
  // sometimes render "178 691" for readability). This primary path is
  // unchanged.
  const labelled = haystack.match(
    /(?:code|otp|passcode|pin|password)[^0-9]{0,30}(\d{3,4}[\s-]?\d{3,4}|\d{4,8})/i,
  );
  let result = labelled?.[1] ?? null;

  // Fallback: a bare 4–8 digit run, but only when it's adjacent to a
  // verification keyword and not an obvious non-code (phone / ZIP / year).
  // Among the plausible candidates we pick the longest, matching the prior
  // "longest run wins" heuristic but scoped to context-validated tokens.
  if (!result) {
    const re = /\b\d{4,8}\b/g;
    let best: string | null = null;
    let match: RegExpExecArray | null;
    while ((match = re.exec(haystack)) !== null) {
      const token = match[0];
      if (!isPlausibleFallbackCode(haystack, match.index, token)) continue;
      if (!best || token.length > best.length) best = token;
    }
    result = best;
  }

  if (!result) return null;
  const digits = result.replace(/[\s-]/g, '');
  if (digits.length < 4 || digits.length > 8) return null;
  // Pretty-print 6+ digit codes as two halves so the UI can render them
  // readably ("178 691" not "178691"). Shorter codes stay as-is.
  if (digits.length >= 6) {
    const half = Math.ceil(digits.length / 2);
    return `${digits.slice(0, half)} ${digits.slice(half)}`;
  }
  return digits;
}

/**
 * Best-effort extractor for receipt-style emails. Pulls the first currency
 * amount it finds in the body, the sender domain as the vendor, and the
 * received date. Returns null when none of those signals are confidently
 * present so the client can fall back to "show nothing".
 */
export interface ExtractedReceipt {
  vendor: string;
  amount: string | null;
  receivedAt: string | null;
}

export function extractReceiptDetails(
  thread: Awaited<ReturnType<typeof getThread>>['result'],
): ExtractedReceipt | null {
  const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
  if (!latest) return null;
  const senderEmail = latest.sender?.email ?? '';
  const senderName = latest.sender?.name?.trim();
  // Prefer the human sender name; fall back to the domain so we always have
  // something to render (e.g. "Stripe" vs "stripe.com").
  const domain = senderEmail.split('@')[1]?.split('.').slice(-2, -1)[0];
  const vendor = senderName && senderName.length > 0
    ? senderName
    : domain
      ? domain.charAt(0).toUpperCase() + domain.slice(1)
      : 'Sender';

  const body = cleanText(latest.decodedBody || latest.body || '');
  // Currency amount sub-patterns reused by both the labelled and fallback
  // matches. Match common currency patterns: $29.00, USD 29.00, €19,95,
  // kr 100, 100 SEK, etc.
  const CURRENCY_PREFIXED = String.raw`(?:[$€£¥]|US\$|USD|EUR|GBP|JPY|SEK|NOK|DKK|kr)\s?\d{1,3}(?:[ ,.]\d{3})*(?:[.,]\d{2})?`;
  const CURRENCY_SUFFIXED = String.raw`\d{1,3}(?:[ ,.]\d{3})*(?:[.,]\d{2})?\s?(?:USD|EUR|GBP|JPY|SEK|NOK|DKK|kr)`;
  const CURRENCY_AMOUNT = `(?:${CURRENCY_PREFIXED}|${CURRENCY_SUFFIXED})`;

  // 1. Label-anchored amount FIRST: a total/amount-paid label within ~20 chars
  // before the currency number. This avoids grabbing a per-line-item price.
  const labelledAmount = body.match(
    new RegExp(
      String.raw`(?:total|amount\s+paid|amount\s+charged|grand\s+total|you\s+paid)[^0-9$€£¥]{0,20}(${CURRENCY_AMOUNT})`,
      'i',
    ),
  );

  // 2. Fall back to the first currency number anywhere in the body. We stay
  // conservative — better to render no amount than the wrong amount.
  const amountMatch = labelledAmount?.[1]
    ? labelledAmount[1]
    : (body.match(new RegExp(CURRENCY_PREFIXED, 'i'))?.[0] ??
      body.match(new RegExp(CURRENCY_SUFFIXED, 'i'))?.[0] ??
      null);
  const amount = amountMatch ?? null;

  const receivedAt = latest.receivedOn
    ? new Date(latest.receivedOn).toISOString()
    : null;

  // Require at least vendor + (amount OR receivedAt) — otherwise the chip
  // would just show the sender name, which is already in the header.
  if (!amount && !receivedAt) return null;

  return { vendor, amount, receivedAt };
}

/**
 * Build a fallback summary when the vector cache misses.
 *
 * Returns an empty string for low-signal threads (verification, receipts,
 * marketing, automated notifications) so the client can hide the AI summary
 * card. For conversational threads we also return empty rather than the old
 * "X most recently wrote about Y" template — that template restated header
 * data without adding value. An empty string signals "no useful summary";
 * the UI hides the card until a real cached summary is available.
 */
function buildFallbackSummary(thread: Awaited<ReturnType<typeof getThread>>['result']) {
  const kind = classifyThreadKind(thread);
  if (kind !== 'conversational') return '';
  return '';
}

/**
 * Pick the single most useful one-liner to render in the AI summary card.
 *
 * The prior approach showed the cached vector summary verbatim, which often
 * just paraphrased the email. This helper picks the most actionable signal:
 *   1. A meeting time if one was extracted ("Meeting · Mon, Apr 28 at 3:00 PM")
 *   2. The first action item, lightly cleaned up ("Review the Q3 forecast")
 *   3. A direct question pulled from the body ("Can you confirm by Friday?")
 *   4. The summary text as a last resort
 *
 * Returns an empty string when none of those produce something useful, which
 * the client interprets as "hide the card on this thread".
 */
function buildAiLeadLine(input: {
  threadKind: ThreadKind;
  meetingRequested: boolean;
  suggestedEvent: ReturnType<typeof extractEventSuggestion>;
  actionItems: string[];
  bodyText: string;
  summary: string;
}): string {
  // Smart-action chips (verification / receipt) own the visual real estate
  // for non-conversational kinds — never compete with them.
  if (input.threadKind !== 'conversational') return '';

  // 1. Meeting time wins when present. The user opened the email; what they
  // need is "when, where".
  if (input.meetingRequested && input.suggestedEvent?.startAt) {
    const start = new Date(input.suggestedEvent.startAt);
    if (!Number.isNaN(start.getTime())) {
      const formatted = start.toLocaleString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      });
      const title = input.suggestedEvent.title?.trim();
      return title ? `Meeting · ${title} · ${formatted}` : `Meeting · ${formatted}`;
    }
  }

  // 2. First action item — usually the AI's best guess at the ask.
  const firstAction = input.actionItems[0]?.trim();
  if (firstAction && firstAction.length > 0 && firstAction.length <= 200) {
    // Capitalize and trim trailing punctuation noise.
    const cleaned = firstAction.replace(/[.,;]+$/, '');
    return cleaned.charAt(0).toUpperCase() + cleaned.slice(1);
  }

  // 3. First direct question in the body — often more useful than the summary
  // because it's literally the thing waiting on a reply.
  const question = extractFirstQuestion(input.bodyText);
  if (question) return question;

  // 4. Fall back to the cached summary.
  return input.summary?.trim() ?? '';
}

/**
 * Pull the first complete question sentence out of a body of text.
 * Keeps it bounded (max 180 chars) so we never render a wall of text.
 */
function extractFirstQuestion(body: string): string | null {
  if (!body) return null;
  // Split on sentence terminators (.!?) so a question doesn't carry the
  // preceding sentence's prose. Then keep only segments that end with `?`.
  const normalized = body.replace(/\s+/g, ' ');
  const segments = normalized
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter((s) => s.endsWith('?'));
  for (const sentence of segments) {
    if (sentence.length < 8 || sentence.length > 180) continue;
    // Skip rhetorical / boilerplate questions ("Need help?" footers etc.).
    if (/^(need help|questions?|any questions|why)\??$/i.test(sentence)) continue;
    return sentence;
  }
  return null;
}

async function getThreadSummary(
  threadId: string,
  connectionId: string,
  thread: Awaited<ReturnType<typeof getThread>>['result'],
) {
  try {
    const response = await env.VECTORIZE.getByIds([threadId]);
    if (response.length && response[0]?.metadata?.['summary']) {
      const metadata = response[0].metadata as { summary?: string; connection?: string };
      if (metadata.connection === connectionId && metadata.summary) {
        return metadata.summary.trim();
      }
    }
  } catch (error) {
    console.warn('[assistant.getThreadSummary] Failed to load vector summary', error);
  }

  return buildFallbackSummary(thread);
}

function inferDueDate(text: string, baseDate: Date) {
  const lower = text.toLowerCase();
  if (lower.includes('today')) return baseDate.toISOString();
  if (lower.includes('tomorrow')) {
    const tomorrow = new Date(baseDate);
    tomorrow.setDate(baseDate.getDate() + 1);
    return tomorrow.toISOString();
  }
  if (lower.includes('next week')) {
    const nextWeek = new Date(baseDate);
    nextWeek.setDate(baseDate.getDate() + 7);
    return nextWeek.toISOString();
  }
  return null;
}

function extractActionItems(text: string, subject: string, senderName: string) {
  const candidates = text
    .split(/[\n•\-]+|(?<=[.!?])\s+/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter(
      (line) =>
        REPLY_KEYWORDS.test(line) || MEETING_KEYWORDS.test(line) || URGENT_KEYWORDS.test(line),
    );

  const cleaned = unique(
    candidates.map((line) =>
      line
        .replace(/^(please|can you|could you|would you|kindly)\s+/i, '')
        .replace(/\s+/g, ' ')
        .trim(),
    ),
  ).slice(0, 4);

  if (cleaned.length) return cleaned;

  if (REPLY_KEYWORDS.test(text)) {
    return [`Reply to ${senderName || 'the sender'} about ${subject || 'this thread'}`];
  }

  return [];
}

function extractEventSuggestion(subject: string, text: string, baseDate: Date) {
  if (!MEETING_KEYWORDS.test(`${subject} ${text}`)) return null;

  const lower = `${subject} ${text}`.toLowerCase();
  const timeMatch = lower.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)/i);
  let start = new Date(baseDate);

  if (lower.includes('tomorrow')) {
    start.setDate(start.getDate() + 1);
  }

  if (!timeMatch) {
    return {
      title: subject.replace(/^re:\s*/i, '').trim() || 'Meeting',
      startAt: null,
      endAt: null,
      location: null,
      notes: 'Meeting request detected in email. Review details before creating the event.',
    };
  }

  let hour = Number(timeMatch[1]);
  const minutes = Number(timeMatch[2] ?? '0');
  const meridiem = timeMatch[3].toLowerCase();

  if (meridiem === 'pm' && hour < 12) hour += 12;
  if (meridiem === 'am' && hour === 12) hour = 0;

  start.setHours(hour, minutes, 0, 0);
  const end = new Date(start.getTime() + 60 * 60 * 1000);

  return {
    title: subject.replace(/^re:\s*/i, '').trim() || 'Meeting',
    startAt: start.toISOString(),
    endAt: end.toISOString(),
    location: null,
    notes: 'Created from Todus assistant context.',
  };
}

function createResearchQueries(
  subject: string,
  senderEmail: string | undefined,
  latestText: string,
) {
  const queries = [subject].filter(Boolean);
  if (senderEmail) {
    const [, domain] = senderEmail.split('@');
    if (domain) queries.push(`Is ${domain} trustworthy?`);
  }
  if (/invoice|contract|pricing|security|policy/i.test(latestText)) {
    queries.push(`Double check details for ${subject}`);
  }
  return unique(queries).slice(0, 3);
}

function normalizeSubject(subject: string) {
  return subject.replace(/^(re|fwd?):\s*/gi, '').trim();
}

function normalizeWorkstreamKey(subject: string) {
  return (
    normalizeSubject(subject)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 80) || 'general'
  );
}

function companyFromEmail(email?: string | null) {
  if (!email) return null;
  const [, domain] = email.split('@');
  return domain ?? null;
}

function safeDateString(value: Date | string | null | undefined) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === 'string');
}

function asEvidenceArray(value: unknown): z.infer<typeof assistantEvidenceSchema>[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => assistantEvidenceSchema.safeParse(entry))
    .filter(
      (entry): entry is { success: true; data: z.infer<typeof assistantEvidenceSchema> } =>
        entry.success,
    )
    .map((entry) => entry.data);
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

async function createGoogleCalendarEvent(
  refreshToken: string,
  payload: {
    title: string;
    startAt: string;
    endAt: string;
    location?: string | null;
    notes?: string | null;
  },
) {
  const auth = new OAuth2Client(env.GOOGLE_CLIENT_ID, env.GOOGLE_CLIENT_SECRET);
  auth.setCredentials({ refresh_token: refreshToken });
  const { token } = await auth.getAccessToken();
  if (!token) {
    throw new Error('Could not refresh Google token');
  }

  const response = await fetch('https://www.googleapis.com/calendar/v3/calendars/primary/events', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      summary: payload.title,
      location: payload.location ?? undefined,
      description: payload.notes ?? undefined,
      start: { dateTime: payload.startAt, timeZone: 'UTC' },
      end: { dateTime: payload.endAt, timeZone: 'UTC' },
    }),
  });

  if (!response.ok) {
    throw new Error(`Google Calendar API error: ${response.status}`);
  }

  const json = (await response.json()) as { id: string; htmlLink?: string };
  return {
    id: json.id,
    htmlLink: json.htmlLink ?? null,
  };
}

async function getRelatedTasks(db: DbHandle, userId: string, threadId: string) {
  return await db
    .select()
    .from(task)
    .where(and(eq(task.userId, userId), eq(task.emailThreadId, threadId)))
    .orderBy(desc(task.updatedAt))
    .limit(5);
}

async function getRecentMeetings(db: DbHandle, userId: string) {
  return await db
    .select()
    .from(meeting)
    .where(eq(meeting.userId, userId))
    .orderBy(desc(meeting.startsAt))
    .limit(12);
}

function summarizeMeetingRow(item: MeetingRow): z.infer<typeof assistantMeetingSummarySchema> {
  return {
    id: item.id,
    title: item.title,
    startsAt: item.startsAt.toISOString(),
    status: item.status,
    aiSummaryReady: Boolean(item.aiSummary),
  };
}

function buildRelationshipSummary(displayName: string, subject: string, unresolvedAsks: string[]) {
  if (unresolvedAsks.length) {
    return `${displayName || 'This person'} currently has unresolved asks related to ${normalizeSubject(subject) || 'your recent work'}.`;
  }
  return `${displayName || 'This person'} appears in your recent communication about ${normalizeSubject(subject) || 'ongoing work'}.`;
}

async function findRelatedMeetings(
  db: DbHandle,
  userId: string,
  subject: string,
  senderEmail?: string,
) {
  const recentMeetings = await getRecentMeetings(db, userId);
  const normalizedSubject = normalizeSubject(subject).toLowerCase();
  return recentMeetings.filter((item) => {
    const title = item.title.toLowerCase();
    const participantText = JSON.stringify(item.participants ?? []).toLowerCase();
    return (
      (normalizedSubject &&
        title.includes(normalizedSubject.slice(0, Math.min(normalizedSubject.length, 24)))) ||
      (!!senderEmail && participantText.includes(senderEmail.toLowerCase()))
    );
  });
}

async function upsertPersonMemory(
  db: DbHandle,
  input: {
    userId: string;
    email: string;
    displayName: string;
    subject: string;
    unresolvedAsks: string[];
    promises: string[];
    recentThreadIds: string[];
    recentMeetingIds: string[];
    recentTaskIds: string[];
    lastInteractionAt: Date | null;
  },
) {
  const existing = await db
    .select()
    .from(assistantPersonMemory)
    .where(
      and(
        eq(assistantPersonMemory.userId, input.userId),
        eq(assistantPersonMemory.email, input.email),
      ),
    )
    .limit(1);

  const relationshipSummary = buildRelationshipSummary(
    input.displayName || input.email,
    input.subject,
    input.unresolvedAsks,
  );

  const values = {
    id: existing[0]?.id ?? crypto.randomUUID(),
    userId: input.userId,
    email: input.email,
    displayName: input.displayName || input.email,
    company: companyFromEmail(input.email),
    relationshipSummary,
    unresolvedAsks: unique([
      ...(existing[0] ? asStringArray(existing[0].unresolvedAsks) : []),
      ...input.unresolvedAsks,
    ]).slice(0, 8),
    promises: unique([
      ...(existing[0] ? asStringArray(existing[0].promises) : []),
      ...input.promises,
    ]).slice(0, 8),
    preferredFollowUpCadenceDays: existing[0]?.preferredFollowUpCadenceDays ?? 3,
    recentThreadIds: unique([
      ...(existing[0] ? asStringArray(existing[0].recentThreadIds) : []),
      ...input.recentThreadIds,
    ]).slice(0, 8),
    recentMeetingIds: unique([
      ...(existing[0] ? asStringArray(existing[0].recentMeetingIds) : []),
      ...input.recentMeetingIds,
    ]).slice(0, 8),
    recentTaskIds: unique([
      ...(existing[0] ? asStringArray(existing[0].recentTaskIds) : []),
      ...input.recentTaskIds,
    ]).slice(0, 8),
    lastInteractionAt: input.lastInteractionAt ?? existing[0]?.lastInteractionAt ?? null,
    createdAt: existing[0]?.createdAt ?? new Date(),
    updatedAt: new Date(),
  };

  if (existing[0]) {
    await db
      .update(assistantPersonMemory)
      .set(values)
      .where(eq(assistantPersonMemory.id, existing[0].id));
  } else {
    await db.insert(assistantPersonMemory).values(values);
  }

  return values;
}

async function upsertWorkstreamMemory(
  db: DbHandle,
  input: {
    userId: string;
    key: string;
    title: string;
    summary: string;
    pendingDecisions: string[];
    risks: string[];
    relatedPeople: string[];
    relatedThreadIds: string[];
    relatedMeetingIds: string[];
    relatedTaskIds: string[];
    nextMilestone: string | null;
  },
) {
  const existing = await db
    .select()
    .from(assistantWorkstreamMemory)
    .where(
      and(
        eq(assistantWorkstreamMemory.userId, input.userId),
        eq(assistantWorkstreamMemory.key, input.key),
      ),
    )
    .limit(1);

  const values = {
    id: existing[0]?.id ?? crypto.randomUUID(),
    userId: input.userId,
    key: input.key,
    title: input.title,
    summary: input.summary,
    status: existing[0]?.status ?? 'active',
    pendingDecisions: unique([
      ...(existing[0] ? asStringArray(existing[0].pendingDecisions) : []),
      ...input.pendingDecisions,
    ]).slice(0, 8),
    risks: unique([...(existing[0] ? asStringArray(existing[0].risks) : []), ...input.risks]).slice(
      0,
      8,
    ),
    relatedPeople: unique([
      ...(existing[0] ? asStringArray(existing[0].relatedPeople) : []),
      ...input.relatedPeople,
    ]).slice(0, 8),
    relatedThreadIds: unique([
      ...(existing[0] ? asStringArray(existing[0].relatedThreadIds) : []),
      ...input.relatedThreadIds,
    ]).slice(0, 8),
    relatedMeetingIds: unique([
      ...(existing[0] ? asStringArray(existing[0].relatedMeetingIds) : []),
      ...input.relatedMeetingIds,
    ]).slice(0, 8),
    relatedTaskIds: unique([
      ...(existing[0] ? asStringArray(existing[0].relatedTaskIds) : []),
      ...input.relatedTaskIds,
    ]).slice(0, 8),
    nextMilestone: input.nextMilestone,
    createdAt: existing[0]?.createdAt ?? new Date(),
    updatedAt: new Date(),
  };

  if (existing[0]) {
    await db
      .update(assistantWorkstreamMemory)
      .set(values)
      .where(eq(assistantWorkstreamMemory.id, existing[0].id));
  } else {
    await db.insert(assistantWorkstreamMemory).values(values);
  }

  return values;
}

function toLoopRow(loop: OpenLoopRow) {
  return {
    id: loop.id,
    type: loop.type,
    queue: loop.queue,
    status: loop.status,
    title: loop.title,
    summary: loop.summary,
    confidence: loop.confidencePct / 100,
    reason: loop.reason,
    suggestedActionLabel: loop.suggestedActionLabel ?? null,
    actionLine: loop.actionLine ?? null,
    threadId: loop.sourceThreadId ?? null,
    meetingId: loop.sourceMeetingId ?? null,
    personEmail: loop.personEmail ?? null,
    workstreamKey: loop.workstreamKey ?? null,
    lastReviewedAt: safeDateString(loop.lastReviewedAt),
    snoozedUntil: safeDateString(loop.snoozedUntil),
    evidence: asEvidenceArray(loop.evidence),
  };
}

function toPreparedActionRow(action: PreparedActionRow) {
  return {
    id: action.id,
    type: action.type,
    status: action.status,
    title: action.title,
    summary: action.summary,
    confidence: action.confidencePct / 100,
    reason: action.reason,
    preview: action.preview ?? null,
    actionLine: action.actionLine ?? null,
    threadId: action.sourceThreadId ?? null,
    meetingId: action.sourceMeetingId ?? null,
    personEmail: action.personEmail ?? null,
    workstreamKey: action.workstreamKey ?? null,
    payload: asRecord(action.payload),
    evidence: asEvidenceArray(action.evidence),
  };
}

async function syncOpenLoops(
  db: DbHandle,
  userId: string,
  threadId: string | null,
  candidates: OpenLoopCandidate[],
) {
  const existing = candidates.length
    ? await db
        .select()
        .from(assistantOpenLoop)
        .where(
          and(
            eq(assistantOpenLoop.userId, userId),
            inArray(
              assistantOpenLoop.uniqueKey,
              candidates.map((candidate) => candidate.uniqueKey),
            ),
          ),
        )
    : [];

  const existingMap = new Map(existing.map((item) => [item.uniqueKey, item]));
  const now = new Date();

  for (const candidate of candidates) {
    const current = existingMap.get(candidate.uniqueKey);
    const nextValues = {
      id: current?.id ?? crypto.randomUUID(),
      userId,
      uniqueKey: candidate.uniqueKey,
      type: candidate.type,
      queue: candidate.queue,
      status: current?.status ?? candidate.status,
      title: candidate.title,
      summary: candidate.summary,
      confidencePct: Math.round(candidate.confidence * 100),
      reason: candidate.reason,
      suggestedActionLabel: candidate.suggestedActionLabel ?? null,
      actionLine: candidate.actionLine ?? null,
      sourceThreadId: candidate.sourceThreadId ?? null,
      sourceMeetingId: candidate.sourceMeetingId ?? null,
      sourceTaskId: candidate.sourceTaskId ?? null,
      sourceEventId: candidate.sourceEventId ?? null,
      personEmail: candidate.personEmail ?? null,
      workstreamKey: candidate.workstreamKey ?? null,
      evidence: candidate.evidence,
      snoozedUntil: current?.snoozedUntil ?? null,
      lastReviewedAt: current?.lastReviewedAt ?? null,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    };

    if (current) {
      await db
        .update(assistantOpenLoop)
        .set(nextValues)
        .where(eq(assistantOpenLoop.id, current.id));
    } else {
      await db.insert(assistantOpenLoop).values(nextValues);
    }
  }

  if (threadId) {
    const obsolete = await db
      .select()
      .from(assistantOpenLoop)
      .where(
        and(eq(assistantOpenLoop.userId, userId), eq(assistantOpenLoop.sourceThreadId, threadId)),
      );
    const currentKeys = new Set(candidates.map((candidate) => candidate.uniqueKey));
    for (const row of obsolete) {
      if (!currentKeys.has(row.uniqueKey) && row.status === 'open') {
        await db
          .update(assistantOpenLoop)
          .set({ status: 'done', updatedAt: now })
          .where(eq(assistantOpenLoop.id, row.id));
      }
    }
  }
}

async function syncPreparedActions(
  db: DbHandle,
  userId: string,
  threadId: string | null,
  candidates: PreparedActionCandidate[],
) {
  const existing = candidates.length
    ? await db
        .select()
        .from(assistantPreparedAction)
        .where(
          and(
            eq(assistantPreparedAction.userId, userId),
            inArray(
              assistantPreparedAction.uniqueKey,
              candidates.map((candidate) => candidate.uniqueKey),
            ),
          ),
        )
    : [];
  const existingMap = new Map(existing.map((item) => [item.uniqueKey, item]));
  const now = new Date();

  for (const candidate of candidates) {
    const current = existingMap.get(candidate.uniqueKey);
    const nextValues = {
      id: current?.id ?? crypto.randomUUID(),
      userId,
      uniqueKey: candidate.uniqueKey,
      type: candidate.type,
      status: current?.status ?? candidate.status,
      title: candidate.title,
      summary: candidate.summary,
      confidencePct: Math.round(candidate.confidence * 100),
      reason: candidate.reason,
      preview: candidate.preview ?? null,
      actionLine: candidate.actionLine ?? null,
      payload: candidate.payload,
      sourceThreadId: candidate.sourceThreadId ?? null,
      sourceMeetingId: candidate.sourceMeetingId ?? null,
      personEmail: candidate.personEmail ?? null,
      workstreamKey: candidate.workstreamKey ?? null,
      evidence: candidate.evidence,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    };

    if (current) {
      await db
        .update(assistantPreparedAction)
        .set(nextValues)
        .where(eq(assistantPreparedAction.id, current.id));
    } else {
      await db.insert(assistantPreparedAction).values(nextValues);
    }
  }

  if (threadId) {
    const obsolete = await db
      .select()
      .from(assistantPreparedAction)
      .where(
        and(
          eq(assistantPreparedAction.userId, userId),
          eq(assistantPreparedAction.sourceThreadId, threadId),
        ),
      );
    const currentKeys = new Set(candidates.map((candidate) => candidate.uniqueKey));
    for (const row of obsolete) {
      if (!currentKeys.has(row.uniqueKey) && row.status === 'pending') {
        await db
          .update(assistantPreparedAction)
          .set({ status: 'dismissed', updatedAt: now })
          .where(eq(assistantPreparedAction.id, row.id));
      }
    }
  }
}

async function buildThreadAnalysis(
  db: DbHandle,
  input: {
    userId: string;
    activeConnection: NonNullable<Awaited<ReturnType<typeof getActiveConnection>>>;
    threadId: string;
    thread: Awaited<ReturnType<typeof getThread>>['result'];
  },
) {
  const { userId, activeConnection, threadId, thread } = input;
  const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
  const subject = latest?.subject || '';
  const senderName = latest?.sender?.name || latest?.sender?.email || 'the sender';
  const senderEmail = latest?.sender?.email;
  const latestText = latestMessageText(thread);
  const threadKind = classifyThreadKind(thread);
  // Extract "smart action" payloads when applicable. We only run the
  // extractor matching the kind so a noisy receipt body doesn't accidentally
  // produce a bogus verification code, and vice versa.
  const extractedCode =
    threadKind === 'verification' ? extractVerificationCode(latestText) : null;
  const extractedReceipt = threadKind === 'receipt' ? extractReceiptDetails(thread) : null;

  // Non-conversational kinds (receipts, notifications, marketing, verification)
  // never require a human reply, even if their bodies happen to contain reply
  // keywords like "please" or action-item phrases. This was the source of
  // the receipt-as-urgent-reply briefing bug. Keep these in lockstep with the
  // classifier's kind enum.
  const isNonConversational =
    threadKind === 'receipt' ||
    threadKind === 'notification' ||
    threadKind === 'marketing' ||
    threadKind === 'verification';

  // B-022: short-circuit for non-conversational threads BEFORE the expensive DB
  // reads (getRelatedTasks / findRelatedMeetings / getThreadSummary), the memory
  // upserts (upsertPersonMemory / upsertWorkstreamMemory), candidate generation,
  // and the batched LLM action-line call. None of those outputs are wanted for
  // receipts / notifications / marketing / verification — that's the entire
  // point of classifying them — and the callers already zero every actionable
  // field out for these kinds (`isConversational ? … : []` in getThreadContext;
  // syncRecentThreads discards the result entirely).
  //
  // We deliberately do NOT call syncOpenLoops / syncPreparedActions with empty
  // arrays here: both are destructive when `threadId` is non-null (their
  // obsolete-reconciliation block flips every existing `open` loop to `done` and
  // every `pending` action to `dismissed`). If a thread was previously
  // conversational and is now reclassified, passing [] would silently retire
  // legitimately-created loops/actions. Skipping the sync leaves prior rows
  // untouched; we still read back whatever already exists so the shape matches.
  if (isNonConversational) {
    const workstreamKey = normalizeWorkstreamKey(subject);
    // Build a workstream object matching upsertWorkstreamMemory's return shape
    // WITHOUT writing to the DB. No caller reads analysis.workstream, but we
    // keep the field shape identical so the inferred return type stays stable.
    const now = new Date();
    const workstream = {
      id: crypto.randomUUID(),
      userId,
      key: workstreamKey,
      title: normalizeSubject(subject) || 'General',
      summary: '',
      status: 'active' as const,
      pendingDecisions: [] as string[],
      risks: [] as string[],
      relatedPeople: [] as string[],
      relatedThreadIds: [] as string[],
      relatedMeetingIds: [] as string[],
      relatedTaskIds: [] as string[],
      nextMilestone: null as string | null,
      createdAt: now,
      updatedAt: now,
    };

    // Read back any rows that already exist for this thread (e.g. from a prior
    // conversational classification) so we neither create nor destroy data, and
    // the returned collections stay correctly typed as DB rows.
    const openLoops = await db
      .select()
      .from(assistantOpenLoop)
      .where(
        and(eq(assistantOpenLoop.userId, userId), eq(assistantOpenLoop.sourceThreadId, threadId)),
      )
      .orderBy(desc(assistantOpenLoop.updatedAt));
    const preparedActions = await db
      .select()
      .from(assistantPreparedAction)
      .where(
        and(
          eq(assistantPreparedAction.userId, userId),
          eq(assistantPreparedAction.sourceThreadId, threadId),
        ),
      )
      .orderBy(desc(assistantPreparedAction.updatedAt));

    return {
      subject,
      summary: '',
      // buildAiLeadLine returns '' for every non-conversational kind anyway.
      aiLeadLine: '',
      threadKind,
      extractedCode,
      extractedReceipt,
      recommendation: {
        label: 'Nothing needed',
        reason: 'The assistant does not see a strong follow-up obligation right now.',
      },
      waitingState: 'done' as WaitingState,
      confidence: 0.25,
      riskLevel: 'low' as AssistantRisk,
      reason:
        'This thread looks like an automated / non-conversational message, so the assistant is staying out of the way.',
      actionItems: [] as string[],
      researchQueries: [] as string[],
      relatedTasks: [] as Awaited<ReturnType<typeof getRelatedTasks>>,
      relatedMeetings: [] as Awaited<ReturnType<typeof findRelatedMeetings>>,
      openLoops,
      preparedActions,
      peopleContext: [] as Awaited<ReturnType<typeof upsertPersonMemory>>[],
      workstream,
      latest,
    };
  }

  const relatedTasks = await getRelatedTasks(db, userId, threadId);
  const relatedMeetings = await findRelatedMeetings(db, userId, subject, senderEmail);
  const summary = await getThreadSummary(threadId, activeConnection.id, thread);
  const actionItems = extractActionItems(latestText, subject, senderName);
  const meetingRequested = MEETING_KEYWORDS.test(`${subject} ${latestText}`);
  const urgent = URGENT_KEYWORDS.test(`${subject} ${latestText}`);
  const automated =
    AUTOMATED_KEYWORDS.test(`${subject} ${latestText}`) ||
    AUTOMATED_KEYWORDS.test(senderEmail ?? '');
  const latestFromUser =
    (latest?.sender?.email || '').toLowerCase() === activeConnection.email.toLowerCase();
  const replyNeeded =
    !automated &&
    !isNonConversational &&
    !latestFromUser &&
    (REPLY_KEYWORDS.test(latestText) || meetingRequested || urgent || actionItems.length > 0);
  const waitingOnOther = !automated && latestFromUser;
  const likelyDropped = replyNeeded && !thread.hasUnread && relatedTasks.length === 0;
  const baseConfidence = automated
    ? 0.25
    : waitingOnOther
      ? 0.82
      : replyNeeded
        ? 0.9
        : meetingRequested
          ? 0.78
          : 0.62;
  const confidence = Math.min(
    0.99,
    Math.max(
      0.25,
      baseConfidence +
        (relatedTasks.length > 0 ? 0.04 : 0) +
        (relatedMeetings.length > 0 ? 0.03 : 0),
    ),
  );
  const suggestedEvent = extractEventSuggestion(
    subject,
    latestText,
    new Date(latest?.receivedOn ?? Date.now()),
  );
  const researchQueries = createResearchQueries(subject, senderEmail, latestText);
  const riskLevel: AssistantRisk = automated
    ? 'high'
    : urgent || /invoice|contract|legal|security|vendor|policy/i.test(latestText)
      ? 'medium'
      : 'low';
  const workstreamKey = normalizeWorkstreamKey(subject);
  const displayName = latest?.sender?.name || latest?.sender?.email || 'Unknown';

  const peopleContext = senderEmail
    ? [
        await upsertPersonMemory(db, {
          userId,
          email: senderEmail,
          displayName,
          subject,
          unresolvedAsks: actionItems,
          promises: waitingOnOther
            ? [`Waiting for a response on ${normalizeSubject(subject) || 'this thread'}`]
            : [],
          recentThreadIds: [threadId],
          recentMeetingIds: relatedMeetings.map((item) => item.id),
          recentTaskIds: relatedTasks.map((item) => item.id),
          lastInteractionAt: latest?.receivedOn ? new Date(latest.receivedOn) : null,
        }),
      ]
    : [];

  const workstream = await upsertWorkstreamMemory(db, {
    userId,
    key: workstreamKey,
    title: normalizeSubject(subject) || 'General',
    summary,
    pendingDecisions: actionItems.filter((item) => /decide|confirm|approve|review/i.test(item)),
    risks: urgent ? ['This thread looks time-sensitive.'] : [],
    relatedPeople: senderEmail ? [senderEmail] : [],
    relatedThreadIds: [threadId],
    relatedMeetingIds: relatedMeetings.map((item) => item.id),
    relatedTaskIds: relatedTasks.map((item) => item.id),
    nextMilestone: suggestedEvent?.startAt
      ? 'Confirm scheduling details'
      : (actionItems[0] ?? null),
  });

  const waitingState: WaitingState = replyNeeded
    ? 'waiting_on_me'
    : waitingOnOther
      ? 'waiting_on_them'
      : actionItems.length === 0
        ? 'done'
        : 'unclear';

  const recommendation = replyNeeded
    ? {
        label: 'Reply now',
        reason: 'The latest message asks for something actionable and you are the next blocker.',
      }
    : actionItems.length > 0 && relatedTasks.length === 0
      ? {
          label: 'Turn into task',
          reason: 'The thread contains an actionable ask that is not yet represented as a task.',
        }
      : meetingRequested && !relatedMeetings.length
        ? {
            label: 'Schedule follow-up',
            reason:
              'This thread looks like scheduling coordination and is not yet connected to a meeting.',
          }
        : waitingOnOther
          ? {
              label: 'Waiting on them',
              reason: 'Your latest outbound message already moved the thread forward.',
            }
          : {
              label: 'Nothing needed',
              reason: 'The assistant does not see a strong follow-up obligation right now.',
            };

  const loopCandidates: OpenLoopCandidate[] = [];
  const actionCandidates: PreparedActionCandidate[] = [];

  const commonEvidence = [
    { kind: 'thread' as const, id: threadId, label: subject || 'Thread' },
    ...(senderEmail ? [{ kind: 'person' as const, id: senderEmail, label: displayName }] : []),
    { kind: 'workstream' as const, id: workstreamKey, label: workstream.title },
  ];

  if (replyNeeded) {
    loopCandidates.push({
      uniqueKey: `thread:${threadId}:needs_reply`,
      type: 'needs_reply',
      queue: 'needs_you',
      status: 'open',
      title: `Reply to ${displayName}`,
      summary: actionItems[0] || summary,
      confidence,
      reason: 'The latest inbound message appears to require a reply.',
      suggestedActionLabel: 'Draft reply',
      sourceThreadId: threadId,
      sourceMeetingId: null,
      sourceTaskId: null,
      sourceEventId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
    actionCandidates.push({
      uniqueKey: `thread:${threadId}:draft_reply`,
      type: 'draft_reply',
      status: 'pending',
      title: `Draft reply for ${displayName}`,
      summary: actionItems[0] || 'Prepared draft based on thread context.',
      confidence,
      reason: 'This thread has enough context to prepare a reply for approval.',
      preview: null,
      payload: { threadId },
      sourceThreadId: threadId,
      sourceMeetingId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  if (waitingOnOther) {
    loopCandidates.push({
      uniqueKey: `thread:${threadId}:waiting_on_other`,
      type: 'waiting_on_other',
      queue: 'waiting_on',
      status: 'open',
      title: `Waiting on ${displayName}`,
      summary: `You already replied in ${normalizeSubject(subject) || 'this thread'} and are now waiting for them.`,
      confidence,
      reason: 'The latest message in the thread was sent by you.',
      suggestedActionLabel: 'Review context',
      sourceThreadId: threadId,
      sourceMeetingId: null,
      sourceTaskId: null,
      sourceEventId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  // Don't surface deadline risk for receipts/notifications/marketing — these
  // often contain urgent-sounding phrases ("by end of day", "today") that
  // aren't directed at the user.
  if (!isNonConversational && (likelyDropped || urgent)) {
    loopCandidates.push({
      uniqueKey: `thread:${threadId}:deadline_risk`,
      type: urgent ? 'deadline_risk' : 'decision_needed',
      queue: 'likely_dropped',
      status: 'open',
      title: urgent
        ? `Deadline risk in ${normalizeSubject(subject) || 'thread'}`
        : `Decision still pending`,
      summary: urgent
        ? 'The thread contains urgency or timing language and no linked task yet.'
        : 'This thread no longer stands out as unread, but still appears actionable.',
      confidence,
      reason: urgent
        ? 'Urgent or deadline keywords were detected.'
        : 'The thread is actionable but may slip without explicit tracking.',
      suggestedActionLabel: actionItems.length ? 'Create task' : 'Review thread',
      sourceThreadId: threadId,
      sourceMeetingId: null,
      sourceTaskId: null,
      sourceEventId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  if (meetingRequested) {
    loopCandidates.push({
      uniqueKey: `thread:${threadId}:meeting_follow_up`,
      type: 'meeting_follow_up',
      queue: 'scheduling',
      status: 'open',
      title: `Scheduling follow-up`,
      summary: suggestedEvent?.startAt
        ? 'The assistant extracted a likely meeting slot from this thread.'
        : 'The thread looks like meeting coordination and may need a calendar event.',
      confidence,
      reason: 'Scheduling language was detected in the thread.',
      suggestedActionLabel: 'Create event',
      sourceThreadId: threadId,
      sourceMeetingId: relatedMeetings[0]?.id ?? null,
      sourceTaskId: null,
      sourceEventId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  if (thread.isLatestDraft) {
    loopCandidates.push({
      uniqueKey: `thread:${threadId}:draft_ready`,
      type: 'draft_ready',
      queue: 'drafts_ready',
      status: 'open',
      title: `Draft ready to review`,
      summary: 'A draft already exists on this thread.',
      confidence,
      reason: 'A thread draft is already attached.',
      suggestedActionLabel: 'Open draft',
      sourceThreadId: threadId,
      sourceMeetingId: null,
      sourceTaskId: null,
      sourceEventId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  if (actionItems.length > 0 && relatedTasks.length === 0) {
    actionCandidates.push({
      uniqueKey: `thread:${threadId}:create_task`,
      type: 'create_task',
      status: 'pending',
      title: `Turn thread into tasks`,
      summary: actionItems[0],
      confidence,
      reason: 'Actionable asks were found without a linked task.',
      preview: actionItems
        .slice(0, 3)
        .map((item) => `• ${item}`)
        .join('\n'),
      payload: {
        tasks: actionItems.slice(0, 3).map((item) => ({
          title: item,
          description: item,
          priority: urgent ? 'high' : 'medium',
          dueDate: inferDueDate(item, new Date(latest?.receivedOn ?? Date.now())),
        })),
      },
      sourceThreadId: threadId,
      sourceMeetingId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  if (suggestedEvent) {
    actionCandidates.push({
      uniqueKey: `thread:${threadId}:create_event`,
      type: 'create_event',
      status: 'pending',
      title: `Create calendar event`,
      summary: suggestedEvent.title,
      confidence,
      reason: 'This thread contains scheduling language and a likely event suggestion.',
      preview: suggestedEvent.startAt
        ? `${suggestedEvent.title} · ${suggestedEvent.startAt}`
        : suggestedEvent.title,
      payload: suggestedEvent,
      sourceThreadId: threadId,
      sourceMeetingId: relatedMeetings[0]?.id ?? null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  if (researchQueries.length > 0) {
    loopCandidates.push({
      uniqueKey: `thread:${threadId}:research_needed`,
      type: 'research_needed',
      queue: 'likely_dropped',
      status: 'open',
      title: `Double-check details`,
      summary: researchQueries[0],
      confidence: Math.max(0.55, confidence - 0.15),
      reason: 'This thread contains terms that benefit from external verification.',
      suggestedActionLabel: 'Research',
      sourceThreadId: threadId,
      sourceMeetingId: null,
      sourceTaskId: null,
      sourceEventId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
    actionCandidates.push({
      uniqueKey: `thread:${threadId}:research`,
      type: 'research',
      status: 'pending',
      title: `Research before acting`,
      summary: researchQueries[0],
      confidence: Math.max(0.55, confidence - 0.15),
      reason: 'The assistant recommends checking external facts before acting.',
      preview: researchQueries.join('\n'),
      payload: { queries: researchQueries, threadId },
      sourceThreadId: threadId,
      sourceMeetingId: null,
      personEmail: senderEmail ?? null,
      workstreamKey,
      evidence: commonEvidence,
    });
  }

  // Fan-out one batched LLM call per thread to produce verb-first sentences
  // ("Reply to Sarah about the Q4 proposal") for every candidate. Best-effort:
  // returns {} on disabled flag, timeout, or model failure → actionLine stays
  // null on each candidate and the client falls back to title+summary render.
  const actionLines = await generateActionLines({
    senderName,
    senderEmail: senderEmail ?? '',
    subject,
    snippet: latestText.slice(0, 400),
    candidates: [
      ...loopCandidates.map((c) => ({
        uniqueKey: c.uniqueKey,
        kind: c.type,
        fallback: c.title,
      })),
      ...actionCandidates.map((c) => ({
        uniqueKey: c.uniqueKey,
        kind: c.type,
        fallback: c.title,
      })),
    ],
  });
  for (const c of loopCandidates) c.actionLine = actionLines[c.uniqueKey] ?? null;
  for (const c of actionCandidates) c.actionLine = actionLines[c.uniqueKey] ?? null;

  await syncOpenLoops(db, userId, threadId, loopCandidates);
  await syncPreparedActions(db, userId, threadId, actionCandidates);

  const openLoops = await db
    .select()
    .from(assistantOpenLoop)
    .where(
      and(eq(assistantOpenLoop.userId, userId), eq(assistantOpenLoop.sourceThreadId, threadId)),
    )
    .orderBy(desc(assistantOpenLoop.updatedAt));
  const preparedActions = await db
    .select()
    .from(assistantPreparedAction)
    .where(
      and(
        eq(assistantPreparedAction.userId, userId),
        eq(assistantPreparedAction.sourceThreadId, threadId),
      ),
    )
    .orderBy(desc(assistantPreparedAction.updatedAt));

  const aiLeadLine = buildAiLeadLine({
    threadKind,
    meetingRequested,
    suggestedEvent,
    actionItems,
    bodyText: latestText,
    summary,
  });

  return {
    subject,
    summary,
    aiLeadLine,
    threadKind,
    extractedCode,
    extractedReceipt,
    recommendation,
    waitingState,
    confidence,
    riskLevel,
    reason: automated
      ? 'The latest message looks automated, so the assistant is being conservative.'
      : recommendation.reason,
    actionItems,
    researchQueries,
    relatedTasks,
    relatedMeetings,
    openLoops,
    preparedActions,
    peopleContext,
    workstream,
    latest,
  };
}

async function syncRecentThreads(
  db: DbHandle,
  userId: string,
  activeConnection: NonNullable<Awaited<ReturnType<typeof getActiveConnection>>>,
) {
  const threadRefs = await getThreadsFromDB(activeConnection.id, {
    folder: 'inbox',
    maxResults: 8,
  });
  for (const threadRef of threadRefs.threads.slice(0, 6)) {
    try {
      const { result } = await getThread(activeConnection.id, threadRef.id);
      await buildThreadAnalysis(db, {
        userId,
        activeConnection,
        threadId: threadRef.id,
        thread: result,
      });
    } catch (error) {
      console.warn('[assistant.syncRecentThreads] Failed to sync thread', threadRef.id, error);
    }
  }
}

async function syncMeetingActions(db: DbHandle, userId: string) {
  const meetings = await db
    .select()
    .from(meeting)
    .where(eq(meeting.userId, userId))
    .orderBy(desc(meeting.updatedAt))
    .limit(8);

  const candidates = meetings
    .filter((item) => asStringArray(item.actionItems).length > 0)
    .map((item) => ({
      uniqueKey: `meeting:${item.id}:action_items`,
      type: 'create_task' as const,
      status: 'pending' as const,
      title: `Review meeting action items`,
      summary: `Meeting "${item.title}" produced ${asStringArray(item.actionItems).length} action item${asStringArray(item.actionItems).length > 1 ? 's' : ''}.`,
      confidence: 0.86,
      reason: 'Meeting recap already extracted actionable follow-ups.',
      preview: asStringArray(item.actionItems)
        .slice(0, 3)
        .map((entry) => `• ${entry}`)
        .join('\n'),
      payload: {
        meetingId: item.id,
        tasks: asStringArray(item.actionItems)
          .slice(0, 5)
          .map((entry) => ({
            title: entry,
            description: `From meeting: ${item.title}`,
            priority: 'medium',
            dueDate: null,
          })),
      },
      sourceThreadId: null,
      sourceMeetingId: item.id,
      personEmail: null,
      workstreamKey: normalizeWorkstreamKey(item.title),
      evidence: [{ kind: 'meeting' as const, id: item.id, label: item.title }],
    }));

  await syncPreparedActions(db, userId, null, candidates);
}

async function generateDraftForThread(
  activeConnection: NonNullable<Awaited<ReturnType<typeof getActiveConnection>>>,
  sessionUser: { id: string; name: string },
  threadId: string,
  openInComposer: boolean,
) {
  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
  try {
    const { result: thread } = await getThread(activeConnection.id, threadId);
    if (thread.isLatestDraft) {
      return { draftId: null, created: false, reason: 'Draft already exists for this thread.' };
    }

    const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
    const latestBody = latestMessageText(thread);
    const relatedTasks = await getRelatedTasks(db, sessionUser.id, threadId);
    const suggestedEvent = extractEventSuggestion(
      latest?.subject || '',
      latestBody,
      new Date(latest?.receivedOn ?? Date.now()),
    );
    const personMemory = latest?.sender?.email
      ? await db
          .select()
          .from(assistantPersonMemory)
          .where(
            and(
              eq(assistantPersonMemory.userId, sessionUser.id),
              eq(assistantPersonMemory.email, latest.sender.email),
            ),
          )
          .limit(1)
      : [];

    const taskContext = relatedTasks.length
      ? `\nRelated tasks:\n${relatedTasks.map((item) => `- ${item.title}`).join('\n')}`
      : '';
    const eventContext = suggestedEvent?.startAt
      ? `\nUpcoming event context:\n- ${suggestedEvent.title} at ${suggestedEvent.startAt}`
      : '';
    const personContext = personMemory[0]
      ? `\nPeople context:\n- ${personMemory[0].relationshipSummary}`
      : '';

    const prompt = `Draft a helpful reply to this email thread.${taskContext}${eventContext}${personContext}\n\nKeep it concise, proactive, and ready to send after review.`;

    const threadMessages = thread.messages.map((message) => ({
      from: message.sender?.name || message.sender?.email || 'Unknown',
      to: message.to?.map((recipient) => recipient.name || recipient.email) || [],
      cc: message.cc?.map((recipient) => recipient.name || recipient.email) || [],
      subject: message.subject || '',
      body: cleanText(message.decodedBody || message.body || ''),
    }));

    const generatedBody = await composeEmail({
      prompt,
      threadMessages,
      username: sessionUser.name,
      connectionId: activeConnection.id,
    });

    const recipientEmail = latest?.sender?.email?.trim();
    if (!recipientEmail) {
      throw new TRPCError({
        code: 'BAD_REQUEST',
        message: 'Could not determine a recipient email address for this draft.',
      });
    }

    const draftPayload = {
      to: recipientEmail,
      cc:
        latest?.cc
          ?.map((recipient) => recipient.email)
          .filter((email) => email !== activeConnection.email)
          .join(', ') ?? '',
      bcc: '',
      subject: latest?.subject?.startsWith('Re: ')
        ? latest.subject
        : `Re: ${latest?.subject || 'No Subject'}`,
      message: generatedBody.replace(/\n/g, '<br>'),
      attachments: [],
      id: null,
      threadId,
      fromEmail: activeConnection.email,
    };

    const { stub: agent } = await getZeroAgent(activeConnection.id);
    const createdDraft = await agent.createDraft(draftPayload);
    return {
      draftId: createdDraft?.id ?? null,
      created: true,
      reason: openInComposer ? 'Assistant draft opened.' : 'Assistant draft prepared.',
      preview: generatedBody,
    };
  } finally {
    await conn.end();
  }
}

async function buildChangeFeed(db: DbHandle, userId: string) {
  const [loops, actions, meetings] = await Promise.all([
    db
      .select()
      .from(assistantOpenLoop)
      .where(eq(assistantOpenLoop.userId, userId))
      .orderBy(desc(assistantOpenLoop.updatedAt))
      .limit(4),
    db
      .select()
      .from(assistantPreparedAction)
      .where(eq(assistantPreparedAction.userId, userId))
      .orderBy(desc(assistantPreparedAction.updatedAt))
      .limit(4),
    db
      .select()
      .from(meeting)
      .where(eq(meeting.userId, userId))
      .orderBy(desc(meeting.updatedAt))
      .limit(4),
  ]);

  const changes = [
    ...loops.map((loop) => ({
      id: loop.id,
      type: 'open_loop' as const,
      title: loop.title,
      summary: loop.summary,
      occurredAt: loop.updatedAt.toISOString(),
    })),
    ...actions.map((action) => ({
      id: action.id,
      type: 'prepared_action' as const,
      title: action.title,
      summary: action.summary,
      occurredAt: action.updatedAt.toISOString(),
    })),
    ...meetings
      .filter((item) => Boolean(item.aiSummary) || asStringArray(item.actionItems).length > 0)
      .map((item) => ({
        id: item.id,
        type: 'meeting' as const,
        title: item.title,
        summary: item.aiSummary || 'Meeting recap generated.',
        occurredAt: item.updatedAt.toISOString(),
      })),
  ]
    .sort((a, b) => +new Date(b.occurredAt) - +new Date(a.occurredAt))
    .slice(0, 6);

  return changes;
}

const isMissingAssistantSchemaError = (error: unknown) =>
  error instanceof Error &&
  (error.message.includes('relation "mail0_meeting" does not exist') ||
    error.message.includes('relation "mail0_assistant_open_loop" does not exist') ||
    error.message.includes('relation "mail0_assistant_prepared_action" does not exist') ||
    error.message.includes('relation "mail0_assistant_briefing_snapshot" does not exist'));

const isBriefingShardCapacityError = (error: unknown) =>
  error instanceof Error &&
  (error.message.includes('Timed out while waiting for an open slot in the pool') ||
    error.message.includes('Shard initialization failed') ||
    error.message.includes('Failed to execute operations across shards'));

/// Recognized degraded-schema errors for the briefing endpoint. Either the assistant
/// tables haven't been migrated yet, OR `mail0_connection.color` is missing (migration
/// 0047 not yet applied to this environment), OR the non-critical shard fan-out is
/// temporarily saturated and cannot acquire a Postgres slot. All of these should degrade
/// to the lightweight fallback briefing instead of taking Home down with a 500.
const shouldFallBackForBriefing = (error: unknown) =>
  isMissingAssistantSchemaError(error) ||
  isMissingConnectionColorError(error) ||
  isBriefingShardCapacityError(error);

/// Minimal thread context returned when the assistant DB tables are missing (e.g. on a
/// fresh deploy that hasn't run migrations yet). Surfaces a usable summary from the
/// thread itself instead of bubbling a 500 to the client.
function buildFallbackThreadContext(
  threadId: string,
  thread: Awaited<ReturnType<typeof getThread>>['result'],
) {
  const latest = thread.latest ?? thread.messages[thread.messages.length - 1];
  const fallbackKind = classifyThreadKind(thread);
  return assistantThreadContextSchema.parse({
    threadId,
    subject: latest?.subject ?? '',
    summary: buildFallbackSummary(thread),
    // No analysis available in fallback mode — leave empty so the card hides.
    aiLeadLine: '',
    threadKind: fallbackKind,
    extractedCode:
      fallbackKind === 'verification'
        ? extractVerificationCode(latestMessageText(thread))
        : null,
    extractedReceipt: fallbackKind === 'receipt' ? extractReceiptDetails(thread) : null,
    recommendation: {
      label: 'No recommendation',
      reason: 'Assistant tables are not yet provisioned for this environment.',
    },
    waitingState: 'unclear' as const,
    confidence: 0,
    riskLevel: 'low' as const,
    reason: 'Assistant context is unavailable until the database schema is migrated.',
    replyNeeded: false,
    followUpNeeded: false,
    meetingRequested: false,
    existingDraft: false,
    actionItems: [],
    researchQueries: [],
    suggestedTasks: [],
    suggestedEvent: null,
    relatedTasks: [],
    relatedMeetings: [],
    people: [],
    openLoops: [],
    preparedActions: [],
    changedSinceLastOpen: [],
  });
}

async function buildFallbackBriefing(db: DbHandle, userId: string) {
  const now = new Date();
  const tasks = await db
    .select()
    .from(task)
    .where(and(eq(task.userId, userId), inArray(task.status, ['todo', 'doing'])))
    .orderBy(desc(task.updatedAt))
    .limit(8)
    .catch(() => []);

  const topTask = tasks.sort((a, b) => {
    if (a.dueDate && b.dueDate) return +new Date(a.dueDate) - +new Date(b.dueDate);
    if (a.dueDate) return -1;
    if (b.dueDate) return 1;
    return +new Date(b.updatedAt) - +new Date(a.updatedAt);
  })[0];

  return {
    generatedAt: now.toISOString(),
    today: {
      nextEvent: null,
      topTask: topTask
        ? {
            id: topTask.id,
            title: topTask.title,
            dueDate: safeDateString(topTask.dueDate),
            priority: topTask.priority,
          }
        : null,
      urgentReply: null,
    },
    topPriorities: topTask
      ? [
          {
            kind: 'task' as const,
            id: topTask.id,
            title: topTask.title,
            summary: topTask.dueDate
              ? `Due ${new Date(topTask.dueDate).toLocaleString()}`
              : 'Active task without a due date.',
          },
        ]
      : [],
    needsYou: [],
    waitingOn: [],
    prepared: [],
    upcomingMeetings: [],
    changedSinceLastTime: [],
  };
}

export const assistantRouter = router({
  getBriefing: privateProcedure.output(assistantBriefingSchema).query(async ({ ctx }) => {
    const activeConnection = await getActiveConnection().catch(() => null);
    const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
    try {
      try {
        if (activeConnection) {
          await syncRecentThreads(db, ctx.sessionUser.id, activeConnection);
        }
        await syncMeetingActions(db, ctx.sessionUser.id);
      } catch (error) {
        if (shouldFallBackForBriefing(error)) {
          console.warn(
            '[assistant.getBriefing] Returning fallback briefing — degraded schema (missing assistant tables or mail0_connection.color)',
            error instanceof Error ? error.message : error,
          );
          return await buildFallbackBriefing(db, ctx.sessionUser.id);
        }
        throw error;
      }

      const now = new Date();
      const loadBriefingData = () =>
        Promise.all([
          db
            .select()
            .from(assistantOpenLoop)
            .where(eq(assistantOpenLoop.userId, ctx.sessionUser.id))
            .orderBy(desc(assistantOpenLoop.updatedAt))
            .limit(20),
          db
            .select()
            .from(assistantPreparedAction)
            .where(eq(assistantPreparedAction.userId, ctx.sessionUser.id))
            .orderBy(desc(assistantPreparedAction.updatedAt))
            .limit(12),
          db
            .select()
            .from(task)
            .where(
              and(eq(task.userId, ctx.sessionUser.id), inArray(task.status, ['todo', 'doing'])),
            )
            .orderBy(desc(task.updatedAt))
            .limit(8),
          db
            .select()
            .from(meeting)
            .where(eq(meeting.userId, ctx.sessionUser.id))
            .orderBy(desc(meeting.startsAt))
            .limit(8),
          buildChangeFeed(db, ctx.sessionUser.id),
        ] as const);

      let briefingData: Awaited<ReturnType<typeof loadBriefingData>>;
      try {
        briefingData = await loadBriefingData();
      } catch (error) {
        if (shouldFallBackForBriefing(error)) {
          console.warn(
            '[assistant.getBriefing] Returning fallback briefing — degraded schema (missing assistant tables or mail0_connection.color)',
            error instanceof Error ? error.message : error,
          );
          return await buildFallbackBriefing(db, ctx.sessionUser.id);
        }
        throw error;
      }
      const [loops, preparedActions, tasks, meetings, changedSinceLastTime] = briefingData;

      const activeLoops = loops.filter((loop) => {
        if (loop.status === 'open') return true;
        if (loop.status === 'snoozed' && loop.snoozedUntil) return loop.snoozedUntil <= now;
        return false;
      });
      const pendingActions = preparedActions.filter((action) => action.status === 'pending');
      const nextEvent = meetings
        .filter((item) => item.startsAt >= now)
        .sort((a, b) => +a.startsAt - +b.startsAt)[0];
      const topTask = tasks.sort((a, b) => {
        if (a.dueDate && b.dueDate) return +new Date(a.dueDate) - +new Date(b.dueDate);
        if (a.dueDate) return -1;
        if (b.dueDate) return 1;
        return +new Date(b.updatedAt) - +new Date(a.updatedAt);
      })[0];

      const topPriorities = [
        ...activeLoops
          .filter((loop) => loop.queue === 'needs_you' || loop.queue === 'likely_dropped')
          .slice(0, 2)
          .map((loop) => ({
            kind: 'open_loop' as const,
            id: loop.id,
            title: loop.title,
            summary: loop.summary,
          })),
        ...(topTask
          ? [
              {
                kind: 'task' as const,
                id: topTask.id,
                title: topTask.title,
                summary: topTask.dueDate
                  ? `Due ${new Date(topTask.dueDate).toLocaleString()}`
                  : 'Active task without a due date.',
              },
            ]
          : []),
        ...pendingActions.slice(0, 1).map((action) => ({
          kind: 'prepared_action' as const,
          id: action.id,
          title: action.title,
          summary: action.summary,
        })),
      ].slice(0, 3);

      const briefing = {
        generatedAt: now.toISOString(),
        today: {
          nextEvent: nextEvent ? summarizeMeetingRow(nextEvent) : null,
          topTask: topTask
            ? {
                id: topTask.id,
                title: topTask.title,
                dueDate: safeDateString(topTask.dueDate),
                priority: topTask.priority,
              }
            : null,
          urgentReply: activeLoops
            .filter((loop) => loop.type === 'needs_reply' || loop.type === 'deadline_risk')
            .sort((a, b) => b.confidencePct - a.confidencePct)[0]
            ? toLoopRow(
                activeLoops
                  .filter((loop) => loop.type === 'needs_reply' || loop.type === 'deadline_risk')
                  .sort((a, b) => b.confidencePct - a.confidencePct)[0]!,
              )
            : null,
        },
        topPriorities,
        needsYou: activeLoops
          .filter((loop) => loop.queue === 'needs_you' || loop.queue === 'likely_dropped')
          .slice(0, 5)
          .map(toLoopRow),
        waitingOn: activeLoops
          .filter((loop) => loop.queue === 'waiting_on')
          .slice(0, 5)
          .map(toLoopRow),
        prepared: pendingActions.slice(0, 5).map(toPreparedActionRow),
        upcomingMeetings: meetings
          .filter((item) => item.startsAt >= now)
          .sort((a, b) => +a.startsAt - +b.startsAt)
          .slice(0, 5)
          .map(summarizeMeetingRow),
        changedSinceLastTime,
      };

      const snapshotKey = `${now.toISOString().slice(0, 10)}:default`;
      const existingSnapshot = await db
        .select()
        .from(assistantBriefingSnapshot)
        .where(
          and(
            eq(assistantBriefingSnapshot.userId, ctx.sessionUser.id),
            eq(assistantBriefingSnapshot.snapshotKey, snapshotKey),
          ),
        )
        .limit(1);
      if (existingSnapshot[0]) {
        await db
          .update(assistantBriefingSnapshot)
          .set({ payload: briefing, updatedAt: now })
          .where(eq(assistantBriefingSnapshot.id, existingSnapshot[0].id));
      } else {
        await db.insert(assistantBriefingSnapshot).values({
          id: crypto.randomUUID(),
          userId: ctx.sessionUser.id,
          snapshotKey,
          payload: briefing,
          createdAt: now,
          updatedAt: now,
        });
      }

      return briefing;
    } finally {
      await conn.end();
    }
  }),

  listOpenLoops: privateProcedure
    .input(
      z.object({
        queue: assistantLoopQueueSchema.optional(),
        status: assistantLoopStatusSchema.optional(),
        limit: z.number().min(1).max(50).default(25),
      }),
    )
    .output(z.object({ loops: z.array(assistantOpenLoopSchema) }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        let rows: (typeof assistantOpenLoop.$inferSelect)[];
        try {
          rows = await db
            .select()
            .from(assistantOpenLoop)
            .where(eq(assistantOpenLoop.userId, ctx.sessionUser.id))
            .orderBy(desc(assistantOpenLoop.updatedAt))
            .limit(input.limit);
        } catch (error) {
          if (!isMissingAssistantSchemaError(error)) throw error;
          console.warn(
            '[assistant.listOpenLoops] Returning no loops because assistant tables are missing',
          );
          return { loops: [] };
        }
        return {
          loops: rows
            .filter((row) => (input.queue ? row.queue === input.queue : true))
            .filter((row) => (input.status ? row.status === input.status : row.status !== 'done'))
            .map(toLoopRow),
        };
      } finally {
        await conn.end();
      }
    }),

  getThreadContext: activeConnectionProcedure
    .input(z.object({ threadId: z.string() }))
    .output(assistantThreadContextSchema)
    .query(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const { result: thread } = await getThread(ctx.activeConnection.id, input.threadId);
        let existingBeforeReview: (typeof assistantOpenLoop.$inferSelect)[];
        try {
          existingBeforeReview = await db
            .select()
            .from(assistantOpenLoop)
            .where(
              and(
                eq(assistantOpenLoop.userId, ctx.sessionUser.id),
                eq(assistantOpenLoop.sourceThreadId, input.threadId),
              ),
            );
        } catch (error) {
          if (isMissingAssistantSchemaError(error)) {
            console.warn(
              '[assistant.getThreadContext] Returning fallback context because assistant tables are missing',
            );
            return buildFallbackThreadContext(input.threadId, thread);
          }
          throw error;
        }
        let analysis: Awaited<ReturnType<typeof buildThreadAnalysis>>;
        try {
          analysis = await buildThreadAnalysis(db, {
            userId: ctx.sessionUser.id,
            activeConnection: ctx.activeConnection,
            threadId: input.threadId,
            thread,
          });
        } catch (error) {
          if (isMissingAssistantSchemaError(error)) {
            console.warn(
              '[assistant.getThreadContext] Returning fallback context because assistant tables are missing',
            );
            return buildFallbackThreadContext(input.threadId, thread);
          }
          throw error;
        }

        const latestReceivedAt =
          safeDateString(analysis.latest?.receivedOn) ?? safeDateString(new Date());
        const changedSinceLastOpen: string[] = [];
        const lastReviewedAt = existingBeforeReview
          .map((item) => item.lastReviewedAt)
          .filter((item): item is Date => Boolean(item))
          .sort((a, b) => +b - +a)[0];
        if (lastReviewedAt && latestReceivedAt && new Date(latestReceivedAt) > lastReviewedAt) {
          changedSinceLastOpen.push('Someone replied since you last opened this thread.');
        }
        if (analysis.relatedTasks.length > 0) {
          changedSinceLastOpen.push(
            `${analysis.relatedTasks.length} related task${analysis.relatedTasks.length > 1 ? 's' : ''} already link to this thread.`,
          );
        }
        if (analysis.relatedMeetings.length > 0) {
          changedSinceLastOpen.push(
            `${analysis.relatedMeetings.length} related meeting${analysis.relatedMeetings.length > 1 ? 's' : ''} found in your schedule.`,
          );
        }

        try {
          await db
            .update(assistantOpenLoop)
            .set({ lastReviewedAt: new Date() })
            .where(
              and(
                eq(assistantOpenLoop.userId, ctx.sessionUser.id),
                eq(assistantOpenLoop.sourceThreadId, input.threadId),
              ),
            );
        } catch (error) {
          if (!isMissingAssistantSchemaError(error)) throw error;
          // Schema missing — skip the bookkeeping update and fall through to return analysis.
        }

        const openLoopCountByPerson = new Map<string, number>();
        analysis.openLoops.forEach((loop) => {
          if (loop.personEmail) {
            openLoopCountByPerson.set(
              loop.personEmail,
              (openLoopCountByPerson.get(loop.personEmail) ?? 0) + 1,
            );
          }
        });

        const isConversational = analysis.threadKind === 'conversational';
        return assistantThreadContextSchema.parse({
          threadId: input.threadId,
          subject: analysis.subject,
          // Suppress summary text on low-signal kinds — the card hides entirely client-side.
          summary: isConversational ? analysis.summary : '',
          // Smart one-liner — pre-computed in buildAiLeadLine. Already empty
          // for non-conversational kinds; pass through verbatim.
          aiLeadLine: analysis.aiLeadLine,
          threadKind: analysis.threadKind,
          // Surface the extracted code / receipt so clients can render a
          // direct "Copy 178 691" or "$29.00 · Apr 27" affordance instead
          // of nothing for verification / receipt threads.
          extractedCode: analysis.extractedCode,
          extractedReceipt: analysis.extractedReceipt,
          recommendation: analysis.recommendation,
          waitingState: analysis.waitingState,
          confidence: analysis.confidence,
          riskLevel: analysis.riskLevel,
          reason: analysis.reason,
          // For non-conversational threads we zero out every actionable signal so
          // no Extract task / Draft reply / Create event / Book follow-up button
          // ever appears on receipts, verification codes, marketing, etc.
          replyNeeded:
            isConversational &&
            analysis.openLoops.some(
              (loop) => loop.type === 'needs_reply' && loop.status === 'open',
            ),
          followUpNeeded:
            isConversational &&
            analysis.openLoops.some(
              (loop) =>
                (loop.type === 'meeting_follow_up' || loop.type === 'waiting_on_other') &&
                loop.status === 'open',
            ),
          meetingRequested:
            isConversational &&
            analysis.openLoops.some(
              (loop) => loop.type === 'meeting_follow_up' && loop.status === 'open',
            ),
          existingDraft:
            isConversational &&
            analysis.openLoops.some(
              (loop) => loop.type === 'draft_ready' && loop.status === 'open',
            ),
          actionItems: isConversational ? analysis.actionItems : [],
          researchQueries: isConversational ? analysis.researchQueries : [],
          suggestedTasks: !isConversational
            ? []
            : analysis.preparedActions
            .filter((action) => action.type === 'create_task')
            .flatMap((action) => {
              const payload = asRecord(action.payload);
              const tasks = Array.isArray(payload.tasks) ? payload.tasks : [];
              return tasks
                .map((entry) =>
                  z
                    .object({
                      title: z.string(),
                      description: z.string().nullable().optional(),
                      priority: z.enum(['none', 'low', 'medium', 'high']).default('medium'),
                      dueDate: z.string().nullable().optional(),
                    })
                    .safeParse(entry),
                )
                .filter(
                  (
                    result,
                  ): result is {
                    success: true;
                    data: {
                      title: string;
                      description?: string | null;
                      priority: 'none' | 'low' | 'medium' | 'high';
                      dueDate?: string | null;
                    };
                  } => result.success,
                )
                .map((result) => ({
                  title: result.data.title,
                  description: result.data.description ?? null,
                  priority: result.data.priority,
                  dueDate: result.data.dueDate ?? null,
                }));
            })
            .slice(0, 5),
          suggestedEvent: !isConversational
            ? null
            : analysis.preparedActions
              .filter((action) => action.type === 'create_event')
              .map((action) =>
                z
                  .object({
                    title: z.string(),
                    startAt: z.string().nullable(),
                    endAt: z.string().nullable(),
                    location: z.string().nullable().optional(),
                    notes: z.string().nullable().optional(),
                  })
                  .safeParse(asRecord(action.payload)),
              )
              .find((result) => result.success)?.data ?? null,
          relatedTasks: analysis.relatedTasks.map((item) => ({
            id: item.id,
            title: item.title,
            status: item.status,
            dueDate: safeDateString(item.dueDate),
          })),
          relatedMeetings: analysis.relatedMeetings.map(summarizeMeetingRow),
          people: analysis.peopleContext.map((person) => ({
            email: person.email,
            displayName: person.displayName ?? person.email,
            company: person.company ?? null,
            relationshipSummary: person.relationshipSummary,
            unresolvedAsks: asStringArray(person.unresolvedAsks),
            promises: asStringArray(person.promises),
            recentThreadIds: asStringArray(person.recentThreadIds),
            recentMeetingIds: asStringArray(person.recentMeetingIds),
            recentTaskIds: asStringArray(person.recentTaskIds),
            openLoopCount: openLoopCountByPerson.get(person.email) ?? 0,
            lastInteractionAt: safeDateString(person.lastInteractionAt),
          })),
          openLoops: analysis.openLoops.map(toLoopRow),
          preparedActions: analysis.preparedActions.map(toPreparedActionRow),
          changedSinceLastOpen: unique(changedSinceLastOpen).slice(0, 4),
        });
      } finally {
        await conn.end();
      }
    }),

  getPersonContext: privateProcedure
    .input(z.object({ email: z.string().email() }))
    .output(assistantPersonContextSchema)
    .query(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const person = await db
          .select()
          .from(assistantPersonMemory)
          .where(
            and(
              eq(assistantPersonMemory.userId, ctx.sessionUser.id),
              eq(assistantPersonMemory.email, input.email),
            ),
          )
          .limit(1);
        if (!person[0]) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Person context not found.' });
        }
        const openLoops = await db
          .select()
          .from(assistantOpenLoop)
          .where(
            and(
              eq(assistantOpenLoop.userId, ctx.sessionUser.id),
              eq(assistantOpenLoop.personEmail, input.email),
            ),
          );
        return {
          email: person[0].email,
          displayName: person[0].displayName ?? person[0].email,
          company: person[0].company ?? null,
          relationshipSummary: person[0].relationshipSummary,
          unresolvedAsks: asStringArray(person[0].unresolvedAsks),
          promises: asStringArray(person[0].promises),
          recentThreadIds: asStringArray(person[0].recentThreadIds),
          recentMeetingIds: asStringArray(person[0].recentMeetingIds),
          recentTaskIds: asStringArray(person[0].recentTaskIds),
          openLoopCount: openLoops.filter((loop) => loop.status === 'open').length,
          lastInteractionAt: safeDateString(person[0].lastInteractionAt),
        };
      } finally {
        await conn.end();
      }
    }),

  getWorkstreamContext: privateProcedure
    .input(z.object({ key: z.string() }))
    .output(assistantWorkstreamContextSchema)
    .query(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const workstream = await db
          .select()
          .from(assistantWorkstreamMemory)
          .where(
            and(
              eq(assistantWorkstreamMemory.userId, ctx.sessionUser.id),
              eq(assistantWorkstreamMemory.key, input.key),
            ),
          )
          .limit(1);
        if (!workstream[0]) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Workstream context not found.' });
        }
        return {
          key: workstream[0].key,
          title: workstream[0].title,
          summary: workstream[0].summary,
          status: workstream[0].status,
          pendingDecisions: asStringArray(workstream[0].pendingDecisions),
          risks: asStringArray(workstream[0].risks),
          relatedPeople: asStringArray(workstream[0].relatedPeople),
          relatedThreadIds: asStringArray(workstream[0].relatedThreadIds),
          relatedMeetingIds: asStringArray(workstream[0].relatedMeetingIds),
          relatedTaskIds: asStringArray(workstream[0].relatedTaskIds),
          nextMilestone: workstream[0].nextMilestone ?? null,
        };
      } finally {
        await conn.end();
      }
    }),

  listPreparedActions: privateProcedure
    .input(
      z.object({
        status: assistantPreparedActionStatusSchema.optional(),
        limit: z.number().min(1).max(50).default(25),
      }),
    )
    .output(z.object({ actions: z.array(assistantPreparedActionSchema) }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const rows = await db
          .select()
          .from(assistantPreparedAction)
          .where(eq(assistantPreparedAction.userId, ctx.sessionUser.id))
          .orderBy(desc(assistantPreparedAction.updatedAt))
          .limit(input.limit);
        return {
          actions: rows
            .filter((row) =>
              input.status ? row.status === input.status : row.status === 'pending',
            )
            .map(toPreparedActionRow),
        };
      } finally {
        await conn.end();
      }
    }),

  generateDraft: activeConnectionProcedure
    .input(
      z.object({ threadId: z.string(), openInComposer: z.boolean().optional().default(false) }),
    )
    .output(
      z.object({
        draftId: z.string().nullable(),
        created: z.boolean(),
        reason: z.string(),
        preview: z.string().optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const result = await generateDraftForThread(
        ctx.activeConnection,
        { id: ctx.sessionUser.id, name: ctx.sessionUser.name },
        input.threadId,
        input.openInComposer,
      );
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        await db
          .update(assistantPreparedAction)
          .set({
            status: result.created ? 'applied' : 'dismissed',
            preview: result.preview ?? null,
            updatedAt: new Date(),
          })
          .where(
            and(
              eq(assistantPreparedAction.userId, ctx.sessionUser.id),
              eq(assistantPreparedAction.uniqueKey, `thread:${input.threadId}:draft_reply`),
            ),
          );
      } finally {
        await conn.end();
      }
      return result;
    }),

  applyPreparedAction: activeConnectionProcedure
    .input(z.object({ actionId: z.string() }))
    .output(
      z.object({
        success: z.boolean(),
        actionType: assistantPreparedActionTypeSchema,
        createdTaskIds: z.array(z.string()).optional(),
        createdEventId: z.string().nullable().optional(),
        draftId: z.string().nullable().optional(),
        researchQueries: z.array(z.string()).optional(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const rows = await db
          .select()
          .from(assistantPreparedAction)
          .where(
            and(
              eq(assistantPreparedAction.userId, ctx.sessionUser.id),
              eq(assistantPreparedAction.id, input.actionId),
            ),
          )
          .limit(1);
        const action = rows[0];
        if (!action) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'Prepared action not found.' });
        }
        if (action.status === 'applied') {
          throw new TRPCError({ code: 'CONFLICT', message: 'Prepared action already applied.' });
        }

        const payload = asRecord(action.payload);

        if (action.type === 'draft_reply' || action.type === 'follow_up') {
          if (!action.sourceThreadId) {
            throw new TRPCError({
              code: 'BAD_REQUEST',
              message: 'This action is missing a source thread.',
            });
          }
          const result = await generateDraftForThread(
            ctx.activeConnection,
            { id: ctx.sessionUser.id, name: ctx.sessionUser.name },
            action.sourceThreadId,
            true,
          );
          await db
            .update(assistantPreparedAction)
            .set({
              status: result.created ? 'applied' : 'dismissed',
              preview: result.preview ?? null,
              updatedAt: new Date(),
            })
            .where(eq(assistantPreparedAction.id, action.id));
          return {
            success: true,
            actionType: action.type,
            draftId: result.draftId ?? null,
          };
        }

        if (action.type === 'create_task') {
          const taskPayloads = Array.isArray(payload.tasks) ? payload.tasks : [];
          const createdTaskIds: string[] = [];
          for (const entry of taskPayloads.slice(0, 5)) {
            const parsed = z
              .object({
                title: z.string(),
                description: z.string().nullable().optional(),
                priority: z.enum(['none', 'low', 'medium', 'high']).default('medium'),
                dueDate: z.string().nullable().optional(),
              })
              .safeParse(entry);
            if (!parsed.success) continue;
            const dueDate =
              parsed.data.dueDate && !Number.isNaN(Date.parse(parsed.data.dueDate))
                ? new Date(parsed.data.dueDate)
                : null;
            const taskId = crypto.randomUUID();
            createdTaskIds.push(taskId);
            await db.insert(task).values({
              id: taskId,
              userId: ctx.sessionUser.id,
              title: parsed.data.title,
              description: parsed.data.description ?? '',
              status: 'todo',
              priority: parsed.data.priority,
              dueDate,
              folderId: null,
              reminderIdentifier: null,
              emailThreadId: action.sourceThreadId ?? null,
              eventId: null,
              createdAt: new Date(),
              updatedAt: new Date(),
            });
          }
          await db
            .update(assistantPreparedAction)
            .set({ status: 'applied', updatedAt: new Date() })
            .where(eq(assistantPreparedAction.id, action.id));
          return {
            success: true,
            actionType: action.type,
            createdTaskIds,
          };
        }

        if (action.type === 'create_event') {
          const parsed = z
            .object({
              title: z.string(),
              startAt: z.string().nullable(),
              endAt: z.string().nullable(),
              location: z.string().nullable().optional(),
              notes: z.string().nullable().optional(),
            })
            .safeParse(payload);
          if (!parsed.success || !parsed.data.startAt || !parsed.data.endAt) {
            throw new TRPCError({ code: 'BAD_REQUEST', message: 'Event payload is incomplete.' });
          }
          if (ctx.activeConnection.providerId !== 'google' || !ctx.activeConnection.refreshToken) {
            throw new TRPCError({
              code: 'BAD_REQUEST',
              message: 'Calendar event creation is only available for connected Google accounts.',
            });
          }
          const created = await createGoogleCalendarEvent(ctx.activeConnection.refreshToken, {
            title: parsed.data.title,
            startAt: parsed.data.startAt,
            endAt: parsed.data.endAt,
            location: parsed.data.location ?? null,
            notes: parsed.data.notes ?? null,
          });
          await db
            .update(assistantPreparedAction)
            .set({ status: 'applied', updatedAt: new Date() })
            .where(eq(assistantPreparedAction.id, action.id));
          return {
            success: true,
            actionType: action.type,
            createdEventId: created.id,
          };
        }

        const researchQueries = Array.isArray(payload.queries)
          ? payload.queries.filter((value): value is string => typeof value === 'string')
          : [];
        await db
          .update(assistantPreparedAction)
          .set({ status: 'applied', updatedAt: new Date() })
          .where(eq(assistantPreparedAction.id, action.id));
        return {
          success: true,
          actionType: action.type,
          researchQueries,
        };
      } finally {
        await conn.end();
      }
    }),

  snoozeOpenLoop: privateProcedure
    .input(z.object({ openLoopId: z.string(), until: z.coerce.date() }))
    .output(z.object({ success: z.boolean() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        await db
          .update(assistantOpenLoop)
          .set({
            status: 'snoozed',
            snoozedUntil: input.until,
            lastReviewedAt: new Date(),
            updatedAt: new Date(),
          })
          .where(
            and(
              eq(assistantOpenLoop.userId, ctx.sessionUser.id),
              eq(assistantOpenLoop.id, input.openLoopId),
            ),
          );
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  dismissOpenLoop: privateProcedure
    .input(z.object({ openLoopId: z.string() }))
    .output(z.object({ success: z.boolean() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        await db
          .update(assistantOpenLoop)
          .set({ status: 'dismissed', lastReviewedAt: new Date(), updatedAt: new Date() })
          .where(
            and(
              eq(assistantOpenLoop.userId, ctx.sessionUser.id),
              eq(assistantOpenLoop.id, input.openLoopId),
            ),
          );
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  /**
   * Mark a prepared action as dismissed without applying it. Used by Home briefing
   * "Not now" / "Not a draft" gestures so the row disappears immediately and the
   * classifier picks up a `wrong` feedback signal alongside the dismissal.
   *
   * Mirrors `dismissOpenLoop` for the prepared-action side. Without this, dismissing
   * a wrong "Draft ready" item left no path to remove it from the briefing.
   */
  dismissPreparedAction: privateProcedure
    .input(z.object({ actionId: z.string() }))
    .output(z.object({ success: z.boolean() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        await db
          .update(assistantPreparedAction)
          .set({ status: 'dismissed', updatedAt: new Date() })
          .where(
            and(
              eq(assistantPreparedAction.userId, ctx.sessionUser.id),
              eq(assistantPreparedAction.id, input.actionId),
            ),
          );
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  recordFeedback: privateProcedure
    .input(assistantFeedbackInputSchema)
    .output(z.object({ success: z.boolean() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        await db.insert(assistantFeedback).values({
          id: crypto.randomUUID(),
          userId: ctx.sessionUser.id,
          targetType: input.targetType,
          targetId: input.targetId,
          feedback: input.feedback,
          note: input.note ?? null,
          createdAt: new Date(),
        });
        if (input.feedback === 'completed' && input.targetType === 'open_loop') {
          await db
            .update(assistantOpenLoop)
            .set({ status: 'done', lastReviewedAt: new Date(), updatedAt: new Date() })
            .where(
              and(
                eq(assistantOpenLoop.userId, ctx.sessionUser.id),
                eq(assistantOpenLoop.id, input.targetId),
              ),
            );
        }
        return { success: true };
      } finally {
        await conn.end();
      }
    }),

  getChangeFeed: privateProcedure
    .input(z.object({ limit: z.number().min(1).max(20).default(10) }).optional())
    .output(z.object({ items: z.array(assistantChangeFeedItemSchema) }))
    .query(async ({ ctx, input }) => {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const items = await buildChangeFeed(db, ctx.sessionUser.id);
        return { items: items.slice(0, input?.limit ?? 10) };
      } finally {
        await conn.end();
      }
    }),
});
