import * as AppleAuthentication from 'expo-apple-authentication';
import * as WebBrowser from 'expo-web-browser';
import * as Linking from 'expo-linking';
import { useSetAtom } from 'jotai';
import { useEffect, useState } from 'react';
import {
  Image,
  Platform,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaView } from 'react-native-safe-area-context';
import { getNativeEnv } from '../../src/shared/config/env';
import { setBearerSessionAtom } from '../../src/shared/state/session';
import { getSocialAuthUrl } from '../../src/features/auth/native-auth';
import { AppleLogo, GoogleColored } from '../../src/shared/components/icons';
import { useTheme } from '../../src/shared/theme/ThemeContext';
import { Button } from '@zero/ui-native';

// Required for expo-web-browser redirect handling
WebBrowser.maybeCompleteAuthSession();

export default function LoginScreen() {
  const env = getNativeEnv();
  const { colors, ui, isDark, spacing, radius } = useTheme();
  const setBearerSession = useSetAtom(setBearerSessionAtom);

  const [loadingGoogle, setLoadingGoogle] = useState(false);
  const [loadingApple, setLoadingApple] = useState(false);
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
    if (!loadingGoogle && !loadingApple) return;
    const timeout = setTimeout(() => {
      setLoadingGoogle(false);
      setLoadingApple(false);
    }, 15000);
    return () => clearTimeout(timeout);
  }, [loadingGoogle, loadingApple]);

  async function handleGoogleSignIn() {
    setLoadingGoogle(true);
    setErrorMessage(null);

    try {
      // 1. Build the deep link URL that SFSafariViewController will listen for.
      // IMPORTANT: Do NOT use Linking.createURL() here — in Expo dev mode it
      // returns exp://192.168.x.x:8081/--/auth-callback, which doesn't match
      // the production server's redirect to todus://auth-callback. Hardcode
      // the scheme so it always matches what the server sends back.
      const redirectUrl = 'todus://auth-callback';

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
          setLoadingGoogle(false);
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
      setTimeout(() => setLoadingGoogle(false), 500);
    }
  }

  async function handleAppleSignIn() {
    setLoadingApple(true);
    setErrorMessage(null);

    try {
      console.log('[AppleSignIn] Starting Apple authentication...');
      const credential = await AppleAuthentication.signInAsync({
        requestedScopes: [
          AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
          AppleAuthentication.AppleAuthenticationScope.EMAIL,
        ],
      });

      console.log('[AppleSignIn] credential received:', {
        identityToken: credential.identityToken ? 'present' : 'missing',
        user: credential.user,
        email: credential.email,
        fullName: credential.fullName,
      });

      if (credential.identityToken) {
        // Better Auth uses /sign-in/social with idToken as an object { token }
        // for native ID token sign-in (not a raw string). This is different from
        // the redirect-based OAuth flow which takes { provider, callbackURL }.
        const backendBase = env.backendUrl.replace(/\/$/, '');
        const authUrl = `${backendBase}/api/auth/sign-in/social`;

        console.log('[AppleSignIn] sending idToken to:', authUrl);
        console.log('[AppleSignIn] idToken length:', credential.identityToken.length);

        const response = await fetch(authUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            provider: 'apple',
            idToken: {
              token: credential.identityToken,
            },
            callbackURL: 'todus://auth-callback',
          }),
        });

        console.log('[AppleSignIn] fetch response status:', response.status);

        if (!response.ok) {
          const errorText = await response.text();
          console.error('[AppleSignIn] server error response:', errorText);
          setErrorMessage(`Apple Sign-in server error (${response.status}). Please try again.`);
          return;
        }

        const result = await response.json();
        console.log('[AppleSignIn] response body:', JSON.stringify(result));

        // Better Auth returns bearer token in set-auth-token header and/or
        // session data in the response body for ID token sign-in.
        const bearerToken =
          response.headers.get('set-auth-token') ??
          result?.token ??
          result?.session?.token ??
          null;

        if (bearerToken) {
          console.log('[AppleSignIn] bearer token received, length:', bearerToken.length);
          await setBearerSession({ token: bearerToken, expiresAt: null });
        } else if (result.url) {
          // Fallback: some flows return a redirect URL with token
          console.log('[AppleSignIn] received redirect URL:', result.url);
          const token = extractTokenFromUrl(result.url);
          if (token) {
            await setBearerSession({ token, expiresAt: null });
          } else {
            console.error('[AppleSignIn] failed to extract token from URL:', result.url);
            setErrorMessage('Failed to extract token from Apple login response.');
          }
        } else if (result.error) {
          console.error('[AppleSignIn] server returned error:', result.error);
          setErrorMessage(result.error.message || 'Apple Sign-in failed on server.');
        } else {
          console.error('[AppleSignIn] unexpected response format:', result);
          setErrorMessage('Unexpected response from server.');
        }
      } else {
        setErrorMessage('Apple did not provide an identity token. Please try again.');
      }
    } catch (e: any) {
      console.error('[AppleSignIn] catch block error:', {
        code: e.code,
        message: e.message,
        stack: e.stack,
      });
      if (
        e.code === 'ERR_CANCELED' ||
        e.code === 'ERR_REQUEST_CANCELED' ||
        (e.message && e.message.includes('canceled'))
      ) {
        console.log('[AppleSignIn] user cancelled');
      } else {
        console.error('[AppleSignIn] unexpected error:', e);
        setErrorMessage(e.message || 'Failed to sign in with Apple');
      }
    } finally {
      setLoadingApple(false);
    }
  }

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: ui.canvas }]}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <View style={styles.content}>
        <View style={[styles.headerContainer, { marginBottom: spacing[8] }]}>
          <Image
            source={require('../../assets/brand-logo.png')}
            style={[styles.symbolLogo, { tintColor: colors.foreground, marginBottom: spacing[3] }]}
            resizeMode="contain"
          />
          <Text style={[styles.title, { color: colors.foreground }]}>Welcome to Todus</Text>
          <Text style={[styles.subtitle, { color: colors.mutedForeground, marginBottom: spacing[4] }]}>Your AI agent for emails</Text>
          <Text style={[styles.description, { color: colors.mutedForeground }]}>
            Sign up for free with your email
          </Text>
        </View>

        {errorMessage && (
          <View style={[styles.errorBox, { backgroundColor: `${colors.destructive}1A`, borderColor: `${colors.destructive}33` }]}>
            <Text style={[styles.errorTitle, { color: colors.destructive }]}>Sign-in Failed</Text>
            <Text style={[styles.errorText, { color: colors.destructive }]}>{errorMessage || 'An unexpected error occurred. Please try again.'}</Text>
          </View>
        )}

        <View style={[styles.providersContainer, { gap: spacing[4] }]}>
          <Button
            tone="outline"
            colorMode={isDark ? 'dark' : 'light'}
            onPress={handleGoogleSignIn}
            isLoading={loadingGoogle}
            disabled={loadingGoogle || loadingApple}
            icon={<GoogleColored width={20} height={20} />}
            textStyle={{ color: colors.foreground }}
          >
            Continue with Google
          </Button>

          {Platform.OS === 'ios' && (
            <Button
              tone="primary"
              colorMode={isDark ? 'dark' : 'light'}
              onPress={handleAppleSignIn}
              isLoading={loadingApple}
              disabled={loadingGoogle || loadingApple}
              icon={<AppleLogo width={20} height={20} color={colors.primaryForeground} />}
              textStyle={{ color: colors.primaryForeground }}
            >
              Continue with Apple
            </Button>
          )}
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
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
    maxWidth: 600,
    width: '100%',
    alignSelf: 'center',
  },
  headerContainer: {
    marginBottom: 32,
    alignItems: 'center',
    width: '100%',
  },
  symbolLogo: {
    width: 24,
    height: 24,
    marginBottom: 12,
  },
  title: {
    fontSize: 24,
    fontWeight: '600',
    textAlign: 'center',
    marginBottom: 0,
    letterSpacing: -0.5,
  },
  subtitle: {
    fontSize: 24,
    fontWeight: '600',
    textAlign: 'center',
    opacity: 0.6,
    marginBottom: 16,
    letterSpacing: -0.5,
  },
  description: {
    fontSize: 14,
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
    alignItems: 'center',
  },
  errorTitle: {
    fontWeight: '600',
    fontSize: 14,
    marginBottom: 4,
    textAlign: 'center',
  },
  errorText: {
    fontSize: 14,
    opacity: 0.8,
    textAlign: 'center',
  },
  providersContainer: {
    width: '100%',
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
    textAlign: 'center',
  },
  dot: {
    width: 3,
    height: 3,
    borderRadius: 1.5,
    marginHorizontal: 12,
  },
});

