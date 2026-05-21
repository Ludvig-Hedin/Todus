import { Navigation } from '@/components/navigation';
import Footer from '@/components/home/footer';
import { cn } from '@/lib/utils';
import type { MetaFunction } from 'react-router';
import { useState, useRef } from 'react';

export const meta: MetaFunction = () => [
  { title: 'Contact Us — Todus' },
  {
    name: 'description',
    content: 'Get in touch with the Todus team. We\'d love to hear from you.',
  },
  { tagName: 'link', rel: 'canonical', href: 'https://todus.app/contact' },
];

function FloatingInput({
  id,
  label,
  type = 'text',
  value,
  onChange,
  placeholder,
  required = false,
  autoComplete,
}: {
  id: string;
  label: string;
  type?: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  required?: boolean;
  autoComplete?: string;
}) {
  const [focused, setFocused] = useState(false);
  const showLabel = value.length > 0;

  return (
    <div className="relative">
      <input
        id={id}
        type={type}
        value={value}
        autoComplete={autoComplete}
        onChange={(e) => onChange(e.target.value)}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        placeholder={placeholder}
        required={required}
        className={cn(
          'w-full rounded-lg border bg-white px-3.5 py-2.5 text-sm text-gray-900 outline-none transition-colors duration-150 placeholder:text-gray-400',
          focused ? 'border-gray-400' : 'border-gray-200 hover:border-gray-300',
        )}
      />
      <span
        aria-hidden="true"
        className={cn(
          'pointer-events-none absolute left-3 bg-white px-0.5 text-[10px] leading-none text-gray-400 transition-all duration-150',
          showLabel ? '-top-[5px] opacity-100' : 'top-1/2 -translate-y-1/2 opacity-0',
        )}
      >
        {label}
      </span>
    </div>
  );
}

function FloatingTextarea({
  id,
  label,
  value,
  onChange,
  placeholder,
  required = false,
  rows = 5,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  required?: boolean;
  rows?: number;
}) {
  const [focused, setFocused] = useState(false);
  const showLabel = value.length > 0;

  return (
    <div className="relative">
      <textarea
        id={id}
        value={value}
        rows={rows}
        onChange={(e) => onChange(e.target.value)}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        placeholder={placeholder}
        required={required}
        className={cn(
          'w-full resize-none rounded-lg border bg-white px-3.5 py-2.5 text-sm text-gray-900 outline-none transition-colors duration-150 placeholder:text-gray-400',
          focused ? 'border-gray-400' : 'border-gray-200 hover:border-gray-300',
        )}
      />
      <span
        aria-hidden="true"
        className={cn(
          'pointer-events-none absolute left-3 bg-white px-0.5 text-[10px] leading-none text-gray-400 transition-all duration-150',
          showLabel ? '-top-[5px] opacity-100' : 'top-4 opacity-0',
        )}
      >
        {label}
      </span>
    </div>
  );
}

export default function ContactPage() {
  const loadTimeRef = useRef(Date.now());

  const [form, setForm] = useState({
    firstName: '',
    lastName: '',
    email: '',
    phone: '',
    message: '',
  });
  const [honeypot, setHoneypot] = useState('');
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState('');

  const set = (field: keyof typeof form) => (v: string) =>
    setForm((prev) => ({ ...prev, [field]: v }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus('loading');
    setErrorMsg('');

    try {
      const res = await fetch(
        `${import.meta.env.VITE_PUBLIC_BACKEND_URL}/api/trpc/contact.submit`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            json: {
              firstName: form.firstName,
              lastName: form.lastName,
              email: form.email,
              phone: form.phone || undefined,
              message: form.message,
              honeypot,
              loadTime: loadTimeRef.current,
            },
          }),
        },
      );

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        const msg =
          (data as { error?: { json?: { message?: string } } })?.error?.json?.message ||
          'Something went wrong. Please try again.';
        setErrorMsg(msg);
        setStatus('error');
        return;
      }

      setStatus('success');
    } catch {
      setErrorMsg('Network error. Please check your connection and try again.');
      setStatus('error');
    }
  };

  return (
    <div className="relative flex min-h-screen w-full flex-col overflow-auto bg-white">
      <Navigation />

      <div className="relative z-10 flex grow flex-col items-center justify-center px-4 py-20">
        <div className="w-full max-w-[480px]">
          {status === 'success' ? (
            <div className="text-center">
              <div className="mb-4 inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100">
                <svg
                  className="h-5 w-5 text-gray-700"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth={2}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <h2 className="text-lg font-semibold text-gray-900">Message sent</h2>
              <p className="mt-1.5 text-sm text-gray-500">
                We'll get back to you at {form.email}.
              </p>
            </div>
          ) : (
            <>
              <h1 className="mb-1.5 text-2xl font-semibold tracking-tight text-gray-900">
                Get in touch
              </h1>
              <p className="mb-8 text-sm text-gray-500">
                We usually respond within a few hours.
              </p>

              <form onSubmit={handleSubmit} className="flex flex-col gap-3" noValidate>
                {/* Honeypot — hidden from real users, bots fill it */}
                <input
                  type="text"
                  name="_trap"
                  value={honeypot}
                  onChange={(e) => setHoneypot(e.target.value)}
                  tabIndex={-1}
                  autoComplete="off"
                  aria-hidden="true"
                  className="absolute -left-[9999px] h-0 w-0 opacity-0"
                />

                <div className="grid grid-cols-2 gap-3">
                  <FloatingInput
                    id="firstName"
                    label="First name"
                    value={form.firstName}
                    onChange={set('firstName')}
                    placeholder="First name"
                    required
                    autoComplete="given-name"
                  />
                  <FloatingInput
                    id="lastName"
                    label="Last name"
                    value={form.lastName}
                    onChange={set('lastName')}
                    placeholder="Last name"
                    required
                    autoComplete="family-name"
                  />
                </div>

                <FloatingInput
                  id="email"
                  label="Email address"
                  type="email"
                  value={form.email}
                  onChange={set('email')}
                  placeholder="Email address"
                  required
                  autoComplete="email"
                />

                <FloatingInput
                  id="phone"
                  label="Phone (optional)"
                  type="tel"
                  value={form.phone}
                  onChange={set('phone')}
                  placeholder="Phone (optional)"
                  autoComplete="tel"
                />

                <FloatingTextarea
                  id="message"
                  label="Message"
                  value={form.message}
                  onChange={set('message')}
                  placeholder="Tell us about your inquiry"
                  required
                  rows={5}
                />

                {status === 'error' && (
                  <p className="text-xs text-red-500">{errorMsg}</p>
                )}

                <button
                  type="submit"
                  disabled={status === 'loading'}
                  className="mt-1 w-full rounded-lg bg-gray-900 py-2.5 text-sm font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
                >
                  {status === 'loading' ? 'Sending…' : 'Send message'}
                </button>
              </form>
            </>
          )}
        </div>
      </div>

      <Footer />
    </div>
  );
}
