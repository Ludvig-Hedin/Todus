import { useNavigation } from '@react-navigation/native';
import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Linking, Pressable, StyleSheet, Text, View, SafeAreaView } from 'react-native';
import { getNativeEnv } from '../../shared/config/env';
import { beginNativeProviderSignIn, loadNativeAuthProviders } from './native-auth';
import { Google, Microsoft, LogoVector } from '../../shared/components/icons';
import { useTheme } from '../../shared/theme/ThemeContext';

type ProviderState = {
  id: string;
  name: string;
  enabled: boolean;
  isCustom?: boolean;
  customRedirectPath?: string;
};

export function LoginScreen() {
  const env = getNativeEnv();
  const navigation = useNavigation<any>();
  const theme = useTheme();

  const [providers, setProviders] = useState<ProviderState[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [activeProvider, setActiveProvider] = useState<string | null>(null);
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

  const startProviderSignIn = async (provider: ProviderState) => {
    setErrorMessage(null);
    setActiveProvider(provider.id);

    try {
      if (provider.isCustom && provider.customRedirectPath) {
        const url = `${env.webUrl.replace(/\/$/, '')}${provider.customRedirectPath}`;
        await Linking.openURL(url);
        return;
      }

      const authUrl = await beginNativeProviderSignIn(
        env.backendUrl,
        provider.id,
        env.authCallbackUrl,
      );

      navigation.navigate('WebAuthScreen', {
        url: authUrl,
      });
    } catch {
      setErrorMessage(`Failed to start ${provider.name} sign-in.`);
    } finally {
      setActiveProvider(null);
    }
  };

  const sortedProviders = [...enabledProviders].sort((a, b) => {
    if (a.id === 'zero') return -1;
    if (b.id === 'zero') return 1;
    return 0;
  });

  const getProviderIcon = (providerId: string, color: string) => {
    switch (providerId) {
      case 'google':
        return <Google width={20} height={20} color={color} style={styles.icon} />;
      case 'microsoft':
        return <Microsoft width={20} height={20} color={color} style={styles.icon} />;
      case 'zero':
        return <LogoVector width={18} height={18} color={color} style={styles.icon} />;
      default:
        return null;
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      {/* Main Centered Content */}
      <View style={styles.content}>
        <View style={styles.headerContainer}>
          <Text style={styles.title}>Login to {env.appName}</Text>
        </View>

        {errorMessage && (
          <View style={styles.errorBox}>
            <Text style={styles.errorTitle}>Error</Text>
            <Text style={styles.errorText}>{errorMessage}</Text>
          </View>
        )}

        <View style={styles.providersContainer}>
          {isLoading ? (
            <ActivityIndicator size="large" color="#ffffff" style={styles.loader} />
          ) : (
            sortedProviders.map((provider) => (
              <Pressable
                key={provider.id}
                onPress={() => startProviderSignIn(provider)}
                disabled={Boolean(activeProvider)}
                style={({ pressed }) => [
                  styles.providerButton,
                  pressed && styles.providerButtonPressed,
                  activeProvider === provider.id && styles.providerButtonDisabled,
                ]}
              >
                {getProviderIcon(provider.id, '#111827')}
                <Text style={styles.providerButtonText}>
                  {activeProvider === provider.id ? `Starting...` : `Continue with ${provider.name}`}
                </Text>
              </Pressable>
            ))
          )}

          {/* Fallback to full web login if needed or if no providers */}
          {!isLoading && sortedProviders.length === 0 && (
            <Pressable
              onPress={() => {
                navigation.navigate('WebAuthScreen', {
                  url: `${env.webUrl.replace(/\/$/, '')}/login`,
                });
              }}
              style={styles.providerButton}
            >
              <Text style={styles.providerButtonText}>Open web login</Text>
            </Pressable>
          )}
        </View>
      </View>

      {/* Footer Links */}
      <View style={styles.footer}>
        <Pressable
          style={styles.footerLink}
          onPress={() => {
            navigation.navigate('PublicWebScreen', {
              url: `${env.webUrl.replace(/\/$/, '')}/terms`,
              title: 'Terms of Service',
            });
          }}
        >
          <Text style={styles.footerLinkText}>Terms of Service</Text>
        </Pressable>
        <Pressable
          style={styles.footerLink}
          onPress={() => {
            navigation.navigate('PublicWebScreen', {
              url: `${env.webUrl.replace(/\/$/, '')}/privacy`,
              title: 'Privacy Policy',
            });
          }}
        >
          <Text style={styles.footerLinkText}>Privacy Policy</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#111111', // Match web bg-[#111111]
    justifyContent: 'space-between',
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 24,
    maxWidth: 600,
    width: '100%',
    alignSelf: 'center',
  },
  headerContainer: {
    marginBottom: 32,
    alignItems: 'center',
    width: '100%',
  },
  title: {
    fontSize: 36,
    fontWeight: '700',
    color: '#ffffff',
    textAlign: 'center',
  },
  errorBox: {
    width: '100%',
    backgroundColor: 'rgba(249, 115, 22, 0.1)', // bg-orange-500/10
    borderColor: 'rgba(249, 115, 22, 0.4)', // border-orange-500/40
    borderWidth: 1,
    borderRadius: 8,
    padding: 16,
    marginBottom: 24,
  },
  errorTitle: {
    color: '#fb923c', // text-orange-400
    fontWeight: '600',
    fontSize: 16,
    marginBottom: 4,
  },
  errorText: {
    color: '#ffffff',
    fontSize: 14,
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
    backgroundColor: '#ffffff',
    height: 48,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: '#e5e7eb', // border-input approx
  },
  providerButtonPressed: {
    backgroundColor: '#f3f4f6', // hover:bg-accent
  },
  providerButtonDisabled: {
    opacity: 0.7,
  },
  providerButtonText: {
    color: '#111827', // text-primary (dark)
    fontSize: 16,
    fontWeight: '500',
  },
  icon: {
    marginRight: 10,
  },
  footer: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 16,
    paddingHorizontal: 24,
    gap: 24,
    width: '100%',
  },
  footerLink: {
    paddingVertical: 8,
  },
  footerLinkText: {
    fontSize: 11,
    color: '#9ca3af', // text-gray-400
  },
});

