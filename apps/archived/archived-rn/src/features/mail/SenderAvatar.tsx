import { View, Text, StyleSheet, type StyleProp, type ViewStyle } from 'react-native';
import { useTRPC, useTRPCClient } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../../shared/theme/ThemeContext';
import { useEffect, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { SvgXml } from 'react-native-svg';
import { Image } from 'expo-image';

type SenderAvatarProps = {
  email?: string;
  name?: string;
  size?: number;
  style?: StyleProp<ViewStyle>;
};

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_FAVICON_URLS = 6;

function getFirstLetterCharacter(value?: string) {
  if (!value) return '';
  const match = value.match(/[a-zA-Z]/);
  return match ? match[0].toUpperCase() : '';
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

export function SenderAvatar({ email, name, size = 32, style }: SenderAvatarProps) {
  const trpc = useTRPC();
  const trpcClient = useTRPCClient();
  const { ui } = useTheme();
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
    staleTime: 1000 * 60 * 60 * 24,
    gcTime: 1000 * 60 * 60 * 24 * 7,
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
  }, [normalizedEmail, avatarData?.primary?.url]);

  const imageUrls = useMemo(() => {
    const urls = [
      avatarData?.primary?.url,
      ...(avatarData?.fallbackUrls ?? []),
      ...buildFaviconFallbackUrls(normalizedEmail),
    ].filter((value): value is string => Boolean(value));

    return Array.from(new Set(urls));
  }, [avatarData?.fallbackUrls, avatarData?.primary?.url, normalizedEmail]);

  const activeImageUrl = imageUrls[imageIndex] ?? '';

  const firstLetter = getFirstLetterCharacter(name || normalizedEmail) || '?';
  const containerStyle = {
    width: size,
    height: size,
    borderRadius: size / 2,
    backgroundColor: ui.surfaceInset,
  };

  return (
    <View style={[styles.container, containerStyle, style]}>
      {avatarData?.primary?.svgContent && !isLoading ? (
        <SvgXml xml={avatarData.primary.svgContent} width={size} height={size} />
      ) : bimiData?.logo?.svgContent && !isBimiLoading ? (
        <SvgXml xml={bimiData.logo.svgContent} width={size} height={size} />
      ) : activeImageUrl ? (
        <Image
          source={{ uri: activeImageUrl }}
          style={styles.image}
          contentFit="cover"
          transition={120}
          onError={() => {
            setImageIndex((currentIndex) => currentIndex + 1);
          }}
        />
      ) : (
        <View style={[styles.fallback, { backgroundColor: ui.avatar }]}>
          <Text style={[styles.fallbackText, { color: ui.avatarText }]}>{firstLetter}</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  fallback: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
  },
  fallbackText: {
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
});
