import { View, Text, StyleSheet, type StyleProp, type ViewStyle } from 'react-native';
import { useTRPC } from '../../providers/QueryTrpcProvider';
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

function getFirstLetterCharacter(value?: string) {
  if (!value) return '';
  const match = value.match(/[a-zA-Z]/);
  return match ? match[0].toUpperCase() : '';
}

export function SenderAvatar({ email, name, size = 32, style }: SenderAvatarProps) {
  const trpc = useTRPC();
  const { ui } = useTheme();
  const [imageIndex, setImageIndex] = useState(0);
  const normalizedEmail = email?.trim().toLowerCase() ?? '';
  const hasValidEmail = EMAIL_PATTERN.test(normalizedEmail);

  const { data: avatarData, isLoading } = useQuery({
    ...trpc.avatar.getByEmail.queryOptions({ email: normalizedEmail, name }),
    enabled: hasValidEmail,
    staleTime: 1000 * 60 * 60 * 24,
    gcTime: 1000 * 60 * 60 * 24 * 7,
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
