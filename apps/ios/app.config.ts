import type { ExpoConfig } from 'expo/config';

const webUrl = process.env.EXPO_PUBLIC_WEB_URL ?? 'https://todus.app';
const backendUrl = process.env.EXPO_PUBLIC_BACKEND_URL ?? 'https://api.todus.app';
const posthogKey = process.env.EXPO_PUBLIC_POSTHOG_KEY ?? '';
const posthogHost = process.env.EXPO_PUBLIC_POSTHOG_HOST ?? 'https://us.i.posthog.com';
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
  plugins: [
    'expo-router',
    'expo-secure-store',
    'expo-web-browser',
    '@react-native-community/datetimepicker',
    'expo-apple-authentication',
  ],
  ios: {
    bundleIdentifier: 'com.ludvighedin.todus',
    config: {
      usesNonExemptEncryption: false,
    },
    icon: {
      light: './assets/ios-icon-light.png',
      dark: './assets/ios-icon-dark.png',
      tinted: './assets/ios-icon-tinted.png',
    },
    supportsTablet: true,
    usesAppleSignIn: true,
    infoPlist: {
      NSMicrophoneUsageDescription:
        'Todus uses your microphone to transcribe voice prompts in the assistant.',
    },
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
    router: {
      origin: false,
    },
    eas: {
      projectId: '10b2cbe2-6786-4328-a831-ba6ccbca1e89',
    },
  },
};

export default config;
