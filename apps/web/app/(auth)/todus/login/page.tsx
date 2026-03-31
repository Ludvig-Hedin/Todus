import { Apple, GoogleColor as Google } from '@/components/icons/icons';
import { signIn } from '@/lib/auth-client';
import { Button } from '@/components/ui/button';
import React from 'react';

export default function LoginTodus() {
  const [isGoogleLoading, setIsGoogleLoading] = React.useState(false);
  const [isAppleLoading, setIsAppleLoading] = React.useState(false);

  async function handleGoogleSignIn() {
    if (isGoogleLoading) return;
    setIsGoogleLoading(true);
    try {
      const { data, error } = await signIn.social({
        provider: 'google',
        callbackURL: `${window.location.origin}/mail/inbox`,
      });
      if (error) {
        toast.error(error.message || 'Google sign-in failed');
        return;
      }
      // Better Auth may return a redirect URL instead of auto-navigating
      if (data?.url) {
        window.location.href = data.url;
      } else if (data) {
        // Signed in but no redirect URL — go to inbox directly
        window.location.href = '/mail/inbox';
      } else {
        console.error('Google sign-in: unexpected empty response', data);
        toast.error('Sign-in failed: unexpected response');
      }
    } catch (err) {
      console.error('Google sign-in error:', err);
      toast.error('Google sign-in failed');
    } finally {
      setIsGoogleLoading(false);
    }
  }

  async function handleAppleSignIn() {
    if (isAppleLoading) return;
    setIsAppleLoading(true);
    try {
      const { data, error } = await signIn.social({
        provider: 'apple',
        callbackURL: `${window.location.origin}/mail/inbox`,
      });
      if (error) {
        toast.error(error.message || 'Apple sign-in failed');
        return;
      }
      if (data?.url) {
        window.location.href = data.url;
      } else if (data) {
        window.location.href = '/mail/inbox';
      } else {
        console.error('Apple sign-in: unexpected empty response', data);
        toast.error('Sign-in failed: unexpected response');
      }
    } catch (err) {
      console.error('Apple sign-in error:', err);
      toast.error('Apple sign-in failed');
    } finally {
      setIsAppleLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen w-full bg-background">
      {/* Left Column - Form */}
      <div className="flex w-full flex-col lg:w-1/2 p-8 md:p-10 xl:p-14">
        <div className="flex items-center gap-2 mb-auto">
          <img
            src="/brand-logo.png"
            alt="Todus Logo"
            className="h-7 w-7"
          />
          <span className="text-[15px] font-semibold tracking-tight text-foreground">Todus</span>
        </div>

        <div className="mx-auto flex w-full max-w-[340px] flex-col justify-center my-auto animate-in slide-in-from-bottom-4 duration-500">
          <div className="mb-7 flex flex-col items-start text-left">
            <h1 className="text-xl font-semibold tracking-tight text-foreground">Welcome to Todus</h1>
            <p className="text-xl font-semibold tracking-tight text-muted-foreground mb-3">
              Your AI agent for emails
            </p>
            <p className="text-[13px] text-muted-foreground">
              Sign up for free with your email
            </p>
          </div>

          {/* OAuth Buttons */}
          <div className="flex flex-col gap-2.5 mb-6">
            <Button
              type="button"
              variant="outline"
              onClick={handleGoogleSignIn}
              disabled={isGoogleLoading || isAppleLoading}
              className="w-full h-10"
            >
              <Google className="mr-2 h-4 w-4" />
              {isGoogleLoading ? 'Signing in...' : 'Continue with Google'}
            </Button>
            <Button
              type="button"
              variant="outline"
              onClick={handleAppleSignIn}
              disabled={isGoogleLoading || isAppleLoading}
              className="w-full h-10"
            >
              <Apple className="mr-2 h-4 w-4 fill-current" />
              {isAppleLoading ? 'Signing in...' : 'Continue with Apple'}
            </Button>
          </div>
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
      <div className="hidden lg:flex w-1/2 p-3 xl:p-4">
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
