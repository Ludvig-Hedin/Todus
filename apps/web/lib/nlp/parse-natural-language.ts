/**
 * Natural language date/time parser for Swedish and English task/event input.
 * Handles patterns like:
 *   "Träffa Johan kl 13 imorgon"  →  title: "Träffa Johan", dueDate: tomorrow at 13:00
 *   "Ring Lisa fredag kl 9"        →  title: "Ring Lisa", dueDate: next Friday at 09:00
 *   "Send report tomorrow at 14"   →  title: "Send report", dueDate: tomorrow at 14:00
 *
 * Also supports compound intents (multiple items separated by "och"/"and"):
 *   "Träffa Johan kl 13 imorgon och maila honom presentationen innan"
 *   →  [event "Träffa Johan" 13:00 tomorrow] + [task "Maila honom presentationen" 12:45 tomorrow]
 */

export type IntentType = 'event' | 'task' | 'email';

export interface ParsedNLInput {
  title: string;
  dueDate: Date | null;
  confidence: number;
  originalText: string;
}

export interface CompoundIntent {
  type: IntentType;
  title: string;
  date: Date | null;
}

const CLAUSE_STARTER_KEYWORDS = [
  'maila',
  'email',
  'reply',
  'skicka',
  'send',
  'ring',
  'call',
  'träffa',
  'möt',
  'meet',
  'book',
  'boka',
  'schedule',
  'create',
  'skapa',
  'add',
  'lägg till',
];

// ---------------------------------------------------------------------------
// Simple single-input parser
// ---------------------------------------------------------------------------

export function parseNaturalLanguage(text: string, now = new Date()): ParsedNLInput {
  const trimmed = text.trim();
  const lower = trimmed.toLowerCase();

  let baseDate: Date = now;
  let confidence = 0.52;
  const consumed: Array<[number, number]> = []; // [start, end] index pairs to remove from title

  // Step 1: relative date keywords
  const relativeMarkers: Array<[string, number]> = [
    ['imorgon', 1],
    ['tomorrow', 1],
    ['idag', 0],
    ['today', 0],
  ];
  for (const [token, offset] of relativeMarkers) {
    const idx = lower.indexOf(token);
    if (idx !== -1) {
      consumed.push([idx, idx + token.length]);
      baseDate = addDays(now, offset);
      confidence = 0.86;
      break; // first match wins
    }
  }

  // Step 2: weekday references (only if no relative marker matched)
  if (baseDate === now) {
    const todayDow = now.getDay(); // 0=Sun … 6=Sat
    const weekdayMarkers: Array<[string, number]> = [
      ['måndag', 1],
      ['mandag', 1],
      ['monday', 1],
      ['tisdag', 2],
      ['tuesday', 2],
      ['onsdag', 3],
      ['wednesday', 3],
      ['torsdag', 4],
      ['thursday', 4],
      ['fredag', 5],
      ['friday', 5],
      ['lördag', 6],
      ['lordag', 6],
      ['saturday', 6],
      ['söndag', 0],
      ['sondag', 0],
      ['sunday', 0],
    ];
    for (const [token, targetDow] of weekdayMarkers) {
      const idx = lower.indexOf(token);
      if (idx !== -1) {
        consumed.push([idx, idx + token.length]);
        let daysAhead = targetDow - todayDow;
        if (daysAhead <= 0) daysAhead += 7;
        baseDate = addDays(now, daysAhead);
        confidence = 0.82;
        break;
      }
    }
  }

  // Step 3: time detection — three patterns in priority order
  let dueDate: Date | null = null;
  const hasDateKeyword = baseDate !== now;
  const timeMatch = findTimeMatch(lower, hasDateKeyword);
  if (timeMatch) {
    const { hours, minutes, start, end } = timeMatch;
    consumed.push([start, end]);
    dueDate = setTime(baseDate, hours, minutes);
    // If no date keyword and the time has already passed today, roll to tomorrow
    if (baseDate === now && dueDate < now) {
      dueDate = addDays(dueDate, 1);
    }
    confidence = Math.max(confidence, 0.9);
  }

  // Step 4: date keyword but no time → start of that day
  if (!dueDate && baseDate !== now) {
    dueDate = startOfDay(baseDate);
    confidence = Math.max(confidence, 0.72);
  }

  // Build cleaned title
  const title = removeConsumedRanges(trimmed, consumed).trim() || trimmed;

  return { title, dueDate, confidence, originalText: trimmed };
}

