import { Google } from '@/components/icons/icons';
import { signIn } from '@/lib/auth-client';
import { Button } from '@/components/ui/button';

export default function SignupTodus() {
  function handleGoogleSignIn() {
    signIn.social({
        provider: 'google',
        callbackURL: `${window.location.origin}/mail/inbox`,
      });
  }

  return (
    <div className="flex min-h-screen w-full bg-background">
      {/* Left Column - Form */}
      <div className="flex w-full flex-col lg:w-1/2 p-8 md:p-12 xl:p-16">
        <div className="flex items-center gap-2 mb-auto">
          <img
            src="/brand-logo.png"
            alt="Todus Logo"
            className="h-8 w-8"
          />
          <span className="font-semibold tracking-tight">Todus</span>
        </div>

        <div className="mx-auto flex w-full max-w-sm flex-col justify-center my-auto animate-in slide-in-from-bottom-4 duration-500">
          <div className="mb-8 flex flex-col items-start text-left">
            <h1 className="text-2xl font-semibold tracking-tight">Signup to Todus</h1>
            <p className="text-2xl font-semibold tracking-tight text-muted-foreground mb-4">
              Your AI agent for emails
            </p>
            <p className="text-sm text-muted-foreground">
              Sign up for free with your email
            </p>
          </div>

          {/* Google OAuth — primary working auth method */}
          <Button
            type="button"
            variant="outline"
            onClick={handleGoogleSignIn}
            className="mb-6 w-full"
          >
            <Google className="mr-2 h-4 w-4" />
            Continue with Google
          </Button>
        </div>

        <footer className="mt-auto">
          <div className="flex items-center gap-6">
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
      <div className="hidden lg:flex w-1/2 p-4 xl:p-6">
        <div className="relative flex h-full w-full items-center justify-center overflow-hidden rounded-[2.5rem] bg-[#0F0F0F] border border-[#2A2A2A]">
          <div className="relative w-full h-full">
            <img
              src="/email-preview.png"
              alt="Todus Interface"
              className="rounded-xl border border-[#252525] shadow-[0_0_50px_-12px_rgba(0,0,0,0.5)] object-cover w-full h-full"
              style={{ objectPosition: 'left center', transformOrigin: 'center left' }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
