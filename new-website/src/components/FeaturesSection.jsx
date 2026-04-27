import { useInView, useReducedMotion } from '../hooks/useAnimation';
import { RxChevronRight } from 'react-icons/rx';
import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import React from 'react';

const features = [
  {
    title: 'Unified workspace',
    description:
      'Email, calendar, tasks, notes, and AI assistant live together without the noise. No tab switching, no lost context.',
    icon: (
      <svg
        width="24"
        height="24"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
      >
        <rect x="3" y="3" width="7" height="7" rx="1.5" />
        <rect x="14" y="3" width="7" height="7" rx="1.5" />
        <rect x="3" y="14" width="7" height="7" rx="1.5" />
        <rect x="14" y="14" width="7" height="7" rx="1.5" />
      </svg>
    ),
  },
  {
    title: 'Stop context switching',
    description:
      'Reclaim the 20 minutes lost to refocusing every time you switch apps. One context, all day.',
    icon: (
      <svg
        width="24"
        height="24"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
      >
        <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
      </svg>
    ),
  },
  {
    title: 'Native everywhere',
    description:
      'Instant on iOS and Mac. Full power on the web. Same experience, any device, zero compromises.',
    icon: (
      <svg
        width="24"
        height="24"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
      >
        <rect x="5" y="2" width="14" height="20" rx="2" />
        <line x1="12" y1="18" x2="12" y2="18.01" />
      </svg>
    ),
  },
];

export function FeaturesSection() {
  const { ref, inView } = useInView();
  const reduced = useReducedMotion();

  return (
    <section id="features" className="section-spacing" ref={ref}>
      <div className="container-tight">
        <div className="mx-auto mb-16 max-w-lg text-center md:mb-20">
          <motion.p
            initial={reduced ? {} : { opacity: 0, y: 16 }}
            animate={inView ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: 0.5 }}
            className="mb-3 text-xs font-semibold uppercase tracking-widest"
            style={{ color: 'var(--accent)' }}
          >
            Built different
          </motion.p>
          <motion.h2
            initial={reduced ? {} : { opacity: 0, y: 16 }}
            animate={inView ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: 0.5, delay: 0.05 }}
            className="text-3xl font-semibold tracking-tight md:text-5xl lg:text-6xl"
            style={{ color: 'var(--foreground)' }}
          >
            Everything you need to stay focused
          </motion.h2>
          <motion.p
            initial={reduced ? {} : { opacity: 0, y: 16 }}
            animate={inView ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: 0.5, delay: 0.1 }}
            className="mt-5 text-base"
            style={{ color: 'var(--foreground-muted)' }}
          >
            No more tabs, no more friction. One app that knows your day.
          </motion.p>
        </div>

        <div className="grid grid-cols-1 gap-6 md:grid-cols-3 md:gap-8">
          {features.map((f, i) => (
            <motion.div
              key={f.title}
              initial={reduced ? {} : { opacity: 0, y: 28 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5, delay: 0.15 + i * 0.1 }}
              className="group relative overflow-hidden rounded-2xl border p-7 transition-all duration-300 md:p-9"
              style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor = 'var(--border-strong)';
                e.currentTarget.style.boxShadow = 'var(--shadow-lg)';
                e.currentTarget.style.transform = 'translateY(-4px)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = 'var(--border)';
                e.currentTarget.style.boxShadow = 'none';
                e.currentTarget.style.transform = 'translateY(0)';
              }}
            >
              <div
                className="absolute -right-8 -top-8 h-32 w-32 rounded-full opacity-0 blur-3xl transition-opacity duration-500 group-hover:opacity-30"
                style={{ background: 'var(--accent)' }}
              />
              <div
                className="mb-5 flex h-11 w-11 items-center justify-center rounded-xl transition-colors duration-300"
                style={{ background: 'var(--background-secondary)', color: 'var(--foreground)' }}
              >
                {f.icon}
              </div>
              <h3 className="text-lg font-semibold" style={{ color: 'var(--foreground)' }}>
                {f.title}
              </h3>
              <p
                className="mt-3 text-sm leading-relaxed"
                style={{ color: 'var(--foreground-muted)' }}
              >
                {f.description}
              </p>
            </motion.div>
          ))}
        </div>

        <motion.div
          initial={reduced ? {} : { opacity: 0 }}
          animate={inView ? { opacity: 1 } : {}}
          transition={{ duration: 0.5, delay: 0.5 }}
          className="mt-14 flex items-center justify-center gap-5"
        >
          <a href="/pricing#compare">
            <span className="btn-secondary text-sm">Explore features</span>
          </a>
          <Link
            to="/pricing"
            className="inline-flex items-center gap-1 text-sm font-medium transition-colors hover:text-[var(--foreground)]"
            style={{ color: 'var(--foreground-muted)' }}
          >
            Learn more <RxChevronRight className="h-4 w-4" />
          </Link>
        </motion.div>
      </div>
    </section>
  );
}