// ---------------------------------------------------------------------------
// Compound intent parser
// ---------------------------------------------------------------------------

export function parseCompoundInput(text: string, now = new Date()): CompoundIntent[] {
  const trimmed = text.trim();
  const segments = splitAtConjunctions(trimmed)
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && !isPureCommandPhrase(s));

  if (segments.length <= 1) {
    const parsed = parseNaturalLanguage(trimmed, now);
    return [{ type: classifyIntent(trimmed), title: parsed.title, date: parsed.dueDate }];
  }

  // First pass: parse each segment
  const intermediate = segments.map((seg) => {
    const parsed = parseNaturalLanguage(seg, now);
    return { type: classifyIntent(seg), title: parsed.title, date: parsed.dueDate, original: seg };
  });

  // Second pass: resolve relative references against the first segment with a date
  const anchorDate = intermediate.find((s) => s.date !== null)?.date ?? null;

  return intermediate.map((result) => {
    let resolvedDate = result.date;

    if (!resolvedDate && anchorDate) {
      const lower = result.original.toLowerCase();
      if (containsBeforeRef(lower)) {
        resolvedDate = addMinutes(anchorDate, -15);
      } else if (containsAfterRef(lower)) {
        resolvedDate = addMinutes(anchorDate, 15);
      } else if (containsSoonRef(lower)) {
        resolvedDate = addMinutes(anchorDate, -60);
      }
    }

    const cleanTitle = stripRelativeRefWords(result.title);
    return {
      type: result.type,
      title: cleanTitle || result.title,
      date: resolvedDate,
    };
  });
}

// ---------------------------------------------------------------------------
// Intent classification
// ---------------------------------------------------------------------------

function classifyIntent(text: string): IntentType {
  const lower = text.toLowerCase();
  const emailKeywords = ['maila', 'mail', 'email', 'skicka mail', 'send email', 'reply'];
  if (emailKeywords.some((kw) => matchesWord(lower, kw))) return 'email';

  const eventKeywords = [
    'träffa',
    'träff',
    'möt',
    'möte',
    'lunch',
    'middag',
    'frukost',
    'dejt',
    'fika',
    'mingel',
    'samtal',
    'konferens',
    'intervju',
    'meet',
    'meeting',
    'dinner',
    'breakfast',
    'coffee',
    'conference',
    'interview',
  ];
  if (eventKeywords.some((kw) => matchesWord(lower, kw))) return 'event';

  return 'task';
}

// ---------------------------------------------------------------------------
// Time matching
// ---------------------------------------------------------------------------

interface TimeMatch {
  hours: number;
  minutes: number;
  start: number; // index into the lowered string
  end: number;
}

