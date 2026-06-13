import { useTRPC, useTRPCClient } from '@/providers/query-provider';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Avatar, AvatarFallback, AvatarImage } from './avatar';
import { useQuery } from '@tanstack/react-query';
import DOMPurify from 'dompurify';
import * as SimpleIcons from 'simple-icons';
import { getSenderIconSpec, type SenderIconSpec } from '@/lib/sender-icon-registry';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_FAVICON_URLS = 8;

// Domains of free personal email providers. Brand-favicon lookup is skipped for these —
// the result would be the provider's own logo (Gmail's G etc.), not the sender's avatar.
// The backend's Gravatar URL in fallbackUrls covers personal addresses instead.
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

// Neutral muted fill for initials avatars — matches Notion Mail's restrained
// style across light + dark mode. No per-sender brand rotation: saves saturation
// budget for real brand icons.
const INITIALS_LIGHT = { bg: '#B5B5B7', text: '#FFFFFF' };
const INITIALS_DARK  = { bg: '#5A5A5A', text: '#FFFFFF' };

function extractDomain(email: string) {
  const [, domain = ''] = email.split('@');
  return domain.trim().toLowerCase();
}

function buildDomainCandidates(domain: string) {
  const labels = domain
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

function buildFaviconFallbackUrls(email: string) {
  const domain = extractDomain(email);
  if (!domain) {
    return [];
  }

  // For personal email providers, skip brand-favicon lookup entirely.
  // The backend already provides a Gravatar URL in fallbackUrls for these addresses.
  if (FREE_EMAIL_PROVIDERS.has(domain)) {
    return [];
  }

  const urls: string[] = [];
  for (const candidate of buildDomainCandidates(domain)) {
    // Clearbit: high-quality brand logos, returns proper 404 (not a globe image).
    // Best coverage for well-known brands (Anthropic, Ryanair, Apple, OpenAI, Cursor…).
    urls.push(`https://logo.clearbit.com/${candidate}?size=256`);
    // icon.horse: reliable favicon API, returns 404 on failure
    urls.push(`https://icon.horse/icon/${candidate}`);
    // DuckDuckGo: reliable favicon service, returns 404 on failure
    urls.push(`https://icons.duckduckgo.com/ip3/${candidate}.ico`);
    // Apple touch icons + favicon.ico — broad compatibility fallbacks.
    // Google s2 is intentionally excluded: it returns a generic globe PNG for
    // unknown domains rather than a proper 404, so onError never fires and
    // the waterfall stops on a meaningless globe icon.
    urls.push(`https://${candidate}/apple-touch-icon.png`);
    urls.push(`https://${candidate}/favicon.ico`);
    if (!candidate.startsWith('www.')) {
      urls.push(`https://logo.clearbit.com/www.${candidate}?size=256`);
      urls.push(`https://icon.horse/icon/www.${candidate}`);
      urls.push(`https://icons.duckduckgo.com/ip3/www.${candidate}.ico`);
      urls.push(`https://www.${candidate}/apple-touch-icon.png`);
      urls.push(`https://www.${candidate}/favicon.ico`);
    }
  }

  return Array.from(new Set(urls));
}

export const getFirstLetterCharacter = (name?: string) => {
  if (!name) return '';
  const match = name.match(/[a-zA-Z]/);
  return match ? match[0].toUpperCase() : '';
};

interface BimiAvatarProps {
  email?: string;
  name?: string;
  className?: string;
  fallbackClassName?: string;
  onImageError?: (e: React.SyntheticEvent<HTMLImageElement>) => void;
}

// Look up the simple-icons brand record for a slug (e.g. "github" → siGithub).
// Returns null if the slug isn't in simple-icons.
function lookupSimpleIcon(slug: string | undefined) {
  if (!slug) return null;
  const key = `si${slug.charAt(0).toUpperCase()}${slug.slice(1)}`;
  // Cast through `unknown` because simple-icons types each export individually.
  const record = (SimpleIcons as unknown as Record<string, { path?: string; title?: string }>)[key];
  return record?.path ? record : null;
}

// Branded sender avatar — only used when a simple-icons SVG glyph is available.
// Renders the brand-colored circle + glyph. If no glyph, this component is
// skipped (BimiAvatar falls through to the neutral initials path) so we never
// render a loud brand-colored letter.
function BrandedSenderAvatar({ spec, className }: { spec: SenderIconSpec; className?: string }) {
  const icon = lookupSimpleIcon(spec.slug);
  if (!icon) return null;
  return (
    <span
      className={`${className ?? ''} flex items-center justify-center rounded-full overflow-hidden`}
      style={{ background: spec.bg, color: spec.fg }}
      aria-hidden
    >
      <svg
        viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg"
        className="h-1/2 w-1/2"
        fill={spec.fg}
        aria-hidden
      >
        <title>{icon.title ?? ''}</title>
        <path d={icon.path} />
      </svg>
    </span>
  );
}

// Thin wrapper that runs the cheap, hookless registry check first and only
// mounts the network-driven avatar when no known brand matches. Done this way
// to keep React hook order stable: we cannot conditionally call useQuery from
// inside a single component.
export const BimiAvatar = (props: BimiAvatarProps) => {
  const normalized = props.email?.trim().toLowerCase() ?? '';
  const brandSpec = getSenderIconSpec(normalized);
  // Only short-circuit when we have an actual SVG glyph to render. Registry
  // entries without a `slug` (e.g. niche brands) deliberately fall through to
  // the network/initials path so we don't paint loud brand-colored letters.
  if (brandSpec?.slug && lookupSimpleIcon(brandSpec.slug)) {
    return <BrandedSenderAvatar spec={brandSpec} className={props.className} />;
  }
  return <NetworkBimiAvatar {...props} />;
};

const NetworkBimiAvatar = ({
  email,
  name,
  className = 'h-8 w-8 rounded-full border dark:border-none',
  onImageError,
}: BimiAvatarProps) => {
  const trpc = useTRPC();
  const trpcClient = useTRPCClient();
  const [imageIndex, setImageIndex] = useState(0);
  const normalizedEmail = email?.trim().toLowerCase() ?? '';
  const hasValidEmail = EMAIL_PATTERN.test(normalizedEmail);
  const avatarInput = useMemo(() => ({ email: normalizedEmail, name }), [name, normalizedEmail]);

  const { data: avatarData, isLoading } = useQuery({
    queryKey: trpc.avatar.getByEmail.queryKey(avatarInput),
    enabled: hasValidEmail,
    retry: false,
    meta: { noGlobalError: true },
    queryFn: async () => {
      try {
        return await trpcClient.avatar.getByEmail.query(avatarInput);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.includes('No procedure found on path "avatar.getByEmail"')) {
          return null;
        }
        throw error;
      }
    },
    staleTime: 1000 * 60 * 60 * 24, // Cache for 24 hours
    gcTime: 1000 * 60 * 60 * 24 * 7, // Keep in cache for 7 days
  });

  const { data: bimiData, isLoading: isBimiLoading } = useQuery({
    ...trpc.bimi.getByEmail.queryOptions({ email: normalizedEmail }),
    enabled: hasValidEmail && !avatarData?.primary?.svgContent,
    retry: false,
    staleTime: 1000 * 60 * 60 * 24,
    gcTime: 1000 * 60 * 60 * 24 * 7,
  });

  useEffect(() => {
    setImageIndex(0);
  }, [normalizedEmail, avatarData?.primary?.url, bimiData?.logo?.url]);

  const imageUrls = useMemo(() => {
    const urls = [
      avatarData?.primary?.url,
      ...(avatarData?.fallbackUrls ?? []),
      ...buildFaviconFallbackUrls(normalizedEmail),
    ].filter((value): value is string => Boolean(value));

    return Array.from(new Set(urls)).slice(0, MAX_FAVICON_URLS);
  }, [avatarData?.fallbackUrls, avatarData?.primary?.url, normalizedEmail]);

  const activeImageUrl = imageUrls[imageIndex] ?? '';

  const handleFallbackImageError = useCallback(
    (e: React.SyntheticEvent<HTMLImageElement>) => {
      setImageIndex((currentIndex) => currentIndex + 1);
      if (onImageError) {
        onImageError(e);
      }
    },
    [onImageError],
  );

  const firstLetter = getFirstLetterCharacter(name || normalizedEmail);

  // Neutral muted fill in light + dark mode. Two spans layered via Tailwind
  // `dark:` classes so the colors flip without JS.
  const InitialsFallback = (
    <>
      <span
        className="dark:hidden flex h-full w-full items-center justify-center rounded-full font-semibold text-sm"
        style={{ background: INITIALS_LIGHT.bg, color: INITIALS_LIGHT.text }}
      >
        {firstLetter}
      </span>
      <span
        className="hidden dark:flex h-full w-full items-center justify-center rounded-full font-semibold text-sm"
        style={{ background: INITIALS_DARK.bg, color: INITIALS_DARK.text }}
      >
        {firstLetter}
      </span>
    </>
  );

  if (!hasValidEmail) {
    return (
      <Avatar className={className}>
        <AvatarFallback className="rounded-full p-0">{InitialsFallback}</AvatarFallback>
      </Avatar>
    );
  }

  return (
    <Avatar className={className}>
      {avatarData?.primary?.svgContent && !isLoading ? (
        // BIMI/profile SVG — highest priority, renders directly
        <div
          className="flex h-full w-full items-center justify-center overflow-hidden rounded-full bg-white dark:bg-[#373737]"
          dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(avatarData.primary.svgContent) }}
        />
      ) : bimiData?.logo?.svgContent && !isBimiLoading ? (
        <div
          className="flex h-full w-full items-center justify-center overflow-hidden rounded-full bg-white dark:bg-[#373737]"
          dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(bimiData.logo.svgContent) }}
        />
      ) : (
        // Image (favicon chain) + always-present fallback as Radix siblings.
        // Radix needs AvatarFallback as a sibling to AvatarImage so it can
        // show the initials while the image is loading or after it fails.
        // Without the sibling, Radix renders nothing during loading → blank avatar.
        <>
          {activeImageUrl && (
            <AvatarImage
              className="rounded-full bg-[#FFFFFF] dark:bg-[#373737]"
              src={activeImageUrl}
              alt={name || normalizedEmail}
              onError={handleFallbackImageError}
            />
          )}
          <AvatarFallback className="rounded-full p-0">{InitialsFallback}</AvatarFallback>
        </>
      )}
    </Avatar>
  );
};
