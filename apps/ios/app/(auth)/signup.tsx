import * as AppleAuthentication from 'expo-apple-authentication';
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
  useColorScheme,
  Image,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { getNativeEnv } from '../../src/shared/config/env';
import { setBearerSessionAtom } from '../../src/shared/state/session';
import { getSocialAuthUrl } from '../../src/features/auth/native-auth';
import { GoogleColored } from '../../src/shared/components/icons';

// Required for expo-web-browser redirect handling
WebBrowser.maybeCompleteAuthSession();

export default function SignupScreen() {
  const env = getNativeEnv();
  const router = useRouter();
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  const setBearerSession = useSetAtom(setBearerSessionAtom);

  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    return () => {
      if (Platform.OS === 'ios') {
        WebBrowser.dismissAuthSession();
      }
    };
  }, []);

  useEffect(() => {
    if (!loading) return;
    const timeout = setTimeout(() => setLoading(false), 15000);
    return () => clearTimeout(timeout);
  }, [loading]);

  async function handleGoogleSignIn() {
    setLoading(true);
    setErrorMessage(null);

    try {
      const redirectUrl = 'todus://auth-callback';
      const backendBase = env.backendUrl.replace(/\/$/, '');
      const mobileTokenUrl = `${backendBase}/api/auth/mobile-token`;

      const googleOAuthUrl = await getSocialAuthUrl(
        env.backendUrl,
        env.webUrl,
        'google',
        mobileTokenUrl,
      );

      let authHandled = false;
      const handleAuthUrl = async (url: string) => {
        if (authHandled) return;
        const token = extractTokenFromUrl(url);
        if (token) {
          authHandled = true;
          if (Platform.OS === 'ios') WebBrowser.dismissAuthSession();
          await setBearerSession({ token, expiresAt: null });
        }
      };

      const subscription = Linking.addEventListener('url', ({ url }) => {
        handleAuthUrl(url);
      });

      try {
        const result = await WebBrowser.openAuthSessionAsync(googleOAuthUrl, redirectUrl);
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
          }
        }
      } catch (err) {
        subscription.remove();
        throw err;
      }
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'Failed to sign up with Google';
      setErrorMessage(message);
    } finally {
      setTimeout(() => setLoading(false), 500);
    }
  }

  async function handleAppleSignUp() {
    setLoading(true);
    setErrorMessage(null);

    try {
      const credential = await AppleAuthentication.signInAsync({
        requestedScopes: [
          AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
          AppleAuthentication.AppleAuthenticationScope.EMAIL,
        ],
      });

      if (credential.identityToken) {
        const backendBase = env.backendUrl.replace(/\/$/, '');
        const authUrl = `${backendBase}/api/auth/sign-in/social`;

        const response = await fetch(authUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            provider: 'apple',
            idToken: credential.identityToken,
            callbackURL: 'todus://auth-callback',
          }),
        });

        const result = await response.json();
        if (result.url) {
          const token = extractTokenFromUrl(result.url);
          if (token) {
            await setBearerSession({ token, expiresAt: null });
          } else {
            setErrorMessage('Failed to extract token from Apple sign-up response.');
          }
        } else if (result.error) {
          setErrorMessage(result.error.message || 'Apple sign-up failed on server.');
        }
      }
    } catch (error: unknown) {
      if ((error as { code?: string }).code === 'ERR_CANCELED') {
        // User cancelled
      } else {
        const message = error instanceof Error ? error.message : 'Failed to sign up with Apple';
        setErrorMessage(message);
      }
    } finally {
      setLoading(false);
    }
  }

  const themeStyles = isDark ? darkStyles : lightStyles;

  return (
    <SafeAreaView style={[styles.safeArea, themeStyles.container]}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <View style={styles.topHeader}>
        <Image
          source={require('../../assets/brand-logo.png')}
          style={[styles.smallLogo, themeStyles.logo]}
          resizeMode="contain"
        />
        <Text style={[styles.brandName, themeStyles.title]}>Todus</Text>
      </View>

      <View style={styles.content}>
        <View style={styles.headerContainer}>
          <Text style={[styles.title, themeStyles.title]}>Signup to Todus</Text>
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
              <ActivityIndicator size="small" color={isDark ? '#ffffff' : '#111111'} style={styles.icon} />
            ) : (
              <GoogleColored width={20} height={20} style={styles.icon} />
            )}
            <Text style={[styles.providerButtonText, themeStyles.providerButtonText]}>
              {loading ? 'Signing up...' : 'Continue with Google'}
            </Text>
          </Pressable>

          {Platform.OS === 'ios' && (
            <AppleAuthentication.AppleAuthenticationButton
              buttonType={AppleAuthentication.AppleAuthenticationButtonType.CONTINUE}
              buttonStyle={
                isDark
                  ? AppleAuthentication.AppleAuthenticationButtonStyle.WHITE
                  : AppleAuthentication.AppleAuthenticationButtonStyle.BLACK
              }
              cornerRadius={8}
              style={{ width: '100%', height: 40, marginTop: 12 }}
              onPress={handleAppleSignUp}
            />
          )}
        </View>

        <View style={styles.bottomCta}>
          <Text style={[styles.bottomCtaText, themeStyles.footerLinkText]}>Already have an account?</Text>
          <Pressable onPress={() => router.push('/(auth)/login')}>
            <Text style={[styles.bottomCtaLink, themeStyles.title]}>Login</Text>
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
  bottomCta: {
    marginTop: 18,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  bottomCtaText: {
    fontSize: 13,
  },
  bottomCtaLink: {
    fontSize: 13,
    fontWeight: '600',
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
    backgroundColor: '#fdfdfd',
  },
  title: {
    color: '#111111',
  },
  subtitle: {
    color: '#111111',
  },
  description: {
    color: '#111111',
  },
  providerButton: {
    backgroundColor: '#fdfdfd',
    borderColor: '#e5e5e5',
  },
  providerButtonPressed: {
    backgroundColor: '#f5f5f5',
  },
  providerButtonText: {
    color: '#111111',
  },
  footerLinkText: {
    color: '#686868',
  },
  dot: {
    backgroundColor: '#d9d9d9',
  },
  logo: {
    tintColor: '#111111',
  },
});

const darkStyles = StyleSheet.create({
  container: {
    backgroundColor: '#0b0b0b',
  },
  title: {
    color: '#f5f5f5',
  },
  subtitle: {
    color: '#f5f5f5',
  },
  description: {
    color: '#f5f5f5',
  },
  providerButton: {
    backgroundColor: '#0b0b0b',
    borderColor: '#2a2a2a',
  },
  providerButtonPressed: {
    backgroundColor: '#171717',
  },
  providerButtonText: {
    color: '#f5f5f5',
  },
  footerLinkText: {
    color: '#8a8a8a',
  },
  dot: {
    backgroundColor: '#333333',
  },
  logo: {
    tintColor: '#f5f5f5',
  },
});
