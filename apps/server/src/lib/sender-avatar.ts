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

export async function resolveSenderAvatar(input: {
  email: string;
  name?: string | null;
  googleAuth?: GoogleConnectionAuth | null;
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

  const faviconUrls = await resolveFaviconUrls(domain);

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
          fallbackUrls: faviconUrls,
        };
      }
    } catch (error) {
      console.warn(`[sender-avatar] Google People lookup failed for ${normalizedEmail}`, error);
    }
  }

  const bimiAvatar = await findBimiAvatar(domain);
  if (bimiAvatar) {
    return {
      email: normalizedEmail,
      domain,
      primary: bimiAvatar,
      fallbackUrls: faviconUrls,
    };
  }

  const [primaryFaviconUrl] = faviconUrls;
  if (primaryFaviconUrl) {
    return {
      email: normalizedEmail,
      domain,
      primary: {
        source: 'favicon' as const,
        url: primaryFaviconUrl,
        svgContent: null,
      },
      fallbackUrls: faviconUrls,
    };
  }

  return {
    email: normalizedEmail,
    domain,
    primary: null,
    fallbackUrls: [],
  };
}
