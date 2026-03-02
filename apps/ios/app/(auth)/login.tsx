import * as WebBrowser from 'expo-web-browser';
import * as Linking from 'expo-linking';
import { useSetAtom } from 'jotai';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
  SafeAreaView,
  useColorScheme,
  Image,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { getNativeEnv } from '../../src/shared/config/env';
import { setBearerSessionAtom } from '../../src/shared/state/session';
import { getSocialAuthUrl } from '../../src/features/auth/native-auth';
import { GoogleColored } from '../../src/shared/components/icons';

// Required for expo-web-browser redirect handling
WebBrowser.maybeCompleteAuthSession();

export default function LoginScreen() {
  const env = getNativeEnv();
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  const setBearerSession = useSetAtom(setBearerSessionAtom);

  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Clean up browser session on unmount (iOS-only)
  useEffect(() => {
    return () => {
      if (Platform.OS === 'ios') {
        WebBrowser.dismissAuthSession();
      }
    };
  }, []);

  // Failsafe: reset loading if stuck for >15s
  useEffect(() => {
    if (!loading) return;
    const timeout = setTimeout(() => setLoading(false), 15000);
    return () => clearTimeout(timeout);
  }, [loading]);

  async function handleGoogleSignIn() {
    setLoading(true);
    setErrorMessage(null);

    try {
      // 1. Build the deep link URL that SFSafariViewController will listen for.
      // Force double-slash scheme (todus://) to match Info.plist configuration.
      let redirectUrl = Linking.createURL('auth-callback', { scheme: 'todus' });
      if (redirectUrl.includes(':///')) {
        redirectUrl = redirectUrl.replace(':///', '://');
      }

      // Debug: log the exact redirect URL so we can verify it matches what the server sends
      console.log('[GoogleSignIn] redirectUrl for openAuthSessionAsync:', redirectUrl);

      // 2. The callbackURL tells better-auth where to redirect AFTER Google OAuth.
      // We point it to the mobile-token bridge which reads the session cookie
      // (available in SFSafariViewController) and redirects to todus:// with token.
      // IMPORTANT: Keep this URL clean without extra query params — better-auth
      // may mangle or drop query strings in the callbackURL during redirect processing.
      const backendBase = env.backendUrl.replace(/\/$/, '');
      const mobileTokenUrl = `${backendBase}/api/auth/mobile-token`;
      console.log('[GoogleSignIn] mobileTokenUrl (callbackURL for better-auth):', mobileTokenUrl);

      // 3. Get the Google OAuth consent URL from better-auth.
      const googleOAuthUrl = await getSocialAuthUrl(
        env.backendUrl,
        env.webUrl,
        'google',
        mobileTokenUrl,
      );
      console.log('[GoogleSignIn] googleOAuthUrl:', googleOAuthUrl);

      // 4. Open in SFSafariViewController (iOS system browser sheet).
      // This shares cookies with Safari, handles redirects natively, and
      // auto-closes when it detects the todus:// deep link redirect.
      let authHandled = false;

      const handleAuthUrl = async (url: string) => {
        if (authHandled) return;
        console.log('[GoogleSignIn] handleAuthUrl received:', url);
        const token = extractTokenFromUrl(url);
        if (token) {
          authHandled = true;
          if (Platform.OS === 'ios') WebBrowser.dismissAuthSession();
          await setBearerSession({ token, expiresAt: null });
        }
      };

      // Fallback listener for deep link redirects (iOS edge cases)
      const subscription = Linking.addEventListener('url', ({ url }) => {
        console.log('[GoogleSignIn] Linking url event:', url);
        handleAuthUrl(url);
      });

      try {
        const result = await WebBrowser.openAuthSessionAsync(googleOAuthUrl, redirectUrl);
        console.log('[GoogleSignIn] openAuthSessionAsync result:', JSON.stringify(result));
        subscription.remove();

        if (!authHandled) {
          setLoading(false);
          if (result.type === 'success' && result.url) {
            const token = extractTokenFromUrl(result.url);
            if (token) {
              authHandled = true;
              await setBearerSession({ token, expiresAt: null });
            } else {
              setErrorMessage('No authentication token received. Please try again.');
            }
          } else if (result.type === 'dismiss' || result.type === 'cancel') {
            // User closed the browser — no error needed
          }
        }
      } catch (err) {
        subscription.remove();
        throw err;
      }
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : 'Failed to sign in with Google';
      setErrorMessage(message);
    } finally {
      setTimeout(() => setLoading(false), 500);
    }
  }

  const themeStyles = isDark ? darkStyles : lightStyles;

  return (
    <SafeAreaView style={[styles.safeArea, themeStyles.container]}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <View style={styles.topHeader}>
        <Image
          source={require('../../assets/brand-logo.png')}
          style={styles.smallLogo}
          resizeMode="contain"
        />
        <Text style={[styles.brandName, themeStyles.title]}>Todus</Text>
      </View>

      <View style={styles.content}>
        <View style={styles.headerContainer}>
          <Text style={[styles.title, themeStyles.title]}>Welcome to Todus</Text>
          <Text style={[styles.subtitle, themeStyles.subtitle]}>Your AI agent for emails</Text>
          <Text style={[styles.description, themeStyles.description]}>Sign up for free with your email</Text>
        </View>

        {errorMessage && (
          <View style={styles.errorBox}>
            <Text style={styles.errorTitle}>Error</Text>
            <Text style={styles.errorText}>{errorMessage}</Text>
          </View>
        )}

        <View style={styles.providersContainer}>
          <Pressable
            onPress={handleGoogleSignIn}
            disabled={loading}
            style={({ pressed }) => [
              styles.providerButton,
              themeStyles.providerButton,
              pressed && themeStyles.providerButtonPressed,
              loading && styles.providerButtonDisabled,
            ]}
          >
            {loading ? (
              <ActivityIndicator size="small" color={isDark ? '#ffffff' : '#000000'} style={styles.icon} />
            ) : (
              <GoogleColored width={20} height={20} style={styles.icon} />
            )}
            <Text style={[styles.providerButtonText, themeStyles.providerButtonText]}>
              {loading ? 'Signing in...' : 'Continue with Google'}
            </Text>
          </Pressable>
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

/** Extracts the bearer token from a todus:// deep link URL */
function extractTokenFromUrl(rawUrl: string): string | null {
  try {
    const url = new URL(rawUrl);
    return (
      url.searchParams.get('token') ??
      url.searchParams.get('set-auth-token') ??
      url.searchParams.get('authToken') ??
      null
    );
  } catch {
    return null;
  }
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  topHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 32,
    paddingTop: 16,
    gap: 8,
  },
  smallLogo: {
    width: 32,
    height: 32,
  },
  brandName: {
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: -0.5,
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'flex-start',
    paddingHorizontal: 32,
    maxWidth: 600,
    width: '100%',
    alignSelf: 'center',
  },
  headerContainer: {
    marginBottom: 32,
    alignItems: 'flex-start',
    width: '100%',
  },
  title: {
    fontSize: 24,
    fontWeight: '600',
    textAlign: 'left',
    marginBottom: 0,
    letterSpacing: -0.5,
  },
  subtitle: {
    fontSize: 24,
    fontWeight: '600',
    textAlign: 'left',
    opacity: 0.6,
    marginBottom: 16,
    letterSpacing: -0.5,
  },
  description: {
    fontSize: 14,
    fontWeight: '400',
    textAlign: 'left',
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
  providerButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    height: 40,
    borderRadius: 8,
    borderWidth: 1,
  },
  providerButtonDisabled: {
    opacity: 0.7,
  },
  providerButtonText: {
    fontSize: 14,
    fontWeight: '500',
  },
  icon: {
    marginRight: 8,
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
  description: {
    color: '#000000',
  },
  providerButton: {
    backgroundColor: '#FFFFFF',
    borderColor: '#E5E5E5',
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
  description: {
    color: '#FFFFFF',
  },
  providerButton: {
    backgroundColor: '#0A0A0A',
    borderColor: '#2A2A2A',
  },
  providerButtonPressed: {
    backgroundColor: '#1A1A1A',
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
