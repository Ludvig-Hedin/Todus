import type { ExpoConfig } from 'expo/config';

const webUrl =
  process.env.EXPO_PUBLIC_WEB_URL ?? 'https://zero-production.ludvighedin15.workers.dev';
const backendUrl =
  process.env.EXPO_PUBLIC_BACKEND_URL ??
  'https://zero-server-v1-production.ludvighedin15.workers.dev';
const appEntryUrl = process.env.EXPO_PUBLIC_APP_ENTRY_URL ?? `${webUrl}/mail/inbox`;

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
    backendUrl,
    appEntryUrl,
  },
};

export default config;
