// Sender icon registry — mirrors apps/ios/Todus/Todus/Features/Email/SenderIconRegistry.swift
// and apps/macos/TodusMac/Views/Email/MacSenderIconRegistry.swift.
//
// When a sender's email domain matches a known brand, we render a bundled SVG
// (from `simple-icons`) on a brand-colored circle — instant, offline-safe,
// crisp at any size. When there's no match we fall back to initials.
//
// `slug` is the simple-icons identifier. When present, look it up with
// `import * as SimpleIcons from 'simple-icons'` and read the brand path/title.
// `letter`/`bg`/`fg` are used when no slug is set (so the rendering site can
// show a colored letter without depending on simple-icons for that domain).
//
// IMPORTANT: keep this in lock-step with the iOS/macOS registries so the
// three platforms render the same icon for the same sender.

export interface SenderIconSpec {
  letter: string;
  bg: string;
  fg: string;
  /** simple-icons slug (e.g. "github", "stripe"). */
  slug?: string;
}

// Free personal email providers always fall through to initials — we don't want
// to show a Gmail/iCloud brand logo for everyone using those mail services.
const PERSONAL_PROVIDERS = new Set<string>([
  'gmail.com', 'googlemail.com',
  'outlook.com', 'hotmail.com', 'live.com', 'msn.com',
  'yahoo.com', 'yahoo.co.uk', 'yahoo.fr', 'yahoo.de', 'yahoo.co.jp', 'yahoo.com.br',
  'icloud.com', 'me.com', 'mac.com',
  'protonmail.com', 'proton.me', 'protonmail.ch',
  'zohomail.com', 'zoho.com',
  'yandex.com', 'yandex.ru',
  'mail.ru', 'bk.ru', 'inbox.ru', 'list.ru',
  'gmx.com', 'gmx.net', 'gmx.de', 'gmx.at',
  'aol.com', 'aol.co.uk',
  'fastmail.com', 'fastmail.fm',
  'hey.com',
  'tutanota.com', 'tutamail.com',
]);

const MULTI_PART_TLDS = new Set([
  'co.uk', 'org.uk', 'gov.uk', 'ac.uk',
  'com.au', 'co.jp', 'com.br', 'co.in',
]);

function rootDomain(email: string): string | null {
  const lower = email.trim().toLowerCase();
  const at = lower.lastIndexOf('@');
  if (at < 0 || at >= lower.length - 1) return null;
  const domain = lower.slice(at + 1).replace(/^\.+|\.+$/g, '');
  const parts = domain.split('.').filter(Boolean);
  if (parts.length < 2) return null;
  if (parts.length >= 3) {
    const tld2 = parts.slice(-2).join('.');
    if (MULTI_PART_TLDS.has(tld2)) return parts.slice(-3).join('.');
  }
  return parts.slice(-2).join('.');
}

