import { Form, FormControl, FormField, FormItem, FormLabel } from '@/components/ui/form';
import { GoogleColor as Google } from '@/components/icons/icons';
import { zodResolver } from '@hookform/resolvers/zod';
import { signIn } from '@/lib/auth-client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useForm } from 'react-hook-form';
import { Link } from 'react-router';
import { toast } from 'sonner';
import { z } from 'zod';

const formSchema = z.object({
  email: z.string().email({ message: 'Please enter a valid email address' }),
  password: z.string().min(6, { message: 'Password must be at least 6 characters' }),
});

export default function LoginTodus() {
  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema) as any,
    defaultValues: {
      email: '',
      password: '',
    },
  });

  function onSubmit(values: z.infer<typeof formSchema>) {
    toast.promise(
      signIn.email({
        email: values.email,
        password: values.password,
        callbackURL: '/mail/inbox',
      }),
      {
        loading: 'Signing in...',
        success: 'Signed in successfully',
        error: (err) => err?.message || 'Sign-in failed. Email/password login may not be enabled.',
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
    <div className="flex h-full min-h-screen w-full items-center justify-center bg-black">
      <div className="animate-in slide-in-from-bottom-4 w-full max-w-md px-6 py-8 duration-500">
        <div className="mb-8 text-center flex flex-col items-center">
          <img
            src="/brand-logo.png"
            alt="Todus Logo"
            className="h-16 w-16 mb-4"
          />
          <h1 className="mb-2 text-4xl font-bold text-white">Welcome to Todus</h1>
          <p className="text-muted-foreground">
            Your AI agent for emails
          </p>
        </div>

        {/* Google OAuth — primary working auth method */}
        <Button
          onClick={handleGoogleSignIn}
          className="bg-white text-black hover:bg-white/90 mb-6 h-12 w-full rounded-full border-0 font-medium"
        >
          <Google className="mr-2 h-5 w-5" />
          Continue with Google
        </Button>

        <div className="relative mb-4">
          <div className="absolute inset-0 flex items-center">
            <span className="w-full border-t border-gray-700" />
          </div>
          <div className="relative flex justify-center text-xs uppercase">
            <span className="bg-black px-2 text-gray-500">or</span>
          </div>
        </div>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-3">
            <FormField
              control={form.control}
              name="email"
              render={({ field }) => (
                <FormItem>
                  <FormLabel className="text-muted-foreground">Email</FormLabel>
                  <FormControl>
                    <Input
                      placeholder="email@example.com"
                      {...field}
                      className="bg-black text-sm text-white placeholder:text-sm rounded-full"
                    />
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
                    <FormLabel className="text-muted-foreground">Password</FormLabel>
                    <Link
                      to="/forgot-password"
                      className="text-muted-foreground text-xs hover:text-white"
                    >
                      Forgot your password?
                    </Link>
                  </div>
                  <FormControl>
                    <Input
                      type="password"
                      placeholder="••••••••"
                      {...field}
                      className="bg-black text-white rounded-full"
                    />
                  </FormControl>
                </FormItem>
              )}
            />

            <Button type="submit" className="w-full rounded-full h-12">
              Login
            </Button>

            <div className="mt-6 text-center text-sm">
              <p className="text-muted-foreground">
                Don't have an account?{' '}
                <a href="/signup" className="text-white underline hover:text-white/80">
                  Sign up
                </a>
              </p>
            </div>
          </form>
        </Form>
      </div>

      <footer className="absolute bottom-0 w-full px-6 py-4">
        <div className="mx-auto flex max-w-6xl items-center justify-center gap-6">
          <a
            href="/terms"
            className="text-[10px] text-gray-500 transition-colors hover:text-gray-300"
          >
            Terms of Service
          </a>
          <a
            href="/privacy"
            className="text-[10px] text-gray-500 transition-colors hover:text-gray-300"
          >
            Privacy Policy
          </a>
        </div>
      </footer>
    </div>
  );
}
