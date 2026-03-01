import type { ExpoConfig } from 'expo/config';

const webUrl = process.env.EXPO_PUBLIC_WEB_URL ?? 'https://todus.app';
const backendUrl = process.env.EXPO_PUBLIC_BACKEND_URL ?? 'https://api.todus.app';
const posthogKey = process.env.EXPO_PUBLIC_POSTHOG_KEY ?? '';
const posthogHost = process.env.EXPO_PUBLIC_POSTHOG_HOST ?? 'https://us.i.posthog.com';
const sentryDsn = process.env.EXPO_PUBLIC_SENTRY_DSN ?? '';
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
  plugins: ['expo-router', 'expo-secure-store', '@sentry/react-native/expo'],
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
    posthogKey,
    posthogHost,
    sentryDsn,
    router: {
      origin: false,
    },
    eas: {
      projectId: '10b2cbe2-6786-4328-a831-ba6ccbca1e89',
    },
  },
};

export default config;
