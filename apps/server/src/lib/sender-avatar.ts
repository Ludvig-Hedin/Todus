import { people, type people_v1 } from '@googleapis/people';
import { OAuth2Client } from 'google-auth-library';
import * as cheerio from 'cheerio';
import { env } from '../env';

const GOOGLE_CONTACTS_READONLY_SCOPE = 'https://www.googleapis.com/auth/contacts.readonly';
const GOOGLE_OTHER_CONTACTS_READONLY_SCOPE =
  'https://www.googleapis.com/auth/contacts.other.readonly';
const GOOGLE_CONTACT_READ_MASK = 'names,emailAddresses,photos';
const GOOGLE_OTHER_CONTACT_SEARCH_MASK = 'names,emailAddresses,metadata';
const MAX_FAVICON_URLS = 6;

// Domains of free personal email providers. Brand-favicon lookup is skipped for these —
// the result would be the provider's own logo (Gmail's G, Outlook's O), not the sender's avatar.
const FREE_EMAIL_PROVIDERS = new Set([
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

export const senderAvatarSourceSchemaValues = ['google', 'bimi', 'favicon', 'none'] as const;
export const senderAvatarPrimarySourceSchemaValues = ['google', 'bimi', 'favicon'] as const;
export type SenderAvatarSource = (typeof senderAvatarSourceSchemaValues)[number];

type GoogleConnectionAuth = {
  accessToken?: string | null;
  refreshToken?: string | null;
  scope?: string | null;
};

type AvatarImage = {
  source: (typeof senderAvatarPrimarySourceSchemaValues)[number];
  url: string | null;
  svgContent: string | null;
};

type ResolvedSenderAvatar = {
  email: string;
  domain: string;
  primary: AvatarImage | { source: 'google'; url: string; svgContent: null } | null;
  fallbackUrls: string[];
};

// --- In-memory isolate cache (B-015) -----------------------------------------
// No general-purpose KV binding exists, so we cache avatar resolution in-process.
// This survives only within a single Worker isolate's lifetime (best-effort, not
// cross-isolate), but it eliminates repeat third-party hits (favicon scrape,
// Gravatar, BIMI DNS, Clearbit) for the same sender while an isolate is warm.
//
// Only the *deterministic* resolution path is cached — i.e. requests WITHOUT
// googleAuth. The Google People lookup is per-user (queries the caller's own
// authorized contacts) and must never be shared across users, so those calls
// bypass the cache entirely.
const AVATAR_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // ~24h
const AVATAR_CACHE_MAX_ENTRIES = 2000;
const avatarCache = new Map<string, { value: ResolvedSenderAvatar; expiresAt: number }>();

function avatarCacheKey(normalizedEmail: string, allowExternalImages: boolean) {
  return `${normalizedEmail}|ext=${allowExternalImages ? 1 : 0}`;
}

function readAvatarCache(key: string): ResolvedSenderAvatar | null {
  const entry = avatarCache.get(key);
  if (!entry) {
    return null;
  }
  if (entry.expiresAt <= Date.now()) {
    avatarCache.delete(key);
    return null;
  }
  // Refresh insertion order so frequently-hit entries are evicted last (LRU-ish).
  avatarCache.delete(key);
  avatarCache.set(key, entry);
  return entry.value;
}

function writeAvatarCache(key: string, value: ResolvedSenderAvatar) {
  // Evict the oldest entry (Map preserves insertion order) when over the cap.
  while (avatarCache.size >= AVATAR_CACHE_MAX_ENTRIES) {
    const oldestKey = avatarCache.keys().next().value;
    if (oldestKey === undefined) {
      break;
    }
    avatarCache.delete(oldestKey);
  }
  avatarCache.set(key, { value, expiresAt: Date.now() + AVATAR_CACHE_TTL_MS });
}

export function normalizeEmailAddress(email: string) {
  return email.trim().toLowerCase();
}

export function extractEmailDomain(email: string) {
  const normalizedEmail = normalizeEmailAddress(email);
  const [, domain = ''] = normalizedEmail.split('@');
  return domain.trim();
}

export function buildDomainCandidates(domain: string) {
  const labels = domain
    .toLowerCase()
    .split('.')
    .map((label) => label.trim())
    .filter(Boolean);

  const candidates: string[] = [];

  for (let index = 0; index <= Math.max(labels.length - 2, 0); index += 1) {
    const candidate = labels.slice(index).join('.');
    if (candidate.includes('.')) {
      candidates.push(candidate);
    }
  }

  return Array.from(new Set(candidates));
}

function buildOriginCandidates(domain: string) {
  const origins: string[] = [];

  for (const candidate of buildDomainCandidates(domain)) {
    origins.push(`https://${candidate}`);
    if (!candidate.startsWith('www.')) {
      origins.push(`https://www.${candidate}`);
    }
  }

  return Array.from(new Set(origins));
}

function isHttpsUrl(value: string) {
  try {
    return new URL(value).protocol === 'https:';
  } catch {
    return false;
  }
}

function resolveIconHref(href: string, baseUrl: string) {
  try {
    const resolved = new URL(href, baseUrl).toString();
    return isHttpsUrl(resolved) ? resolved : null;
  } catch {
    return null;
  }
}

function extractIconUrlsFromHtml(html: string, baseUrl: string) {
  const $ = cheerio.load(html);
  const iconUrls: string[] = [];

  $('link[rel][href]').each((_, element) => {
    const relValue = ($(element).attr('rel') ?? '').toLowerCase();
    if (!relValue.includes('icon')) {
      return;
    }

    const href = $(element).attr('href');
    if (!href) {
      return;
    }

    const resolved = resolveIconHref(href, baseUrl);
    if (resolved) {
      iconUrls.push(resolved);
    }
  });

  return iconUrls;
}

function getDefaultFaviconUrls(origin: string) {
  return [
    new URL('/favicon.ico', origin).toString(),
    new URL('/apple-touch-icon.png', origin).toString(),
  ];
}

export async function resolveFaviconUrls(domain: string) {
  const fallbackUrls = new Set<string>();

  for (const origin of buildOriginCandidates(domain)) {
    try {
      const response = await fetch(origin, {
        redirect: 'follow',
        headers: {
          Accept: 'text/html,application/xhtml+xml',
        },
      });

      const finalOrigin = new URL(response.url || origin).origin;
      const contentType = response.headers.get('content-type') ?? '';

      if (response.ok && contentType.includes('html')) {
        const html = await response.text();
        for (const iconUrl of extractIconUrlsFromHtml(html, response.url || origin)) {
          fallbackUrls.add(iconUrl);
        }
      }

      for (const defaultUrl of getDefaultFaviconUrls(finalOrigin)) {
        fallbackUrls.add(defaultUrl);
      }
    } catch {
      for (const defaultUrl of getDefaultFaviconUrls(origin)) {
        fallbackUrls.add(defaultUrl);
      }
    }

    if (fallbackUrls.size >= MAX_FAVICON_URLS) {
      break;
    }
  }

  return Array.from(fallbackUrls).filter(isHttpsUrl).slice(0, MAX_FAVICON_URLS);
}

function parseGrantedScopes(scope: string | null | undefined) {
  return new Set(
    (scope ?? '')
      .split(/\s+/)
      .map((value) => value.trim())
      .filter(Boolean),
  );
}

function getPrimaryPhoto(person: people_v1.Schema$Person | undefined) {
  const photos = person?.photos ?? [];
  return (
    photos.find((photo) => photo.default !== true && photo.url)?.url ??
    photos.find((photo) => photo.url)?.url ??
    null
  );
}

function emailMatchesPerson(person: people_v1.Schema$Person | undefined, email: string) {
  return (person?.emailAddresses ?? []).some(
    (address) => normalizeEmailAddress(address.value ?? '') === email,
  );
}

async function findGoogleContactPhoto(
  auth: GoogleConnectionAuth,
  input: { email: string; name?: string | null },
) {
  const grantedScopes = parseGrantedScopes(auth.scope);
  const hasExplicitScopes = grantedScopes.size > 0;
  const canSearchContacts = !hasExplicitScopes || grantedScopes.has(GOOGLE_CONTACTS_READONLY_SCOPE);
  const canSearchOtherContacts =
    !hasExplicitScopes || grantedScopes.has(GOOGLE_OTHER_CONTACTS_READONLY_SCOPE);

  if (
    (!canSearchContacts && !canSearchOtherContacts) ||
    (!auth.accessToken && !auth.refreshToken)
  ) {
    return null;
  }

  const oauthClient = new OAuth2Client(env.GOOGLE_CLIENT_ID, env.GOOGLE_CLIENT_SECRET);
  oauthClient.setCredentials({
    access_token: auth.accessToken ?? undefined,
    refresh_token: auth.refreshToken ?? undefined,
    scope: auth.scope ?? undefined,
  });

  const peopleApi = people({ version: 'v1', auth: oauthClient });
  const queries = Array.from(
    new Set([input.email, input.name?.trim()].filter((value): value is string => Boolean(value))),
  );
  const normalizedEmail = normalizeEmailAddress(input.email);

  for (const query of queries) {
    if (canSearchContacts) {
      const contactsResponse = await peopleApi.people.searchContacts({
        query,
        pageSize: 10,
        readMask: GOOGLE_CONTACT_READ_MASK,
      });

      const matchingContact = contactsResponse.data.results?.find((result) =>
        emailMatchesPerson(result.person, normalizedEmail),
      );
      const contactPhoto = getPrimaryPhoto(matchingContact?.person);
      if (contactPhoto) {
        return contactPhoto;
      }
    }

    if (canSearchOtherContacts) {
      const otherContactsResponse = await peopleApi.otherContacts.search({
        query,
        pageSize: 10,
        readMask: GOOGLE_OTHER_CONTACT_SEARCH_MASK,
      });

      const matchingOtherContact = otherContactsResponse.data.results?.find((result) =>
        emailMatchesPerson(result.person, normalizedEmail),
      );
      const resourceName = matchingOtherContact?.person?.resourceName;

      if (!resourceName) {
        continue;
      }

      const personResponse = await peopleApi.people.get({
        resourceName,
        personFields: GOOGLE_CONTACT_READ_MASK,
      });
      const contactPhoto = getPrimaryPhoto(personResponse.data);
      if (contactPhoto) {
        return contactPhoto;
      }
    }
  }

  return null;
}

const parseBimiRecord = (record: string) => {
  const parts = record.split(';').map((part) => part.trim());
  const result: { version?: string; logoUrl?: string; authorityUrl?: string } = {};

  for (const part of parts) {
    if (part.startsWith('v=')) {
      result.version = part.substring(2);
    } else if (part.startsWith('l=')) {
      result.logoUrl = part.substring(2);
    } else if (part.startsWith('a=')) {
      result.authorityUrl = part.substring(2);
    }
  }

  return result;
};

async function fetchBimiRecord(domain: string) {
  try {
    const response = await fetch(
      `https://dns.google/resolve?name=default._bimi.${domain}&type=TXT`,
    );

    if (!response.ok) {
      return null;
    }

    const data = (await response.json()) as {
      Status: number;
      Answer?: Array<{ data: string }>;
    };

    if (data.Status !== 0 || !data.Answer?.length) {
      return null;
    }

    const bimiRecord = data.Answer.find((answer) => answer.data.includes('v=BIMI1'));
    return bimiRecord ? parseBimiRecord(bimiRecord.data.replace(/"/g, '')) : null;
  } catch {
    return null;
  }
}

async function fetchBimiSvg(logoUrl: string) {
  try {
    if (!isHttpsUrl(logoUrl)) {
      return null;
    }

    const response = await fetch(logoUrl, {
      headers: {
        Accept: 'image/svg+xml',
      },
    });

    if (!response.ok) {
      return null;
    }

    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('svg')) {
      return null;
    }

    const svgContent = await response.text();
    return svgContent.includes('<svg') && svgContent.includes('</svg>') ? svgContent : null;
  } catch {
    return null;
  }
}

async function findBimiAvatar(domain: string): Promise<AvatarImage | null> {
  const bimiRecord = await fetchBimiRecord(domain);

  if (!bimiRecord?.logoUrl) {
    return null;
  }

  const svgContent = await fetchBimiSvg(bimiRecord.logoUrl);
  if (!svgContent) {
    return null;
  }

  return {
    source: 'bimi',
    url: bimiRecord.logoUrl,
    svgContent,
  };
}

async function computeGravatarUrl(email: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(email.trim().toLowerCase());
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashHex = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  // d=404 makes Gravatar return HTTP 404 when no avatar exists so the client's
  // onError waterfall advances to the next candidate instead of showing a default image.
  return `https://www.gravatar.com/avatar/${hashHex}?s=256&d=404&r=g`;
}

function buildAugmentedFallbackUrls({
  domain,
  isFreeProvider,
  gravatarUrl,
  faviconUrls,
}: {
  domain: string;
  isFreeProvider: boolean;
  gravatarUrl: string;
  faviconUrls: string[];
}): string[] {
  if (isFreeProvider) {
    // Personal email addresses: only Gravatar — no brand logos.
    return [gravatarUrl];
  }

  const urls: string[] = [];

  // Clearbit has excellent brand-logo coverage and returns proper 404 (not a globe).
  // Reverse candidates so the root domain (best hit rate) is tried first.
  const candidates = [...buildDomainCandidates(domain)].reverse();
  for (const candidate of candidates) {
    urls.push(`https://logo.clearbit.com/${candidate}?size=256`);
  }

  // icon.horse and DuckDuckGo: reliable favicon services that return 404 on failure
  for (const candidate of candidates) {
    urls.push(`https://icon.horse/icon/${candidate}`);
  }
  for (const candidate of candidates) {
    urls.push(`https://icons.duckduckgo.com/ip3/${candidate}.ico`);
  }

  // Gravatar: covers individuals who happen to use a brand domain
  urls.push(gravatarUrl);

  // Cheerio-extracted favicon URLs (apple-touch-icon, favicon.ico from domain HTML)
  for (const url of faviconUrls) {
    urls.push(url);
  }

  return Array.from(new Set(urls)).filter(isHttpsUrl);
}

export async function resolveSenderAvatar(input: {
  email: string;
  name?: string | null;
  googleAuth?: GoogleConnectionAuth | null;
  // Privacy gate (B-015). When false, all third-party avatar lookups are skipped —
  // no Gravatar/Clearbit/icon.horse/DuckDuckGo/favicon-scrape/BIMI requests are made,
  // so the raw email/domain never leaks to those services. Defaults to true to preserve
  // existing behavior when the caller can't resolve the user's setting.
  externalImages?: boolean;
}) {
  const normalizedEmail = normalizeEmailAddress(input.email);
  const domain = extractEmailDomain(normalizedEmail);

  if (!domain) {
    return {
      email: normalizedEmail,
      domain: '',
      primary: null,
      fallbackUrls: [],
    };
  }

  const allowExternalImages = input.externalImages ?? true;

  // In-memory isolate cache (B-015): serve a previously-resolved result for this
  // sender when the caller has no googleAuth (the deterministic domain/BIMI/favicon/
  // Gravatar path). Google-authed lookups are per-user and intentionally uncached.
  const cacheKey = avatarCacheKey(normalizedEmail, allowExternalImages);
  const hasGoogleAuth = Boolean(input.googleAuth);
  if (!hasGoogleAuth) {
    const cached = readAvatarCache(cacheKey);
    if (cached) {
      return cached;
    }
  }

  // Cache + return helper for the deterministic (non-Google) resolution paths.
  // Skips caching when a per-user Google lookup was involved.
  const finalize = (result: ResolvedSenderAvatar): ResolvedSenderAvatar => {
    if (!hasGoogleAuth) {
      writeAvatarCache(cacheKey, result);
    }
    return result;
  };

  // Privacy gate: skip the Google-independent third-party leaks entirely. The Google
  // People lookup below is still allowed because it queries the user's own authorized
  // contacts via their OAuth token (not an anonymous third-party image host).
  if (!allowExternalImages) {
    if (input.googleAuth) {
      try {
        const googlePhotoUrl = await findGoogleContactPhoto(input.googleAuth, {
          email: normalizedEmail,
          name: input.name,
        });

        if (googlePhotoUrl) {
          return {
            email: normalizedEmail,
            domain,
            primary: {
              source: 'google' as const,
              url: googlePhotoUrl,
              svgContent: null,
            },
            fallbackUrls: [],
          };
        }
      } catch (error) {
        console.warn(`[sender-avatar] Google People lookup failed for ${normalizedEmail}`, error);
      }
    }

    // No external fallbacks — client renders initials.
    return finalize({
      email: normalizedEmail,
      domain,
      primary: null,
      fallbackUrls: [],
    });
  }

  const isFreeProvider = FREE_EMAIL_PROVIDERS.has(domain);

  // Skip favicon scraping for free email providers — it returns the provider's own icon,
  // not the person's avatar. Gravatar covers personal addresses instead.
  const faviconUrls = isFreeProvider ? [] : await resolveFaviconUrls(domain);
  const gravatarUrl = await computeGravatarUrl(normalizedEmail);
  const augmentedFallbackUrls = buildAugmentedFallbackUrls({
    domain,
    isFreeProvider,
    gravatarUrl,
    faviconUrls,
  });

  if (input.googleAuth) {
    try {
      const googlePhotoUrl = await findGoogleContactPhoto(input.googleAuth, {
        email: normalizedEmail,
        name: input.name,
      });

      if (googlePhotoUrl) {
        return {
          email: normalizedEmail,
          domain,
          primary: {
            source: 'google' as const,
            url: googlePhotoUrl,
            svgContent: null,
          },
          fallbackUrls: augmentedFallbackUrls,
        };
      }
    } catch (error) {
      console.warn(`[sender-avatar] Google People lookup failed for ${normalizedEmail}`, error);
    }
  }

  // BIMI is domain-specific — meaningless for free email providers
  if (!isFreeProvider) {
    const bimiAvatar = await findBimiAvatar(domain);
    if (bimiAvatar) {
      return finalize({
        email: normalizedEmail,
        domain,
        primary: bimiAvatar,
        fallbackUrls: augmentedFallbackUrls,
      });
    }
  }

  const [primaryFallbackUrl] = augmentedFallbackUrls;
  if (primaryFallbackUrl) {
    return finalize({
      email: normalizedEmail,
      domain,
      primary: {
        source: 'favicon' as const,
        url: primaryFallbackUrl,
        svgContent: null,
      },
      fallbackUrls: augmentedFallbackUrls,
    });
  }

  return finalize({
    email: normalizedEmail,
    domain,
    primary: null,
    fallbackUrls: [],
  });
}
