import type { ExpoConfig } from 'expo/config';

const webUrl =
  process.env.EXPO_PUBLIC_WEB_URL ?? 'https://todus-production.ludvighedin15.workers.dev';
const backendUrl =
  process.env.EXPO_PUBLIC_BACKEND_URL ??
  'https://todus-server-v1-production.ludvighedin15.workers.dev';
const appName = process.env.EXPO_PUBLIC_APP_NAME ?? 'Todus';

const config: ExpoConfig = {
  name: appName,
  slug: 'todus-ios',
  version: '1.0.0',
  scheme: 'todus',
  orientation: 'portrait',
  icon: './assets/icon.png',
  userInterfaceStyle: 'automatic',
  newArchEnabled: true,
  plugins: ['expo-router', 'expo-secure-store'],
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
  experiments: {
    typedRoutes: true,
  },
  extra: {
    appName,
    webUrl,
    backendUrl,
    router: {
      origin: false,
    },
  },
};

export default config;
