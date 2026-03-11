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
  Image,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { getNativeEnv } from '../../src/shared/config/env';
import { setBearerSessionAtom } from '../../src/shared/state/session';
import { getSocialAuthUrl } from '../../src/features/auth/native-auth';
import { AppleLogo, GoogleColored } from '../../src/shared/components/icons';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import { Button } from '@zero/ui-native';

// Required for expo-web-browser redirect handling
WebBrowser.maybeCompleteAuthSession();

export default function SignupScreen() {
  const env = getNativeEnv();
  const router = useRouter();
  const { colors, ui, isDark, spacing, radius } = useTheme();
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

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: ui.canvas }]}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <View style={[styles.topHeader, { paddingTop: spacing[4], paddingHorizontal: spacing[8], gap: spacing[2] }]}>
        <Image
          source={require('../../assets/brand-logo.png')}
          style={[styles.smallLogo, { tintColor: colors.foreground }]}
          resizeMode="contain"
        />
        <Text style={[styles.brandName, { color: colors.foreground }]}>Todus</Text>
      </View>

      <View style={styles.content}>
        <View style={[styles.headerContainer, { marginBottom: spacing[8] }]}>
          <Text style={[styles.title, { color: colors.foreground }]}>Signup to Todus</Text>
          <Text style={[styles.subtitle, { color: colors.mutedForeground, marginBottom: spacing[4] }]}>Your AI agent for emails</Text>
          <Text style={[styles.description, { color: colors.mutedForeground }]}>Sign up for free with your email</Text>
        </View>

        {errorMessage && (
          <View style={[styles.errorBox, { backgroundColor: `${colors.destructive}1A`, borderColor: `${colors.destructive}33` }]}>
            <Text style={[styles.errorTitle, { color: colors.destructive }]}>Sign-up Failed</Text>
            <Text style={[styles.errorText, { color: colors.destructive }]}>{errorMessage}</Text>
          </View>
        )}

        <View style={[styles.providersContainer, { gap: spacing[4] }]}>
          <Button
            tone="outline"
            colorMode={isDark ? 'dark' : 'light'}
            onPress={handleGoogleSignIn}
            isLoading={loading}
            disabled={loading}
            icon={<GoogleColored width={20} height={20} />}
            textStyle={{ color: colors.foreground }}
            style={{ borderRadius: radius.xl, height: 48 }}
          >
            Continue with Google
          </Button>

          {Platform.OS === 'ios' && (
            <Button
              tone="primary"
              colorMode={isDark ? 'dark' : 'light'}
              onPress={handleAppleSignUp}
              isLoading={loading}
              disabled={loading}
              icon={<AppleLogo width={20} height={20} color={colors.primaryForeground} />}
              textStyle={{ color: colors.primaryForeground }}
              style={{ borderRadius: radius.xl, height: 48 }}
            >
              Continue with Apple
            </Button>
          )}
        </View>

        <View style={[styles.bottomCta, { marginTop: spacing[4], gap: spacing[1] }]}>
          <Text style={[styles.bottomCtaText, { color: colors.mutedForeground }]}>Already have an account?</Text>
          <Pressable onPress={() => router.push('/(auth)/login')}>
            <Text style={[styles.bottomCtaLink, { color: colors.foreground }]}>Login</Text>
          </Pressable>
        </View>
      </View>

      <View style={[styles.footer, { paddingVertical: spacing[6], paddingHorizontal: spacing[6] }]}>
        <Text style={[styles.footerLinkText, { color: colors.mutedForeground }]}>Terms of Service</Text>
        <View style={[styles.dot, { backgroundColor: ui.borderStrong }]} />
        <Text style={[styles.footerLinkText, { color: colors.mutedForeground }]}>Privacy Policy</Text>
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
    borderWidth: 1,
    borderRadius: 12,
    padding: 16,
  },
  errorTitle: {
    fontWeight: '600',
    fontSize: 14,
    marginBottom: 4,
  },
  errorText: {
    fontSize: 14,
    opacity: 0.8,
  },
  providersContainer: {
    width: '100%',
  },
  bottomCta: {
    flexDirection: 'row',
    alignItems: 'center',
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

