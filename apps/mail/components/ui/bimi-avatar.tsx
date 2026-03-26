import { useTRPC, useTRPCClient } from '@/providers/query-provider';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Avatar, AvatarFallback, AvatarImage } from './avatar';
import { useQuery } from '@tanstack/react-query';
import DOMPurify from 'dompurify';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_FAVICON_URLS = 6;

// Palette of pleasant bg/text pairs for initials avatars — deterministic per seed
const AVATAR_COLOR_PALETTE = [
  { bg: '#DBEAFE', text: '#1D4ED8' }, // blue
  { bg: '#D1FAE5', text: '#065F46' }, // emerald
  { bg: '#EDE9FE', text: '#5B21B6' }, // violet
  { bg: '#FCE7F3', text: '#9D174D' }, // pink
  { bg: '#FEF3C7', text: '#92400E' }, // amber
  { bg: '#FFEDD5', text: '#9A3412' }, // orange
  { bg: '#FEE2E2', text: '#991B1B' }, // red
  { bg: '#F0FDF4', text: '#166534' }, // green
  { bg: '#E0E7FF', text: '#3730A3' }, // indigo
  { bg: '#FDF4FF', text: '#7E22CE' }, // fuchsia
];

const AVATAR_COLOR_PALETTE_DARK = [
  { bg: '#1E3A5F', text: '#93C5FD' },
  { bg: '#064E3B', text: '#6EE7B7' },
  { bg: '#2E1065', text: '#C4B5FD' },
  { bg: '#500724', text: '#F9A8D4' },
  { bg: '#451A03', text: '#FDE68A' },
  { bg: '#431407', text: '#FDBA74' },
  { bg: '#450A0A', text: '#FCA5A5' },
  { bg: '#052E16', text: '#86EFAC' },
  { bg: '#1E1B4B', text: '#A5B4FC' },
  { bg: '#3B0764', text: '#E879F9' },
];

function getAvatarColorIndex(seed: string): number {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = seed.charCodeAt(i) + ((hash << 5) - hash);
  }
  return Math.abs(hash) % AVATAR_COLOR_PALETTE.length;
}

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

  const urls: string[] = [];
  for (const candidate of buildDomainCandidates(domain)) {
    urls.push(`https://${candidate}/favicon.ico`);
    urls.push(`https://${candidate}/apple-touch-icon.png`);
    if (!candidate.startsWith('www.')) {
      urls.push(`https://www.${candidate}/favicon.ico`);
      urls.push(`https://www.${candidate}/apple-touch-icon.png`);
    }
  }

  return Array.from(new Set(urls)).slice(0, MAX_FAVICON_URLS);
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

export const BimiAvatar = ({
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

    return Array.from(new Set(urls));
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

  // Deterministic color based on email so the same sender always gets the same color
  const colorIndex = getAvatarColorIndex(normalizedEmail || name || '');
  const lightColor = AVATAR_COLOR_PALETTE[colorIndex]!;
  const darkColor = AVATAR_COLOR_PALETTE_DARK[colorIndex]!;

  // Two spans layered via Tailwind dark-mode classes — one for light, one for dark
  const InitialsFallback = (
    <>
      <span
        className="dark:hidden flex h-full w-full items-center justify-center rounded-full font-bold text-sm"
        style={{ background: lightColor.bg, color: lightColor.text }}
      >
        {firstLetter}
      </span>
      <span
        className="hidden dark:flex h-full w-full items-center justify-center rounded-full font-bold text-sm"
        style={{ background: darkColor.bg, color: darkColor.text }}
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
        <div
          className="flex h-full w-full items-center justify-center overflow-hidden rounded-full bg-white dark:bg-[#373737]"
          dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(avatarData.primary.svgContent) }}
        />
      ) : bimiData?.logo?.svgContent && !isBimiLoading ? (
        <div
          className="flex h-full w-full items-center justify-center overflow-hidden rounded-full bg-white dark:bg-[#373737]"
          dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(bimiData.logo.svgContent) }}
        />
      ) : activeImageUrl ? (
        <AvatarImage
          className="rounded-full bg-[#FFFFFF] dark:bg-[#373737]"
          src={activeImageUrl}
          alt={name || normalizedEmail}
          onError={handleFallbackImageError}
        />
      ) : (
        <AvatarFallback className="rounded-full p-0">{InitialsFallback}</AvatarFallback>
      )}
    </Avatar>
  );
};
