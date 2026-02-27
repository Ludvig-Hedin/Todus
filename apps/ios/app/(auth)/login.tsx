import { useRouter } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Linking,
  Pressable,
  StyleSheet,
  Text,
  View,
  SafeAreaView,
  useColorScheme,
  Image,
} from 'react-native';
import { getNativeEnv } from '../../src/shared/config/env';
import { loadNativeAuthProviders } from '../../src/features/auth/native-auth';
import { GoogleColored, Microsoft, LogoVector } from '../../src/shared/components/icons';

type ProviderState = {
  id: string;
  name: string;
  enabled: boolean;
  isCustom?: boolean;
  customRedirectPath?: string;
};

export default function LoginScreen() {
  const env = getNativeEnv();
  const router = useRouter();
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const [providers, setProviders] = useState<ProviderState[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const loadProviders = async () => {
      setIsLoading(true);
      setErrorMessage(null);

      try {
        const result = await loadNativeAuthProviders(env.backendUrl);
        if (!cancelled) {
          setProviders(result);
        }
      } catch {
        if (!cancelled) {
          setErrorMessage('Could not load login providers. Please try again later.');
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    };

    loadProviders();
    return () => {
      cancelled = true;
    };
  }, [env.backendUrl]);

  const enabledProviders = useMemo(
    () => providers.filter((provider) => provider.enabled || provider.isCustom),
    [providers],
  );

  /** Opens the WebView with the provider ID to trigger direct OAuth.
   * The WebView handles the API call internally (correct Origin header). */
  const startProviderSignIn = (provider: ProviderState) => {
    setErrorMessage(null);

    if (provider.isCustom && provider.customRedirectPath) {
      const url = `${env.webUrl.replace(/\/$/, '')}${provider.customRedirectPath}`;
      Linking.openURL(url).catch(() => { });
      return;
    }

    router.push({
      pathname: '/(auth)/web-auth',
      params: {
        provider: provider.id,
        callbackUrl: env.authCallbackUrl,
      },
    });
  };

  const sortedProviders = [...enabledProviders].sort((a, b) => {
    if (a.id === 'google') return -1;
    if (b.id === 'google') return 1;
    return 0;
  });

  const getProviderIcon = (providerId: string, color: string) => {
    switch (providerId) {
      case 'google':
        return <GoogleColored width={20} height={20} style={styles.icon} />;
      case 'microsoft':
        return <Microsoft width={20} height={20} color={color} style={styles.icon} />;
      case 'zero':
        return <LogoVector width={18} height={18} color={color} style={styles.icon} />;
      default:
        return null;
    }
  };

  const themeStyles = isDark ? darkStyles : lightStyles;

  return (
    <SafeAreaView style={[styles.container, themeStyles.container]}>
      <View style={styles.content}>
        <View style={styles.headerContainer}>
          <View style={styles.logoContainer}>
            {/* Using the brand-logo.png identified from web app assets */}
            <Image
              source={require('../../assets/brand-logo.png')}
              style={styles.logo}
              resizeMode="contain"
            />
          </View>
          <Text style={[styles.title, themeStyles.title]}>Welcome to Todus</Text>
          <Text style={[styles.subtitle, themeStyles.subtitle]}>Your AI agent for emails</Text>
        </View>

        {errorMessage && (
          <View style={styles.errorBox}>
            <Text style={styles.errorTitle}>Error</Text>
            <Text style={styles.errorText}>{errorMessage}</Text>
          </View>
        )}

        <View style={styles.providersContainer}>
          {isLoading ? (
            <ActivityIndicator size="large" color={isDark ? '#ffffff' : '#000000'} style={styles.loader} />
          ) : (
            sortedProviders.map((provider) => (
              <Pressable
                key={provider.id}
                onPress={() => startProviderSignIn(provider)}
                style={({ pressed }) => [
                  styles.providerButton,
                  themeStyles.providerButton,
                  pressed && themeStyles.providerButtonPressed,
                ]}
              >
                {getProviderIcon(provider.id, isDark ? '#ffffff' : '#111827')}
                <Text style={[styles.providerButtonText, themeStyles.providerButtonText]}>
                  Sign in with {provider.name}
                </Text>
              </Pressable>
            ))
          )}

          {!isLoading && sortedProviders.length === 0 && (
            <Pressable
              onPress={() => {
                router.push({
                  pathname: '/(auth)/web-auth',
                  params: { url: `${env.webUrl.replace(/\/$/, '')}/login` },
                });
              }}
              style={[styles.providerButton, themeStyles.providerButton]}
            >
              <Text style={[styles.providerButtonText, themeStyles.providerButtonText]}>Open web login</Text>
            </Pressable>
          )}
        </View>
      </View>

      <View style={styles.footer}>
        <Text style={[styles.footerLinkText, themeStyles.footerLinkText]}>Terms of Service</Text>
        <View style={[styles.dot, themeStyles.dot]} />
        <Text style={[styles.footerLinkText, themeStyles.footerLinkText]}>Privacy Policy</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'space-between',
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
    maxWidth: 600,
    width: '100%',
    alignSelf: 'center',
    marginTop: -40, // Visual balance
  },
  headerContainer: {
    marginBottom: 48,
    alignItems: 'center',
    width: '100%',
  },
  logoContainer: {
    width: 64,
    height: 64,
    borderRadius: 16,
    backgroundColor: '#000000',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 5,
  },
  logo: {
    width: 40,
    height: 40,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 8,
    letterSpacing: -0.5,
  },
  subtitle: {
    fontSize: 17,
    fontWeight: '400',
    textAlign: 'center',
    opacity: 0.6,
  },
  errorBox: {
    width: '100%',
    backgroundColor: 'rgba(239, 68, 68, 0.1)',
    borderColor: 'rgba(239, 68, 68, 0.2)',
    borderWidth: 1,
    borderRadius: 12,
    padding: 16,
    marginBottom: 24,
  },
  errorTitle: {
    color: '#ef4444',
    fontWeight: '600',
    fontSize: 14,
    marginBottom: 4,
  },
  errorText: {
    color: '#ef4444',
    fontSize: 14,
    opacity: 0.8,
  },
  providersContainer: {
    width: '100%',
    gap: 12,
  },
  loader: {
    marginVertical: 20,
  },
  providerButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    height: 52,
    borderRadius: 999,
    borderWidth: 1,
  },
  providerButtonText: {
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: -0.2,
  },
  icon: {
    marginRight: 12,
  },
  footer: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 24,
    paddingHorizontal: 24,
    width: '100%',
  },
  footerLinkText: {
    fontSize: 13,
    fontWeight: '400',
  },
  dot: {
    width: 3,
    height: 3,
    borderRadius: 1.5,
    marginHorizontal: 12,
  },
});

const lightStyles = StyleSheet.create({
  container: {
    backgroundColor: '#FFFFFF',
  },
  title: {
    color: '#000000',
  },
  subtitle: {
    color: '#000000',
  },
  providerButton: {
    backgroundColor: '#FFFFFF',
    borderColor: '#E5E5E5',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 2,
  },
  providerButtonPressed: {
    backgroundColor: '#F8F8F8',
  },
  providerButtonText: {
    color: '#000000',
  },
  footerLinkText: {
    color: '#666666',
  },
  dot: {
    backgroundColor: '#DDDDDD',
  },
});

const darkStyles = StyleSheet.create({
  container: {
    backgroundColor: '#0A0A0A',
  },
  title: {
    color: '#FFFFFF',
  },
  subtitle: {
    color: '#FFFFFF',
  },
  providerButton: {
    backgroundColor: '#1A1A1A',
    borderColor: '#2A2A2A',
  },
  providerButtonPressed: {
    backgroundColor: '#252525',
  },
  providerButtonText: {
    color: '#FFFFFF',
  },
  footerLinkText: {
    color: '#888888',
  },
  dot: {
    backgroundColor: '#333333',
  },
});
