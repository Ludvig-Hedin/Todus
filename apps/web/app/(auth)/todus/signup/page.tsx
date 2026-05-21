import { Google } from '@/components/icons/icons';
import { TodusLogo } from '@/components/ui/todus-logo';
import { Button } from '@/components/ui/button';
import { signIn } from '@/lib/auth-client';
import { authProxy } from '@/lib/auth-proxy';
import { Loader2 } from 'lucide-react';
import { useState } from 'react';
import { redirect } from 'react-router';
import { toast } from 'sonner';
import type { Route } from './+types/page';

// Block signed-in users from re-running OAuth on /signup.
// Without this guard, a logged-in user picking a different Google account here
// would be silently linked onto the existing user row → cross-account leak.
// Skip the round-trip on cookieless requests + race against a 3s timeout so
// a slow backend never blocks the signup page from rendering.
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

export default function SignupTodus() {
  const [isRedirecting, setIsRedirecting] = useState(false);

  async function handleGoogleSignIn() {
    if (isRedirecting) return;
    setIsRedirecting(true);
    try {
      await signIn.social({
        provider: 'google',
        callbackURL: `${window.location.origin}/mail/inbox`,
      });
    } catch (error) {
      console.error('Google sign-in failed:', error);
      toast.error('Could not start Google sign-in. Please try again.');
      setIsRedirecting(false);
    }
  }

  return (
    <div className="flex min-h-screen w-full bg-background">
      {/* Left Column - Form */}
      <div className="flex w-full flex-col p-8 md:p-12 xl:p-16">
        <div className="mb-auto">
          <TodusLogo height={28} className="text-foreground" />
        </div>

        <div className="mx-auto flex w-full max-w-sm flex-col justify-center my-auto animate-in slide-in-from-bottom-4 duration-500">
          <div className="mb-8 flex flex-col items-start text-left">
            <h1 className="text-2xl font-semibold tracking-tight">Sign up for Todus</h1>
            <p className="text-2xl font-semibold tracking-tight text-muted-foreground mb-4">
              Your AI agent for emails
            </p>
            <p className="text-sm text-muted-foreground">
              Continue with your Google account to get started.
            </p>
          </div>

          {/* Google OAuth — primary working auth method */}
          <Button
            type="button"
            variant="outline"
            onClick={handleGoogleSignIn}
            disabled={isRedirecting}
            className="mb-6 w-full"
          >
            {isRedirecting ? (
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
              <form onSubmit={form.handleSubmit(onSubmit)} className="mx-auto space-y-4">
                <FormField
                  control={form.control}
                  name="name"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Name</FormLabel>
                      <FormControl>
                        <Input placeholder="Luke" {...field} />
                      </FormControl>
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="email"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Email</FormLabel>
                      <FormControl>
                        <div className="relative w-full rounded-md">
                          <Input
                            placeholder="adam"
                            {...field}
                            className="w-full pr-20"
                          />
                          <span className="bg-popover text-muted-foreground border-input absolute bottom-0 right-0 top-0 flex items-center rounded-r-md border border-l-0 px-3 py-2 text-sm">
                            @todus.app
                          </span>
                        </div>
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
                      </div>
                      <FormControl>
                        <Input type="password" placeholder="••••••••" {...field} />
                      </FormControl>
                    </FormItem>
                  )}
                />

                <Button type="submit" className="w-full">
                  Signup
                </Button>

                <div className="mt-6 text-center text-sm">
                  <p className="text-muted-foreground">
                    Already have an account?{' '}
                    <a
                      href="/login"
                      className="font-medium underline underline-offset-4 hover:text-foreground"
                    >
                      Login
                    </a>
                  </p>
                </div>
              </form>
            </Form>
          */}
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
      <div className="hidden w-1/2 p-4 xl:p-6">
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