function findTimeMatch(lower: string, hasDateKeyword: boolean): TimeMatch | null {
  // Priority 1: explicit prefix "kl", "at", "@" anywhere
  const prefixedRe = /(?:kl\s*|at\s+|@\s*)([01]?\d|2[0-3])(?::([0-5]\d))?(?!\d)/g;
  const p1 = prefixedRe.exec(lower);
  if (p1) {
    return {
      hours: parseInt(p1[1], 10),
      minutes: p1[2] ? parseInt(p1[2], 10) : 0,
      start: p1.index,
      end: p1.index + p1[0].length,
    };
  }

  // Priority 2: HH:MM colon format (less ambiguous)
  const colonRe = /(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)/g;
  const p2 = colonRe.exec(lower);
  if (p2) {
    return {
      hours: parseInt(p2[1], 10),
      minutes: parseInt(p2[2], 10),
      start: p2.index,
      end: p2.index + p2[0].length,
    };
  }

  // Priority 3: bare number at end of string
  if (hasDateKeyword) {
    const tailRe = /(?<![:\d])([01]?\d|2[0-3])(?::([0-5]\d))?\s*$/;
    const p3 = tailRe.exec(lower);
    if (p3) {
      return {
        hours: parseInt(p3[1], 10),
        minutes: p3[2] ? parseInt(p3[2], 10) : 0,
        start: p3.index,
        end: p3.index + p3[0].length,
      };
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Conjunction splitting
// ---------------------------------------------------------------------------

function splitAtConjunctions(text: string): string[] {
  const regex = /\s+(?:och|and)\s+/gi;
  const segments: string[] = [];
  let lastIndex = 0;

  for (const match of text.matchAll(regex)) {
    const matchStart = match.index ?? 0;
    const matchText = match[0] ?? '';
    const rightSide = text.slice(matchStart + matchText.length);

    if (isLikelyClauseStarter(rightSide)) {
      segments.push(text.slice(lastIndex, matchStart));
      lastIndex = matchStart + matchText.length;
    }
  }

  segments.push(text.slice(lastIndex));
  return segments;
}

// ---------------------------------------------------------------------------
// Command phrase filtering
// ---------------------------------------------------------------------------

function isPureCommandPhrase(text: string): boolean {
  const lower = text
    .toLowerCase()
    .replace(/[.!?,]+$/, '')
    .trim();
  const commands = [
    'skapa',
    'skapa dem',
    'skapa den',
    'skapa det',
    'skapa alla',
    'lägg till',
    'lägg till dem',
    'gör det',
    'gör dem',
    'och skapa',
    'spara',
    'spara det',
    'create',
    'create them',
    'create it',
    'add it',
    'save it',
    'do it',
  ];
  return commands.includes(lower);
}

// ---------------------------------------------------------------------------
// Relative time references
// ---------------------------------------------------------------------------

function containsBeforeRef(lower: string): boolean {
  return ['innan', 'before', 'dessförinnan', 'i förväg', 'i forvag', 'i förhand', 'i forhand'].some(
    (t) => lower.includes(t),
  );
}

function containsAfterRef(lower: string): boolean {
  if (['efteråt', 'efterat', 'efter det', 'after', 'afterwards'].some((t) => lower.includes(t))) {
    return true;
  }

  return /\b(?:sen|sedan)\b/i.test(lower);
}

function containsSoonRef(lower: string): boolean {
  return ['snart', 'soon'].some((t) => lower.includes(t));
}

function stripRelativeRefWords(title: string): string {
  const words = [
    'innan',
    'before',
    'efteråt',
    'efterat',
    'efter det',
    'after',
    'afterwards',
    'dessförinnan',
    'snart',
    'soon',
    'i förväg',
    'i forvag',
    'i förhand',
    'i forhand',
    'sedan',
  ];
  let result = title;
  for (const word of words) {
    result = result.replace(new RegExp(word, 'gi'), '');
  }
  result = result.replace(/\bsen\b/gi, '');
  return result
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/[.!?,]+$/, '');
}

function matchesWord(text: string, word: string): boolean {
  const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`\\b${escaped}\\b`, 'i').test(text);
}

function isLikelyClauseStarter(text: string): boolean {
  const lower = text.toLowerCase().trim();
  if (!lower) return false;
  if (CLAUSE_STARTER_KEYWORDS.some((kw) => matchesWord(lower, kw))) return true;

  const prefixed = lower.match(/^(?:sedan|then)\s+(.+)$/i)?.[1]?.trim() ?? '';
  return prefixed ? CLAUSE_STARTER_KEYWORDS.some((kw) => matchesWord(prefixed, kw)) : false;
}

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

function addDays(date: Date, days: number): Date {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000);
}

function setTime(base: Date, hours: number, minutes: number): Date {
  const d = new Date(base);
  d.setHours(hours, minutes, 0, 0);
  return d;
}

function startOfDay(date: Date): Date {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

/** Remove character ranges from a string (ranges in ascending order). */
function removeConsumedRanges(text: string, ranges: Array<[number, number]>): string {
  if (ranges.length === 0) return text;
  // Sort descending so we remove from end first and don't shift earlier indices
  const sorted = [...ranges].sort((a, b) => b[0] - a[0]);
  let result = text;
  for (const [start, end] of sorted) {
    result = result.slice(0, start) + result.slice(end);
  }
  return result.replace(/\s+/g, ' ').trim();
}
