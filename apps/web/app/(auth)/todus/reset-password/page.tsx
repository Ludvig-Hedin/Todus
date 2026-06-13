import { TodusLogo } from '@/components/ui/todus-logo';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { authClient } from '@/lib/auth-client';
import { AlertCircle, ArrowLeft, Loader2, Lock } from 'lucide-react';
import { useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { toast } from 'sonner';

const MIN_PASSWORD_LENGTH = 8;

// Reset-password flow. Better Auth emails a link to `/reset-password?token=…`.
// On an expired/invalid token it instead redirects here with `?error=INVALID_TOKEN`.
// We read the token from the query string and call `resetPassword({ newPassword, token })`.
export default function ResetPasswordTodus() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const token = searchParams.get('token');
  const tokenError = searchParams.get('error');

  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const invalidToken = !token || !!tokenError;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!token) return;
    if (password.length < MIN_PASSWORD_LENGTH) {
      toast.error(`Password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
      return;
    }
    if (password !== confirm) {
      toast.error('Passwords do not match.');
      return;
    }
    setSubmitting(true);
    try {
      const { error } = await authClient.resetPassword({ newPassword: password, token });
      if (error) throw new Error(error.message ?? 'Failed to reset password');
      toast.success('Password updated. Please sign in.');
      void navigate('/login', { replace: true });
    } catch (error) {
      console.error('Failed to reset password:', error);
      toast.error(
        error instanceof Error ? error.message : 'Could not reset your password. Try again.',
      );
    } finally {
      setSubmitting(false);
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
          {invalidToken ? (
            <div className="flex flex-col items-start text-left">
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-destructive/10">
                <AlertCircle className="h-5 w-5 text-destructive" aria-hidden />
              </div>
              <h1 className="text-xl font-semibold tracking-tight text-foreground">
                This reset link is invalid
              </h1>
              <p className="mt-2 text-[13px] text-muted-foreground">
                The link may have expired or already been used. Request a new password reset link to
                continue.
              </p>
              <Button asChild variant="outline" className="mt-6 h-10 w-full">
                <Link to="/forgot-password">Request a new link</Link>
              </Button>
              <Link
                to="/login"
                className="mt-4 inline-flex items-center gap-1.5 text-[12px] text-muted-foreground transition-colors hover:text-foreground"
              >
                <ArrowLeft className="h-3.5 w-3.5" />
                Back to sign in
              </Link>
            </div>
          ) : (
            <>
              <div className="mb-7 flex flex-col items-start text-left">
                <h1 className="text-xl font-semibold tracking-tight text-foreground">
                  Set a new password
                </h1>
                <p className="mt-2 text-[13px] text-muted-foreground">
                  Choose a strong password you don&apos;t use anywhere else.
                </p>
              </div>

              <form onSubmit={handleSubmit} className="space-y-3">
                <div className="space-y-1.5">
                  <label
                    htmlFor="new-password"
                    className="text-[12px] font-medium text-muted-foreground"
                  >
                    New password
                  </label>
                  <Input
                    id="new-password"
                    type="password"
                    autoComplete="new-password"
                    placeholder="••••••••"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    autoFocus
                    required
                    minLength={MIN_PASSWORD_LENGTH}
                    className="h-10"
                  />
                </div>
                <div className="space-y-1.5">
                  <label
                    htmlFor="confirm-password"
                    className="text-[12px] font-medium text-muted-foreground"
                  >
                    Confirm password
                  </label>
                  <Input
                    id="confirm-password"
                    type="password"
                    autoComplete="new-password"
                    placeholder="••••••••"
                    value={confirm}
                    onChange={(e) => setConfirm(e.target.value)}
                    required
                    minLength={MIN_PASSWORD_LENGTH}
                    className="h-10"
                  />
                </div>
                <Button type="submit" disabled={submitting} className="h-10 w-full">
                  {submitting ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Updating password…
                    </>
                  ) : (
                    <>
                      <Lock className="mr-2 h-4 w-4" />
                      Update password
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
