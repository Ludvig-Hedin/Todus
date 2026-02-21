import type { ExpoConfig } from 'expo/config';

const webUrl = process.env.EXPO_PUBLIC_WEB_URL ?? 'https://0.email';

const config: ExpoConfig = {
  name: 'Zero Mail',
  slug: 'zero-mail-ios',
  version: '1.0.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  userInterfaceStyle: 'light',
  newArchEnabled: true,
  ios: {
    bundleIdentifier: 'com.ludvighedin.zero',
    supportsTablet: true,
  },
  android: {
    adaptiveIcon: {
      foregroundImage: './assets/adaptive-icon.png',
      backgroundColor: '#ffffff',
    },
    edgeToEdgeEnabled: true,
    package: 'com.ludvighedin.zero',
  },
  web: {
    favicon: './assets/favicon.png',
  },
  extra: {
    webUrl,
  },
};

export default config;
