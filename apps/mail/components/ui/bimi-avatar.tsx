import { useCallback, useEffect, useMemo, useState } from 'react';
import { Avatar, AvatarFallback, AvatarImage } from './avatar';
import { useTRPC } from '@/providers/query-provider';
import { useQuery } from '@tanstack/react-query';
import DOMPurify from 'dompurify';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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
  fallbackClassName = 'rounded-full bg-[#FFFFFF] font-bold text-[#9F9F9F] dark:bg-[#373737]',
  onImageError,
}: BimiAvatarProps) => {
  const trpc = useTRPC();
  const [imageIndex, setImageIndex] = useState(0);
  const normalizedEmail = email?.trim().toLowerCase() ?? '';
  const hasValidEmail = EMAIL_PATTERN.test(normalizedEmail);

  const { data: avatarData, isLoading } = useQuery({
    ...trpc.avatar.getByEmail.queryOptions({ email: normalizedEmail, name }),
    enabled: hasValidEmail,
    staleTime: 1000 * 60 * 60 * 24, // Cache for 24 hours
    gcTime: 1000 * 60 * 60 * 24 * 7, // Keep in cache for 7 days
  });

  useEffect(() => {
    setImageIndex(0);
  }, [normalizedEmail]);

  const imageUrls = useMemo(() => {
    const urls = [avatarData?.primary?.url, ...(avatarData?.fallbackUrls ?? [])].filter(
      (value): value is string => Boolean(value),
    );

    return Array.from(new Set(urls));
  }, [avatarData?.fallbackUrls, avatarData?.primary?.url]);

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

  if (!hasValidEmail) {
    return (
      <Avatar className={className}>
        <AvatarFallback className={fallbackClassName}>{firstLetter}</AvatarFallback>
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
      ) : activeImageUrl ? (
        <AvatarImage
          className="rounded-full bg-[#FFFFFF] dark:bg-[#373737]"
          src={activeImageUrl}
          alt={name || normalizedEmail}
          onError={handleFallbackImageError}
        />
      ) : (
        <AvatarFallback className={fallbackClassName}>{firstLetter}</AvatarFallback>
      )}
    </Avatar>
  );
};
