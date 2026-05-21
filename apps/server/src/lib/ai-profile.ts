import { getZeroDB } from './server-utils';

type AIProfileSource = {
  contextAboutYou?: string | null;
  customPrompt?: string | null;
  language?: string | null;
  timezone?: string | null;
  location?: string | null;
};

type UserIdentity = {
  name?: string | null;
  email?: string | null;
};

const normalizeBlock = (value: string | null | undefined) => value?.trim() ?? '';

const ISO_LANG_NAMES: Record<string, string> = {
  en: 'English',
  es: 'Spanish',
  fr: 'French',
  de: 'German',
  it: 'Italian',
  pt: 'Portuguese',
  nl: 'Dutch',
  sv: 'Swedish',
  no: 'Norwegian',
  da: 'Danish',
  fi: 'Finnish',
  pl: 'Polish',
  ru: 'Russian',
  uk: 'Ukrainian',
  tr: 'Turkish',
  ar: 'Arabic',
  he: 'Hebrew',
  hi: 'Hindi',
  zh: 'Chinese',
  ja: 'Japanese',
  ko: 'Korean',
  vi: 'Vietnamese',
  th: 'Thai',
  id: 'Indonesian',
  cs: 'Czech',
  el: 'Greek',
  hu: 'Hungarian',
  ro: 'Romanian',
};

function languageDisplayName(code: string | null | undefined): string | null {
  if (!code) return null;
  const trimmed = code.trim().toLowerCase();
  if (!trimmed) return null;
  // Try the full tag (e.g. "pt-br") then the base language ("pt").
  const base = trimmed.split(/[-_]/)[0]!;
  return ISO_LANG_NAMES[trimmed] ?? ISO_LANG_NAMES[base] ?? code;
}

/**
 * Builds the full AI profile prompt. Includes:
 *   - User identity (name, email) so the AI can address the user correctly
 *     and produce correct From: lines in drafts
 *   - Locale (timezone, configured language, current local date/time)
 *   - User-supplied context + custom instructions
 *   - A language-match rule so the AI replies in whatever language the user wrote in
 *
 * Privacy: the user's own name + email are sent to the LLM that is already serving
 * the user's own session. The user has consented (account creation + privacy policy);
 * no third party sees this. We deliberately do not include other users' identities here.
 */
export const buildAIProfilePrompt = (
  source?: AIProfileSource,
  identity?: UserIdentity,
) => {
  const sections: string[] = [];

  // ─── User identity ──────────────────────────────────────────────
  const name = normalizeBlock(identity?.name);
  const email = normalizeBlock(identity?.email);
  if (name || email) {
    const lines: string[] = ['## About the user'];
    if (name) lines.push(`- Name: ${name}`);
    if (email) lines.push(`- Email: ${email}`);
    sections.push(lines.join('\n'));
  }

  // ─── Locale ─────────────────────────────────────────────────────
  const timezone = normalizeBlock(source?.timezone) || 'UTC';
  const language = normalizeBlock(source?.language) || 'en';
  const languageName = languageDisplayName(language) ?? 'English';
  const location = normalizeBlock(source?.location);

  // Compute the user's current local date and time once per request so the AI can
  // resolve relative references like "tomorrow" or "this evening" without having to
  // ask. Falls back to the UTC ISO timestamp if the configured timezone is invalid.
  const now = new Date();
  let localNow = now.toISOString();
  try {
    localNow = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      dateStyle: 'full',
      timeStyle: 'short',
    }).format(now);
  } catch {
    // Invalid timezone — keep the UTC fallback.
  }

  const localeLines = [
    '## Locale',
    `- Timezone: ${timezone}`,
    ...(location ? [`- Location: ${location}`] : []),
    `- Preferred language: ${languageName} (${language})`,
    `- Current local date/time: ${localNow}`,
  ];
  sections.push(localeLines.join('\n'));

  // ─── Language-match instruction ────────────────────────────────
  // Tell the AI to mirror the user's message language for reply text. Stable
  // identifiers (action names, IDs) stay in English so the client dispatcher
  // continues to recognize them.
  sections.push(
    [
      '## Reply language',
      `Reply in the language the user wrote in. If the latest user message is in a`,
      `different language than the preferred language above, mirror the message`,
      `language — do not translate it back. Match the user's tone (formal vs. casual).`,
      `Card text shown to the user (titles, summaries, button labels, suggestion chips,`,
      `confirmation messages) must use the same language as the reply; only stable`,
      `identifiers like \`action\` names, IDs, and ISO timestamps stay in English.`,
    ].join(' '),
  );

  // ─── User-supplied context ─────────────────────────────────────
  const contextAboutYou = normalizeBlock(source?.contextAboutYou);
  if (contextAboutYou) {
    sections.push(`## Context about the user (user-provided)\n${contextAboutYou}`);
  }

  // ─── User-supplied custom instructions ─────────────────────────
  const customPrompt = normalizeBlock(source?.customPrompt);
  if (customPrompt) {
    sections.push(`## Custom instructions (user-provided)\n${customPrompt}`);
  }

  return sections.join('\n\n');
};

export async function getSharedAIProfilePromptForUser(
  userId: string,
  identity?: UserIdentity,
) {
  try {
    const zeroDB = await getZeroDB(userId);
    const settings = await zeroDB.findUserSettings();
    return buildAIProfilePrompt(settings?.settings, identity);
  } catch (error) {
    console.warn('[AIProfile] Failed to load shared AI profile prompt:', error);
    // Even on settings-load failure, still return identity + locale defaults so the
    // chat keeps user context (rather than returning the empty string the previous
    // implementation did, which dropped name/email entirely on transient DB errors).
    return buildAIProfilePrompt(undefined, identity);
  }
}
