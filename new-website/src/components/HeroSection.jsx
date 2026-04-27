import { useReducedMotion } from '../hooks/useAnimation';
import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import React from 'react';

export function HeroSection() {
  const reduced = useReducedMotion();
  const fadeUp = reduced ? {} : { initial: { opacity: 0, y: 28 }, animate: { opacity: 1, y: 0 } };

  return (
    <section className="relative overflow-hidden pb-20 pt-32 md:pb-28 md:pt-44 lg:pb-36">
      <div className="absolute inset-0 -z-10">
        <div
          className="absolute left-1/2 top-0 h-[700px] w-[1400px] -translate-x-1/2 -translate-y-1/3 rounded-full opacity-[0.07] blur-[140px]"
          style={{ background: 'var(--accent)' }}
        />
        <div
          className="absolute bottom-0 right-0 h-[500px] w-[800px] translate-x-1/3 translate-y-1/3 rounded-full opacity-[0.04] blur-[120px]"
          style={{ background: 'var(--accent-soft)' }}
        />
      </div>

      <div className="container-tight flex flex-col items-center text-center">
        <motion.div
          {...fadeUp}
          transition={{ duration: 0.6, delay: 0.1 }}
          className="mb-5 inline-flex items-center gap-2 rounded-full border px-4 py-1.5 text-xs font-medium"
          style={{
            borderColor: 'var(--border)',
            background: 'var(--background-secondary)',
            color: 'var(--foreground-muted)',
          }}
        >
          <span className="relative flex h-2 w-2">
            <span
              className="absolute inline-flex h-full w-full animate-ping rounded-full opacity-75"
              style={{ background: 'var(--accent)' }}
            />
            <span
              className="relative inline-flex h-2 w-2 rounded-full"
              style={{ background: 'var(--accent)' }}
            />
          </span>
          Now available on iOS and Mac
        </motion.div>

        <motion.h1
          {...fadeUp}
          transition={{ duration: 0.6, delay: 0.2 }}
          className="max-w-3xl text-4xl font-semibold tracking-tight md:text-6xl lg:text-7xl"
          style={{ color: 'var(--foreground)' }}
        >
          Your entire day, finally in one place
        </motion.h1>

        <motion.p
          {...fadeUp}
          transition={{ duration: 0.6, delay: 0.3 }}
          className="mt-6 max-w-lg text-base md:text-lg"
          style={{ color: 'var(--foreground-muted)' }}
        >
          All your email, calendar, tasks, notes, and AI assistant in a single app. Minimal,
          powerful, and fast everywhere.
        </motion.p>

        <motion.div
          {...fadeUp}
          transition={{ duration: 0.6, delay: 0.4 }}
          className="mt-8 flex flex-wrap items-center justify-center gap-3"
        >
          <Link to="/download">
            <span className="btn-primary">Get Todus</span>
          </Link>
          <a href="#features">
            <span className="btn-secondary">See how it works</span>
          </a>
        </motion.div>

        <motion.div
          {...fadeUp}
          transition={{ duration: 0.7, delay: 0.5 }}
          className="mt-16 w-full max-w-5xl"
        >
          <AppScreenshotHero />
        </motion.div>
      </div>
    </section>
  );
}

function AppScreenshotHero() {
  return (
    <div className="relative mx-auto w-full max-w-4xl">
      <div
        className="relative overflow-hidden rounded-2xl border shadow-2xl"
        style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}
      >
        <div
          className="flex items-center gap-2 border-b px-4 py-3"
          style={{ borderColor: 'var(--border)' }}
        >
          <div className="flex gap-1.5">
            <div className="h-3 w-3 rounded-full" style={{ background: '#FF5F57' }} />
            <div className="h-3 w-3 rounded-full" style={{ background: '#FEBC2E' }} />
            <div className="h-3 w-3 rounded-full" style={{ background: '#28C840' }} />
          </div>
          <div
            className="ml-4 flex-1 rounded-md px-3 py-1 text-center text-xs"
            style={{ background: 'var(--background-secondary)', color: 'var(--foreground-muted)' }}
          >
            todus.app
          </div>
        </div>
        <div
          className="relative aspect-[16/10] w-full overflow-hidden"
          style={{ background: 'var(--background-secondary)' }}
        >
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="text-center">
              <div className="mb-4 flex items-center justify-center gap-3">
                <div
                  className="flex h-16 w-16 items-center justify-center rounded-2xl"
                  style={{ background: 'var(--accent)' }}
                >
                  <span className="text-2xl font-bold text-white">T</span>
                </div>
              </div>
              <p className="text-sm" style={{ color: 'var(--foreground-muted)' }}>
                App preview placeholder
              </p>
              <p className="mt-1 text-xs opacity-50" style={{ color: 'var(--foreground-muted)' }}>
                TODO: Replace with real screenshot of unified inbox
              </p>
            </div>
          </div>
          <div
            className="absolute inset-x-8 top-1/2 h-px -translate-y-1/2"
            style={{
              background: 'linear-gradient(90deg, transparent, var(--border), transparent)',
            }}
          />
          <div
            className="absolute inset-y-8 left-1/2 w-px -translate-x-1/2"
            style={{
              background: 'linear-gradient(180deg, transparent, var(--border), transparent)',
            }}
          />
        </div>
      </div>
      <div
        className="pointer-events-none absolute -bottom-12 left-1/2 h-24 w-[80%] -translate-x-1/2 rounded-full opacity-40 blur-2xl"
        style={{ background: 'var(--accent)' }}
      />
    </div>
  );
}
