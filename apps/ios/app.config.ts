import type { ExpoConfig } from 'expo/config';

const webUrl =
  process.env.EXPO_PUBLIC_WEB_URL ?? 'https://zero-production.ludvighedin15.workers.dev';
const backendUrl =
  process.env.EXPO_PUBLIC_BACKEND_URL ??
  'https://zero-server-v1-production.ludvighedin15.workers.dev';
const appEntryUrl = process.env.EXPO_PUBLIC_APP_ENTRY_URL ?? `${webUrl}/mail/inbox`;
const appName = process.env.EXPO_PUBLIC_APP_NAME ?? 'Todus';

const config: ExpoConfig = {
  name: appName,
  slug: 'todus-ios',
  version: '1.0.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  userInterfaceStyle: 'automatic',
  newArchEnabled: true,
  ios: {
    bundleIdentifier: 'com.ludvighedin.todus',
    supportsTablet: true,
  },
  android: {
    adaptiveIcon: {
      foregroundImage: './assets/adaptive-icon.png',
      backgroundColor: '#ffffff',
    },
    edgeToEdgeEnabled: true,
    package: 'com.ludvighedin.todus',
  },
  web: {
    favicon: './assets/favicon.png',
  },
  extra: {
    appName,
    webUrl,
    backendUrl,
    appEntryUrl,
  },
};

export default config;
