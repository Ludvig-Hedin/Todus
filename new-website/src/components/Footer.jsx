import { useTheme } from '../context/ThemeContext';
import { Link } from 'react-router-dom';
import React from 'react';

const footerLinks = [
  {
    title: 'Product',
    links: [
      { label: 'Features', href: '/#features' },
      { label: 'Pricing', href: '/pricing' },
      { label: 'Download', href: '/download' },
      { label: 'Blog', href: '/blog' },
    ],
  },
  {
    title: 'Company',
    links: [
      { label: 'Contact', href: '/contact' },
      { label: 'Careers', href: '/careers' },
      { label: 'Press', href: '/press' },
      { label: 'Legal', href: '/legal' },
    ],
  },
];

export function Footer() {
  const { theme, setTheme } = useTheme();

  return (
    <footer style={{ borderTop: '1px solid var(--border)', background: 'var(--background)' }}>
      <div className="container-tight py-14 md:py-20">
        <div className="grid grid-cols-1 gap-12 md:grid-cols-[1.5fr_1fr_1fr]">
          <div>
            <Link to="/" className="flex items-center gap-2">
              <div
                className="flex h-8 w-8 items-center justify-center rounded-lg"
                style={{ background: 'var(--foreground)' }}
              >
                <span className="text-xs font-bold" style={{ color: 'var(--background)' }}>
                  T
                </span>
              </div>
              <span
                className="text-base font-semibold tracking-tight"
                style={{ color: 'var(--foreground)' }}
              >
                Todus
              </span>
            </Link>
            <p
              className="mt-5 max-w-xs text-sm leading-relaxed"
              style={{ color: 'var(--foreground-muted)' }}
            >
              Your entire day, finally in one place. Email, calendar, tasks, notes, and AI.
            </p>
            <div className="mt-5">
              <a
                href="mailto:hello@todus.app"
                className="text-sm transition-colors"
                style={{ color: 'var(--foreground-muted)' }}
                onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--foreground)')}
                onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--foreground-muted)')}
              >
                hello@todus.app
              </a>
            </div>
          </div>

          {footerLinks.map((group) => (
            <div key={group.title}>
              <h4
                className="text-xs font-semibold uppercase tracking-widest"
                style={{ color: 'var(--foreground-muted)' }}
              >
                {group.title}
              </h4>
              <ul className="mt-5 space-y-3">
                {group.links.map((link) => (
                  <li key={link.label}>
                    <Link
                      to={link.href}
                      className="text-sm transition-colors"
                      style={{ color: 'var(--foreground-muted)' }}
                      onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--foreground)')}
                      onMouseLeave={(e) =>
                        (e.currentTarget.style.color = 'var(--foreground-muted)')
                      }
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div
          className="mt-14 flex flex-col items-start justify-between gap-6 border-t pt-8 md:flex-row md:items-center"
          style={{ borderColor: 'var(--border)' }}
        >
          <div className="flex flex-wrap items-center gap-5">
            <span className="text-xs" style={{ color: 'var(--foreground-muted)' }}>
              &copy; {new Date().getFullYear()} Todus
            </span>
            <Link
              to="/privacy"
              className="text-xs transition-colors"
              style={{ color: 'var(--foreground-muted)' }}
              onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--foreground)')}
              onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--foreground-muted)')}
            >
              Privacy
            </Link>
            <Link
              to="/terms"
              className="text-xs transition-colors"
              style={{ color: 'var(--foreground-muted)' }}
              onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--foreground)')}
              onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--foreground-muted)')}
            >
              Terms
            </Link>
          </div>

          <div
            role="group"
            aria-label="Theme selector"
            className="flex items-center gap-1 rounded-lg border p-1"
            style={{ borderColor: 'var(--border)', background: 'var(--background-secondary)' }}
          >
            {['light', 'dark', 'system'].map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTheme(t)}
                aria-label={`Set theme to ${t}`}
                aria-pressed={theme === t}
                className="rounded-md px-3 py-1.5 text-xs font-medium transition-colors"
                style={
                  theme === t
                    ? {
                        background: 'var(--surface)',
                        color: 'var(--foreground)',
                        boxShadow: 'var(--shadow-sm)',
                      }
                    : { color: 'var(--foreground-muted)' }
                }
              >
                {t.charAt(0).toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
        </div>
      </div>
    </footer>
  );
}
