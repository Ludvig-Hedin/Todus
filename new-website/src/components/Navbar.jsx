import { AnimatePresence, motion } from 'framer-motion';
import { Link, useLocation } from 'react-router-dom';
import React, { useState, useEffect } from 'react';
import { RxChevronDown } from 'react-icons/rx';

const navLinks = [
  { label: 'Features', href: '/#features' },
  { label: 'Pricing', href: '/pricing' },
  { label: 'Download', href: '/download' },
];

const moreLinks = [
  { label: 'Blog', href: '/blog' },
  { label: 'Contact', href: '/contact' },
  { label: 'Legal', href: '/legal' },
];

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const location = useLocation();
  const headerClass = `fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
    scrolled ? 'backdrop-blur-xl' : ''
  }`;
  const headerStyle = {
    background: scrolled ? 'rgba(var(--background-rgb), 0.8)' : 'transparent',
    borderBottom: scrolled ? '1px solid var(--border)' : '1px solid transparent',
  };
  const handleMoreBlur = (event) => {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      setMoreOpen(false);
    }
  };
  const handleMobileLinkEnter = (event) => {
    event.currentTarget.style.background = 'var(--background-secondary)';
    event.currentTarget.style.color = 'var(--foreground)';
  };
  const handleMobileLinkLeave = (event) => {
    event.currentTarget.style.background = 'transparent';
    event.currentTarget.style.color = 'var(--foreground-muted)';
  };

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', onScroll);
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    setMobileOpen(false);
  }, [location]);

  return (
    <header className={headerClass} style={headerStyle}>
      <div className="container-tight flex h-16 items-center justify-between">
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

        <nav className="hidden items-center gap-1 md:flex">
          {navLinks.map((link) => (
            <Link
              key={link.label}
              to={link.href}
              className="rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
              style={{ color: 'var(--foreground-muted)' }}
              onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--foreground)')}
              onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--foreground-muted)')}
            >
              {link.label}
            </Link>
          ))}
          <div
            className="relative"
            onMouseEnter={() => setMoreOpen(true)}
            onMouseLeave={() => setMoreOpen(false)}
            onFocus={() => setMoreOpen(true)}
            onBlur={handleMoreBlur}
          >
            <button
              type="button"
              aria-haspopup="menu"
              aria-expanded={moreOpen}
              className="flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
              style={{ color: 'var(--foreground-muted)' }}
              onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--foreground)')}
              onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--foreground-muted)')}
            >
              More
              <motion.div animate={{ rotate: moreOpen ? 180 : 0 }} transition={{ duration: 0.2 }}>
                <RxChevronDown className="h-3.5 w-3.5" />
              </motion.div>
            </button>
            <AnimatePresence>
              {moreOpen && (
                <motion.div
                  role="menu"
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: 8 }}
                  transition={{ duration: 0.2 }}
                  className="absolute right-0 top-full mt-2 w-48 overflow-hidden rounded-xl border p-2 shadow-xl"
                  style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}
                >
                  {moreLinks.map((link) => (
                    <Link
                      key={link.label}
                      role="menuitem"
                      to={link.href}
                      className="block rounded-lg px-3 py-2 text-sm transition-colors"
                      style={{ color: 'var(--foreground-muted)' }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.background = 'var(--background-secondary)';
                        e.currentTarget.style.color = 'var(--foreground)';
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.background = 'transparent';
                        e.currentTarget.style.color = 'var(--foreground-muted)';
                      }}
                    >
                      {link.label}
                    </Link>
                  ))}
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </nav>

        <div className="flex items-center gap-3">
          <Link to="/download" className="hidden md:inline-flex">
            <span className="btn-primary px-5 py-2 text-xs">Get Todus</span>
          </Link>
          <button
            type="button"
            className="flex h-10 w-10 flex-col items-center justify-center gap-1.5 rounded-lg md:hidden"
            onClick={() => setMobileOpen((p) => !p)}
            aria-label="Toggle navigation menu"
            aria-expanded={mobileOpen}
            aria-controls="mobile-navigation-menu"
          >
            <motion.span
              animate={mobileOpen ? { rotate: 45, y: 5 } : { rotate: 0, y: 0 }}
              className="block h-px w-5"
              style={{ background: 'var(--foreground)' }}
            />
            <motion.span
              animate={mobileOpen ? { opacity: 0 } : { opacity: 1 }}
              className="block h-px w-5"
              style={{ background: 'var(--foreground)' }}
            />
            <motion.span
              animate={mobileOpen ? { rotate: -45, y: -5 } : { rotate: 0, y: 0 }}
              className="block h-px w-5"
              style={{ background: 'var(--foreground)' }}
            />
          </button>
        </div>
      </div>

      <AnimatePresence>
        {mobileOpen && (
          <motion.div
            id="mobile-navigation-menu"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.25 }}
            className="overflow-hidden border-b md:hidden"
            style={{ borderColor: 'var(--border)', background: 'var(--background)' }}
          >
            <div className="container-tight flex flex-col gap-1 py-5">
              {[...navLinks, ...moreLinks].map((link) => (
                <Link
                  key={link.label}
                  to={link.href}
                  className="rounded-lg px-3 py-2.5 text-sm font-medium"
                  style={{ color: 'var(--foreground-muted)' }}
                  onMouseEnter={handleMobileLinkEnter}
                  onMouseLeave={handleMobileLinkLeave}
                >
                  {link.label}
                </Link>
              ))}
              <Link to="/download" className="mt-3">
                <span className="btn-primary w-full py-2.5 text-center text-sm">Get Todus</span>
              </Link>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </header>
  );
}