// Registry — mirrors the Swift files exactly. Order is purely for readability.
const ICONS: Record<string, SenderIconSpec> = {
  // Google
  'google.com':    { letter: 'G', bg: '#4285F4', fg: '#FFFFFF', slug: 'google' },
  'google.co.uk':  { letter: 'G', bg: '#4285F4', fg: '#FFFFFF', slug: 'google' },
  'google.de':     { letter: 'G', bg: '#4285F4', fg: '#FFFFFF', slug: 'google' },
  'google.fr':     { letter: 'G', bg: '#4285F4', fg: '#FFFFFF', slug: 'google' },
  'google.ca':     { letter: 'G', bg: '#4285F4', fg: '#FFFFFF', slug: 'google' },
  'google.com.au': { letter: 'G', bg: '#4285F4', fg: '#FFFFFF', slug: 'google' },
  'google.co.jp':  { letter: 'G', bg: '#4285F4', fg: '#FFFFFF', slug: 'google' },

  // GitHub
  'github.com': { letter: 'GH', bg: '#24292E', fg: '#FFFFFF', slug: 'github' },
  'github.io':  { letter: 'GH', bg: '#24292E', fg: '#FFFFFF', slug: 'github' },

  // Apple
  'apple.com': { letter: 'A', bg: '#54545A', fg: '#FFFFFF', slug: 'apple' },

  // Microsoft
  'microsoft.com': { letter: 'M',  bg: '#00A4EF', fg: '#FFFFFF', slug: 'microsoft' },
  'office.com':    { letter: 'O',  bg: '#D83B01', fg: '#FFFFFF' },
  'azure.com':     { letter: 'Az', bg: '#0078D4', fg: '#FFFFFF' },

  // Amazon
  'amazon.com':    { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazon.co.uk':  { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazon.de':     { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazon.fr':     { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazon.es':     { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazon.it':     { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazon.se':     { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazon.nl':     { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazonaws.com': { letter: 'AWS', bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },
  'amazonses.com': { letter: 'A',   bg: '#FF9900', fg: '#232F3E', slug: 'amazon' },

  // AI
  'anthropic.com': { letter: 'A',  bg: '#CF7A4A', fg: '#FFFFFF', slug: 'anthropic' },
  'openai.com':    { letter: 'AI', bg: '#0D0D0D', fg: '#FFFFFF', slug: 'openai' },
  'mistral.ai':    { letter: 'M',  bg: '#FF8F00', fg: '#FFFFFF', slug: 'mistralai' },
  'perplexity.ai': { letter: 'P',  bg: '#19B0AA', fg: '#FFFFFF', slug: 'perplexity' },

  // Productivity / SaaS
  'notion.so':    { letter: 'N',  bg: '#0D0D0D', fg: '#FFFFFF', slug: 'notion' },
  'slack.com':    { letter: '#',  bg: '#4A154B', fg: '#FFFFFF', slug: 'slack' },
  'figma.com':    { letter: 'F',  bg: '#F24E1E', fg: '#FFFFFF', slug: 'figma' },
  'linear.app':   { letter: 'L',  bg: '#5E6AD2', fg: '#FFFFFF', slug: 'linear' },
  'airtable.com': { letter: 'A',  bg: '#FCB400', fg: '#000000', slug: 'airtable' },
  'monday.com':   { letter: 'M',  bg: '#F62B54', fg: '#FFFFFF' },
  'asana.com':    { letter: 'A',  bg: '#F96B68', fg: '#FFFFFF', slug: 'asana' },
  'typeform.com': { letter: 'T',  bg: '#262628', fg: '#FFFFFF', slug: 'typeform' },
  'canva.com':    { letter: 'C',  bg: '#00C4CC', fg: '#FFFFFF', slug: 'canva' },
  'webflow.com':  { letter: 'WF', bg: '#4353FF', fg: '#FFFFFF', slug: 'webflow' },

  // Project management
  'atlassian.com': { letter: 'A', bg: '#0052CC', fg: '#FFFFFF', slug: 'atlassian' },
  'jira.com':      { letter: 'J', bg: '#0052CC', fg: '#FFFFFF', slug: 'atlassian' },

  // Social
  'linkedin.com':  { letter: 'in', bg: '#0A66C2', fg: '#FFFFFF', slug: 'linkedin' },
  'twitter.com':   { letter: '𝕏',  bg: '#0D0D0D', fg: '#FFFFFF', slug: 'x' },
  'x.com':         { letter: '𝕏',  bg: '#0D0D0D', fg: '#FFFFFF', slug: 'x' },
  'facebook.com':     { letter: 'f', bg: '#1877F2', fg: '#FFFFFF', slug: 'facebook' },
  // Transactional / notification mail routes for Meta apps. Map so
  // `messages@priority.facebookmail.com` shows the Facebook logo instead of
  // a gray "JV" initial.
  'facebookmail.com': { letter: 'f', bg: '#1877F2', fg: '#FFFFFF', slug: 'facebook' },
  'facebookmail.net': { letter: 'f', bg: '#1877F2', fg: '#FFFFFF', slug: 'facebook' },
  'fb.com':           { letter: 'f', bg: '#1877F2', fg: '#FFFFFF', slug: 'facebook' },
  'fbcdn.net':        { letter: 'f', bg: '#1877F2', fg: '#FFFFFF', slug: 'facebook' },
  'instagram.com': { letter: 'IG', bg: '#E1306C', fg: '#FFFFFF', slug: 'instagram' },
  'meta.com':      { letter: 'M',  bg: '#0668E1', fg: '#FFFFFF', slug: 'meta' },
  'discord.com':   { letter: 'D',  bg: '#5865F2', fg: '#FFFFFF', slug: 'discord' },
  'telegram.org':  { letter: 'T',  bg: '#2AABEE', fg: '#FFFFFF', slug: 'telegram' },
  'whatsapp.com':  { letter: 'W',  bg: '#25D366', fg: '#FFFFFF', slug: 'whatsapp' },
  'reddit.com':    { letter: 'R',  bg: '#FF4410', fg: '#FFFFFF', slug: 'reddit' },
  'tiktok.com':    { letter: 'T',  bg: '#0D0D0D', fg: '#FFFFFF', slug: 'tiktok' },

  // Newsletter
  'substack.com':    { letter: 'S',  bg: '#FF6719', fg: '#FFFFFF', slug: 'substack' },
  'beehiiv.com':     { letter: 'B',  bg: '#FF6154', fg: '#FFFFFF' },
  'convertkit.com':  { letter: 'CK', bg: '#EE4719', fg: '#FFFFFF', slug: 'kit' },
  'kit.com':         { letter: 'K',  bg: '#EE4719', fg: '#FFFFFF', slug: 'kit' },
  'mailerlite.com':  { letter: 'ML', bg: '#05A893', fg: '#FFFFFF' },

  // Entertainment
  'netflix.com':    { letter: 'N',  bg: '#E50914', fg: '#FFFFFF', slug: 'netflix' },
  'spotify.com':    { letter: 'S',  bg: '#1DB954', fg: '#FFFFFF', slug: 'spotify' },
  'youtube.com':    { letter: '▶',  bg: '#FF0000', fg: '#FFFFFF', slug: 'youtube' },
  'twitch.tv':      { letter: 'T',  bg: '#9244FE', fg: '#FFFFFF', slug: 'twitch' },
  'hbo.com':        { letter: 'H',  bg: '#6922BE', fg: '#FFFFFF', slug: 'hbo' },
  'disneyplus.com': { letter: 'D+', bg: '#111C66', fg: '#FFFFFF' },

  // Commerce / Payments
  'stripe.com':            { letter: 'S',  bg: '#635BFF', fg: '#FFFFFF', slug: 'stripe' },
  'paypal.com':            { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.co.uk':          { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.de':             { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.fr':             { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.it':             { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.es':             { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.se':             { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.nl':             { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'paypal.com.au':         { letter: 'P',  bg: '#003087', fg: '#FFFFFF', slug: 'paypal' },
  'shopify.com':           { letter: 'S',  bg: '#96BF47', fg: '#FFFFFF', slug: 'shopify' },
  'squarespace.com':       { letter: 'S',  bg: '#222222', fg: '#FFFFFF', slug: 'squarespace' },
  'wix.com':               { letter: 'W',  bg: '#0066FF', fg: '#FFFFFF', slug: 'wix' },
  'klarna.com':            { letter: 'K',  bg: '#FFB4C9', fg: '#17120F', slug: 'klarna' },
  'braintreepayments.com': { letter: 'BT', bg: '#3C95CE', fg: '#FFFFFF' },

  // Developer / Infrastructure
  'vercel.com':       { letter: '▲',  bg: '#0D0D0D', fg: '#FFFFFF', slug: 'vercel' },
  'cloudflare.com':   { letter: 'CF', bg: '#F6821F', fg: '#FFFFFF', slug: 'cloudflare' },
  'resend.com':       { letter: 'R',  bg: '#0D0D0D', fg: '#FFFFFF', slug: 'resend' },
  'netlify.com':      { letter: 'N',  bg: '#00C7B7', fg: '#FFFFFF', slug: 'netlify' },
  'heroku.com':       { letter: 'H',  bg: '#6E3DA6', fg: '#FFFFFF', slug: 'heroku' },
  'digitalocean.com': { letter: 'DO', bg: '#0073FF', fg: '#FFFFFF', slug: 'digitalocean' },
  'supabase.com':     { letter: 'S',  bg: '#3CCF8E', fg: '#FFFFFF', slug: 'supabase' },
  'railway.app':      { letter: 'R',  bg: '#7F44DE', fg: '#FFFFFF', slug: 'railway' },
  'render.com':       { letter: 'R',  bg: '#434243', fg: '#FFFFFF', slug: 'render' },
  'sendgrid.net':     { letter: 'SG', bg: '#1A82E2', fg: '#FFFFFF', slug: 'sendgrid' },
  'mailgun.com':      { letter: 'MG', bg: '#F06B66', fg: '#FFFFFF', slug: 'mailgun' },
  'twilio.com':       { letter: 'T',  bg: '#F22F46', fg: '#FFFFFF', slug: 'twilio' },
  'postmark.com':     { letter: 'P',  bg: '#FF720D', fg: '#FFFFFF' },
  'sentry.io':        { letter: 'S',  bg: '#5C4193', fg: '#FFFFFF', slug: 'sentry' },

  // CRM / Marketing / Support
  'hubspot.com':    { letter: 'H',  bg: '#FF7A59', fg: '#FFFFFF', slug: 'hubspot' },
  'salesforce.com': { letter: 'SF', bg: '#00A1E0', fg: '#FFFFFF', slug: 'salesforce' },
  'zendesk.com':    { letter: 'Z',  bg: '#03363D', fg: '#FFFFFF', slug: 'zendesk' },
  'intercom.com':   { letter: 'I',  bg: '#286EFA', fg: '#FFFFFF', slug: 'intercom' },
  'mailchimp.com':  { letter: 'MC', bg: '#040404', fg: '#FFFFFF', slug: 'mailchimp' },

  // Cloud Storage
  'dropbox.com': { letter: 'D', bg: '#0061FF', fg: '#FFFFFF', slug: 'dropbox' },
  'box.com':     { letter: 'B', bg: '#0075FF', fg: '#FFFFFF', slug: 'box' },

  // Design / Creative
  'adobe.com': { letter: 'Ae', bg: '#EF0606', fg: '#FFFFFF', slug: 'adobe' },
};

/**
 * Returns a sender icon spec for the given email address, or null if the
 * domain is unknown / a personal email provider.
 */
export function getSenderIconSpec(email: string | null | undefined): SenderIconSpec | null {
  if (!email) return null;
  const domain = rootDomain(email);
  if (!domain || PERSONAL_PROVIDERS.has(domain)) return null;
  return ICONS[domain] ?? null;
}
