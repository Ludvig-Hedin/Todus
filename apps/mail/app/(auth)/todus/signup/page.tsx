import { Form, FormControl, FormField, FormItem, FormLabel } from '@/components/ui/form';
import { Google } from '@/components/icons/icons';
import { zodResolver } from '@hookform/resolvers/zod';
import { signIn, signUp } from '@/lib/auth-client';
import { Button } from '@/components/ui/button';
import { APP_NAME } from '@/lib/branding';
import { Input } from '@/components/ui/input';
import { useForm } from 'react-hook-form';
import { toast } from 'sonner';
import { z } from 'zod';

const formSchema = z.object({
  name: z.string().min(1, { message: 'Name must be at least 1 character' }),
  email: z.string().min(1, { message: 'Username must be at least 1 character' }),
  password: z.string().min(6, { message: 'Password must be at least 6 characters' }),
});

export default function SignupTodus() {
  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema as any),
    defaultValues: {
      name: '',
      email: '',
      password: '',
    },
  });

  function onSubmit(values: z.infer<typeof formSchema>) {
    const fullEmail = `${values.email}@todus.app`;

    toast.promise(
      signUp.email({
        name: values.name,
        email: fullEmail,
        password: values.password,
        callbackURL: '/mail/inbox',
      }),
      {
        loading: 'Creating account...',
        success: 'Account created successfully',
        error: (err) =>
          err?.message || 'Sign-up failed. Email/password registration may not be enabled.',
      },
    );
  }

  function handleGoogleSignIn() {
    toast.promise(
      signIn.social({
        provider: 'google',
        callbackURL: `${window.location.origin}/mail/inbox`,
      }),
      {
        error: 'Login redirect failed',
      },
    );
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

          {false && (
            <>
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
                          <Input
                            placeholder="Luke"
                            {...field}
                          />
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
                          <Input
                            type="password"
                            placeholder="••••••••"
                            {...field}
                          />
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
                      <a href="/login" className="font-medium underline underline-offset-4 hover:text-foreground">
                        Login
                      </a>
                    </p>
                  </div>
                </form>
              </Form>
            </>
          )}
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
