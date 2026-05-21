import { Apple, GoogleColor as Google } from '@/components/icons/icons';
import { TodusLogo } from '@/components/ui/todus-logo';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { authClient, signIn } from '@/lib/auth-client';
import { authProxy } from '@/lib/auth-proxy';
import { AlertCircle, ArrowLeft, Loader2, Mail } from 'lucide-react';
import { useEffect, useState } from 'react';
import { redirect, useNavigate, useSearchParams } from 'react-router';
import { toast } from 'sonner';
import type { Route } from './+types/page';

type Provider = 'google' | 'apple';
type EmailStep = 'idle' | 'enter-email' | 'enter-code';

// Block signed-in users from re-running OAuth on /login.
// Without this guard, a logged-in user clicking "Continue with Google" with a
// different Google account would be silently linked onto the existing user row
// via Better Auth's trustedProviders → cross-account mailbox leak.
//
// Two extra defenses vs. naive `await getSession()`:
//   1. Skip the round-trip entirely when no cookies are present (crawlers /
//      health checks / cold visitors). Saves a backend hit per impression.
//   2. Race against a 3s timeout so a slow/offline backend never blocks the
//      login page from rendering — without this, the screen hung indefinitely
//      during outages, leaving users with nothing to look at.
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const hasCookies = !!request.headers.get('cookie');
  if (!hasCookies) return null;
  const session = await Promise.race<Awaited<ReturnType<typeof authProxy.api.getSession>> | null>([
    authProxy.api.getSession({ headers: request.headers }),
    new Promise((resolve) => setTimeout(() => resolve(null), 3000)),
  ]);
  if (session?.user?.id) throw redirect('/mail/inbox');
  return null;
}

const ERROR_MESSAGES: Record<string, string> = {
  required_scopes_missing:
    'We need full Gmail access to load your mail. Reconnect and grant all permissions.',
  invalid_connection: 'That connection is no longer valid. Please sign in again.',
};

// Apple Sign-In on the web requires a separately-provisioned Services ID
// (NOT the iOS app bundle ID) and a matching redirect URI registered in the
// Apple Developer console. Until both are set on the server (APPLE_WEB_CLIENT_ID)
// and this flag is flipped, the button stays hidden — clicking it otherwise
// would land on an Apple error page (`invalid_client`).
const APPLE_WEB_ENABLED =
  String(import.meta.env.VITE_PUBLIC_APPLE_WEB_ENABLED ?? '').toLowerCase() === 'true';

