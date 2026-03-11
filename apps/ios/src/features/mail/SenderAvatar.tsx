import { View, Text, StyleSheet, type StyleProp, type ViewStyle } from 'react-native';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../../shared/theme/ThemeContext';
import { getNativeEnv } from '../../shared/config/env';
import { Image } from 'expo-image';
import { useQuery } from '@tanstack/react-query';
import { SvgXml } from 'react-native-svg';
import { useMemo, useState } from 'react';

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

function getEmailLogo(email: string, imageApiUrl: string) {
  if (!imageApiUrl) return '';
  return `${imageApiUrl}${email}`;
}

export function SenderAvatar({ email, name, size = 32, style }: SenderAvatarProps) {
  const trpc = useTRPC();
  const env = getNativeEnv();
  const { ui } = useTheme();
  const [useDefaultFallback, setUseDefaultFallback] = useState(false);
  const normalizedEmail = email?.trim() ?? '';
  const hasValidEmail = EMAIL_PATTERN.test(normalizedEmail);

  const { data: bimiData, isLoading } = useQuery({
    ...trpc.bimi.getByEmail.queryOptions({ email: normalizedEmail }),
    enabled: hasValidEmail && !useDefaultFallback,
    staleTime: 1000 * 60 * 60 * 24,
    gcTime: 1000 * 60 * 60 * 24 * 7,
  });

  const fallbackImageSrc = useMemo(() => {
    if (!hasValidEmail || useDefaultFallback) return '';
    return getEmailLogo(normalizedEmail, env.imageApiUrl);
  }, [env.imageApiUrl, hasValidEmail, normalizedEmail, useDefaultFallback]);

  const firstLetter = getFirstLetterCharacter(name || normalizedEmail) || '?';
  const containerStyle = {
    width: size,
    height: size,
    borderRadius: size / 2,
    backgroundColor: ui.surfaceInset,
  };

  return (
    <View style={[styles.container, containerStyle, style]}>
      {bimiData?.logo?.svgContent && !isLoading ? (
        <SvgXml xml={bimiData.logo.svgContent} width={size} height={size} />
      ) : fallbackImageSrc ? (
        <Image
          source={{ uri: fallbackImageSrc }}
          style={styles.image}
          contentFit="cover"
          transition={120}
          onError={(e) => {
            console.log('SenderAvatar load error:', e.error);
            setUseDefaultFallback(true);
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
