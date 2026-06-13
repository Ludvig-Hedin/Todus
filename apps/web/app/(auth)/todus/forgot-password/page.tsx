import { TodusLogo } from '@/components/ui/todus-logo';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { authClient } from '@/lib/auth-client';
import { ArrowLeft, CheckCircle2, Loader2, Mail } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router';
import { toast } from 'sonner';

// Forgot-password flow. Calls Better Auth `requestPasswordReset` which emails the
// user a link to `${redirectTo}?token=…`. The server's `sendResetPassword` handler
// (apps/server/src/lib/auth.ts) dispatches the mail via Resend. We always show the
// same success state regardless of whether the address exists — never confirm or
// deny account existence (enumeration protection).
export default function ForgotPasswordTodus() {
  const [email, setEmail] = useState('');
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const trimmed = email.trim().toLowerCase();
    if (!trimmed) return;
    setSending(true);
    try {
      const { error } = await authClient.requestPasswordReset({
        email: trimmed,
        redirectTo: `${window.location.origin}/reset-password`,
      });
      if (error) throw new Error(error.message ?? 'Failed to send reset link');
      setSent(true);
    } catch (error) {
      console.error('Failed to request password reset:', error);
      toast.error(
        error instanceof Error ? error.message : "Couldn't send a reset link. Try again.",
      );
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="flex min-h-screen w-full bg-background">
      {/* Left Column - Form */}
      <div className="flex w-full flex-col p-8 md:p-10 xl:p-14">
        <div className="mb-auto">
          <TodusLogo height={28} className="text-foreground" />
        </div>

        <div className="mx-auto flex w-full max-w-[340px] flex-col justify-center my-auto animate-in slide-in-from-bottom-4 duration-500">
          {sent ? (
            <div className="flex flex-col items-start text-left">
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-primary/10">
                <CheckCircle2 className="h-5 w-5 text-primary" aria-hidden />
              </div>
              <h1 className="text-xl font-semibold tracking-tight text-foreground">
                Check your email
              </h1>
              <p className="mt-2 text-[13px] text-muted-foreground">
                If an account exists for <span className="text-foreground">{email.trim()}</span>,
                we&apos;ve sent a link to reset your password. The link expires shortly.
              </p>
              <Button asChild variant="outline" className="mt-6 h-10 w-full">
                <Link to="/login">
                  <ArrowLeft className="mr-2 h-4 w-4" />
                  Back to sign in
                </Link>
              </Button>
            </div>
          ) : (
            <>
              <div className="mb-7 flex flex-col items-start text-left">
                <h1 className="text-xl font-semibold tracking-tight text-foreground">
                  Forgot your password?
                </h1>
                <p className="mt-2 text-[13px] text-muted-foreground">
                  Enter the email address linked to your account and we&apos;ll send you a link to
                  reset your password.
                </p>
              </div>

              <form onSubmit={handleSubmit} className="space-y-3">
                <label htmlFor="reset-email" className="text-[12px] font-medium text-muted-foreground">
                  Email address
                </label>
                <Input
                  id="reset-email"
                  type="email"
                  autoComplete="email"
                  inputMode="email"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoFocus
                  required
                  className="h-10"
                />
                <Button type="submit" disabled={sending} className="h-10 w-full">
                  {sending ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Sending link…
                    </>
                  ) : (
                    <>
                      <Mail className="mr-2 h-4 w-4" />
                      Send reset link
                    </>
                  )}
                </Button>
              </form>

              <Link
                to="/login"
                className="mt-6 inline-flex items-center gap-1.5 text-[12px] text-muted-foreground transition-colors hover:text-foreground"
              >
                <ArrowLeft className="h-3.5 w-3.5" />
                Back to sign in
              </Link>
            </>
          )}
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