export default function LoginTodus() {
  const [redirectingProvider, setRedirectingProvider] = useState<Provider | null>(null);
  const [searchParams, setSearchParams] = useSearchParams();
  const errorKey = searchParams.get('error');
  const navigate = useNavigate();

  // Email-OTP state. Step machine: idle → enter-email → enter-code → success.
  // Kept inside the same page (no new route) so the existing OAuth buttons
  // remain the primary entry point and OTP slots in below them.
  const [emailStep, setEmailStep] = useState<EmailStep>('idle');
  const [otpEmail, setOtpEmail] = useState('');
  const [otpCode, setOtpCode] = useState('');
  const [otpSending, setOtpSending] = useState(false);
  const [otpVerifying, setOtpVerifying] = useState(false);

  useEffect(() => {
    if (!errorKey) return;
    const message = ERROR_MESSAGES[errorKey] ?? 'Something went wrong. Please sign in again.';
    toast.error(message);
    // Strip ?error= so a refresh doesn't re-fire the toast.
    const next = new URLSearchParams(searchParams);
    next.delete('error');
    setSearchParams(next, { replace: true });
  }, [errorKey, searchParams, setSearchParams]);

  async function handleSocialSignIn(provider: Provider) {
    if (redirectingProvider) return;
    setRedirectingProvider(provider);
    try {
      await signIn.social({
        provider,
        callbackURL: `${window.location.origin}/mail/inbox`,
      });
    } catch (error) {
      console.error(`${provider} sign-in failed:`, error);
      toast.error(
        provider === 'google'
          ? 'Could not start Google sign-in. Please try again.'
          : 'Could not start Apple sign-in. Please try again.',
      );
      setRedirectingProvider(null);
    }
  }

  async function handleSendOtp(event: React.FormEvent) {
    event.preventDefault();
    const email = otpEmail.trim().toLowerCase();
    if (!email) return;
    setOtpSending(true);
    try {
      // Calls POST /api/auth/email-otp/send-verification-otp on the server.
      const { error } = await authClient.emailOtp.sendVerificationOtp({
        email,
        type: 'sign-in',
      });
      if (error) throw new Error(error.message ?? 'Failed to send code');
      toast.success(`Code sent to ${email}`);
      setOtpCode('');
      setEmailStep('enter-code');
    } catch (error) {
      console.error('Failed to send email OTP:', error);
      toast.error(
        error instanceof Error
          ? error.message
          : "Couldn't send code. Check the address and try again.",
      );
    } finally {
      setOtpSending(false);
    }
  }

  async function handleVerifyOtp(event: React.FormEvent) {
    event.preventDefault();
    const code = otpCode.trim();
    if (code.length < 6) {
      toast.error('Enter the 6-digit code from your email.');
      return;
    }
    setOtpVerifying(true);
    try {
      // Calls POST /api/auth/sign-in/email-otp. On success the session cookie
      // is set; navigate to the inbox the same way OAuth flows land.
      const { error } = await signIn.emailOtp({ email: otpEmail.trim().toLowerCase(), otp: code });
      if (error) throw new Error(error.message ?? 'Verification failed');
      toast.success('Signed in');
      void navigate('/mail/inbox', { replace: true });
    } catch (error) {
      console.error('Failed to verify email OTP:', error);
      toast.error(error instanceof Error ? error.message : 'Code was rejected. Try again.');
    } finally {
      setOtpVerifying(false);
    }
  }

  function resetEmailFlow() {
    setEmailStep('idle');
    setOtpEmail('');
    setOtpCode('');
  }

  return (
    <div className="flex min-h-screen w-full bg-background">
      {/* Left Column - Form */}
      <div className="flex w-full flex-col p-8 md:p-10 xl:p-14">
        <div className="mb-auto">
          <TodusLogo height={28} className="text-foreground" />
        </div>

        <div className="mx-auto flex w-full max-w-[340px] flex-col justify-center my-auto animate-in slide-in-from-bottom-4 duration-500">
          <div className="mb-7 flex flex-col items-start text-left">
            <h1 className="text-xl font-semibold tracking-tight text-foreground">Welcome back to Todus</h1>
            <p className="text-xl font-semibold tracking-tight text-muted-foreground mb-3">
              Your AI agent for emails
            </p>
            <p className="text-[13px] text-muted-foreground">
              Continue with the account you signed up with.
            </p>
          </div>

          {errorKey && ERROR_MESSAGES[errorKey] && (
            <div
              role="alert"
              className="mb-4 flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-[13px] text-destructive"
            >
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
              <p>{ERROR_MESSAGES[errorKey]}</p>
            </div>
          )}

          {/* OAuth Buttons */}
          <div className="flex flex-col gap-2.5 mb-6">
            <Button
              type="button"
              variant="outline"
              onClick={() => handleSocialSignIn('google')}
              disabled={redirectingProvider !== null}
              className="w-full h-10"
            >
              {redirectingProvider === 'google' ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Redirecting to Google…
                </>
              ) : (
                <>
                  <Google className="mr-2 h-4 w-4" />
                  Continue with Google
                </>
              )}
            </Button>
            {APPLE_WEB_ENABLED && (
              <Button
                type="button"
                variant="outline"
                onClick={() => handleSocialSignIn('apple')}
                disabled={redirectingProvider !== null}
                className="w-full h-10"
              >
                {redirectingProvider === 'apple' ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Redirecting to Apple…
                  </>
                ) : (
                  <>
                    <Apple className="mr-2 h-4 w-4 fill-current" />
                    Continue with Apple
                  </>
                )}
              </Button>
            )}

            {emailStep === 'idle' ? (
              <Button
                type="button"
                variant="outline"
                onClick={() => setEmailStep('enter-email')}
                disabled={redirectingProvider !== null}
                className="w-full h-10"
              >
                <Mail className="mr-2 h-4 w-4" />
                Continue with email
              </Button>
            ) : null}
          </div>

          {emailStep === 'enter-email' && (
            <form onSubmit={handleSendOtp} className="mb-6 space-y-3">
              <label
                htmlFor="otp-email"
                className="text-[12px] font-medium text-muted-foreground"
              >
                Email address
              </label>
              <Input
                id="otp-email"
                type="email"
                autoComplete="email"
                inputMode="email"
                placeholder="you@example.com"
                value={otpEmail}
                onChange={(e) => setOtpEmail(e.target.value)}
                autoFocus
                required
                className="h-10"
              />
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={resetEmailFlow}
                  className="px-2"
                  aria-label="Back"
                >
                  <ArrowLeft className="h-4 w-4" />
                </Button>
                <Button type="submit" disabled={otpSending} className="h-10 flex-1">
                  {otpSending ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Sending code…
                    </>
                  ) : (
                    'Send 6-digit code'
                  )}
                </Button>
              </div>
              <p className="text-[12px] text-muted-foreground">
                We&apos;ll email a 6-digit code that expires in 5 minutes.
              </p>
            </form>
          )}

          {emailStep === 'enter-code' && (
            <form onSubmit={handleVerifyOtp} className="mb-6 space-y-3">
              <label
                htmlFor="otp-code"
                className="text-[12px] font-medium text-muted-foreground"
              >
                Enter the code sent to{' '}
                <span className="text-foreground">{otpEmail}</span>
              </label>
              <Input
                id="otp-code"
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]*"
                maxLength={6}
                placeholder="123456"
                value={otpCode}
                onChange={(e) => setOtpCode(e.target.value.replace(/\D/g, ''))}
                autoFocus
                required
                className="h-10 tracking-[0.5em] text-center font-mono text-lg"
              />
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => setEmailStep('enter-email')}
                  className="px-2"
                  aria-label="Use a different email"
                >
                  <ArrowLeft className="h-4 w-4" />
                </Button>
                <Button
                  type="submit"
                  disabled={otpVerifying || otpCode.length < 6}
                  className="h-10 flex-1"
                >
                  {otpVerifying ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Verifying…
                    </>
                  ) : (
                    'Verify & sign in'
                  )}
                </Button>
              </div>
              <button
                type="button"
                onClick={(e) => {
                  e.preventDefault();
                  void handleSendOtp(new Event('submit') as unknown as React.FormEvent);
                }}
                disabled={otpSending}
                className="text-[12px] text-muted-foreground underline-offset-2 hover:underline disabled:opacity-50"
              >
                {otpSending ? 'Resending…' : 'Resend code'}
              </button>
            </form>
          )}

          {/*
            Legacy email/password auth kept here for future re-enable.

            <div className="relative mb-4">
              <div className="absolute inset-0 flex items-center">
                <span className="w-full border-t border-border" />
              </div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-background px-2 text-muted-foreground">or</span>
              </div>
            </div>

            <Form {...form}>
              <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
                <FormField
                  control={form.control}
                  name="email"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Email</FormLabel>
                      <FormControl>
                        <Input placeholder="email@example.com" {...field} />
                      </FormControl>
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="password"
                  render={({ field }) => (
                    <FormItem>
                      <div className="flex items-center justify-between">
                        <FormLabel>Password</FormLabel>
                        <Link
                          to="/forgot-password"
                          className="text-muted-foreground text-xs hover:text-foreground"
                        >
                          Forgot your password?
                        </Link>
                      </div>
                      <FormControl>
                        <Input type="password" placeholder="••••••••" {...field} />
                      </FormControl>
                    </FormItem>
                  )}
                />

                <Button type="submit" className="w-full">
                  Login
                </Button>

                <div className="mt-6 text-center text-sm">
                  <p className="text-muted-foreground">
                    Don't have an account?{' '}
                    <a
                      href="/signup"
                      className="font-medium underline underline-offset-4 hover:text-foreground"
                    >
                      Sign up
                    </a>
                  </p>
                </div>
              </form>
            </Form>
          */}
        </div>

        <footer className="mt-auto">
          <div className="flex items-center gap-5">
            <a
              href="/terms"
              className="text-xs text-muted-foreground transition-colors hover:text-foreground"
            >
              Terms of Service
            </a>
            <a
              href="/privacy"
              className="text-xs text-muted-foreground transition-colors hover:text-foreground"
            >
              Privacy Policy
            </a>
          </div>
        </footer>
      </div>

      {/* Right Column - Image Showcase */}
      <div className="hidden w-1/2 p-3 xl:p-4">
        <div className="relative flex h-full w-full items-center justify-center overflow-hidden rounded-2xl bg-[#111113] border border-[#222224]">
          <div className="relative w-full h-full">
            <img
              src="/email-preview.png"
              alt="Todus Interface"
              className="rounded-lg border border-[#222224] shadow-[0_0_40px_-12px_rgba(0,0,0,0.4)] object-cover w-full h-full"
              style={{ objectPosition: 'left center', transformOrigin: 'center left' }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
