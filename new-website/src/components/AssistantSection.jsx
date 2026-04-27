import { useInView, useReducedMotion } from '../hooks/useAnimation';
import { RxChevronRight } from 'react-icons/rx';
import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import React from 'react';

const steps = [
  { label: 'Email arrives', detail: 'AI reads context instantly' },
  { label: 'Drafts reply', detail: 'Personalized to your tone' },
  { label: 'Creates task', detail: 'Extracted from the message' },
  { label: 'Adds to calendar', detail: 'So nothing is forgotten' },
];

export function AssistantSection() {
  const { ref, inView } = useInView();
  const reduced = useReducedMotion();
  const statusDotClassName = reduced
    ? 'h-2 w-2 rounded-full'
    : 'h-2 w-2 animate-pulse rounded-full';

  return (
    <section className="section-spacing overflow-hidden" ref={ref}>
      <div className="container-tight">
        <div className="grid grid-cols-1 items-center gap-16 lg:grid-cols-2 lg:gap-24">
          <div>
            <motion.p
              initial={reduced ? {} : { opacity: 0, y: 16 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5 }}
              className="mb-3 text-xs font-semibold uppercase tracking-widest"
              style={{ color: 'var(--accent)' }}
            >
              Integrated
            </motion.p>
            <motion.h2
              initial={reduced ? {} : { opacity: 0, y: 16 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5, delay: 0.05 }}
              className="text-3xl font-semibold tracking-tight md:text-4xl lg:text-5xl"
              style={{ color: 'var(--foreground)' }}
            >
              An assistant that actually gets things done
            </motion.h2>
            <motion.p
              initial={reduced ? {} : { opacity: 0, y: 16 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5, delay: 0.1 }}
              className="mt-5 text-base leading-relaxed"
              style={{ color: 'var(--foreground-muted)' }}
            >
              It does not just talk. The AI reads your email, creates tasks, drafts replies, and
              organizes your day using what it knows about you. Everything works together.
            </motion.p>
            <motion.div
              initial={reduced ? {} : { opacity: 0, y: 16 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5, delay: 0.15 }}
              className="mt-8 flex flex-wrap items-center gap-3"
            >
              <Link to="/pricing">
                <span className="btn-secondary text-sm">Learn more</span>
              </Link>
              <Link
                to="/pricing"
                className="inline-flex items-center gap-1 text-sm font-medium transition-colors"
                style={{ color: 'var(--foreground-muted)' }}
                onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--foreground)')}
                onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--foreground-muted)')}
              >
                See pricing <RxChevronRight className="h-4 w-4" />
              </Link>
            </motion.div>
          </div>

          <motion.div
            initial={reduced ? {} : { opacity: 0, x: 50 }}
            animate={inView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.6, delay: 0.2 }}
            className="relative"
          >
            <div
              className="relative overflow-hidden rounded-2xl border p-7 shadow-xl md:p-10"
              style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}
            >
              <div className="mb-8 flex items-center gap-3">
                <div
                  className="flex h-10 w-10 items-center justify-center rounded-xl"
                  style={{ background: 'var(--accent)' }}
                >
                  <svg
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="white"
                    strokeWidth="2"
                    aria-hidden="true"
                  >
                    <path d="M12 2L2 7l10 5 10-5-10-5z" />
                    <path d="M2 17l10 5 10-5" />
                    <path d="M2 12l10 5 10-5" />
                  </svg>
                </div>
                <span className="text-base font-semibold" style={{ color: 'var(--foreground)' }}>
                  AI Assistant
                </span>
              </div>

              <div className="space-y-4">
                {steps.map((step, i) => (
                  <div key={step.label} className="flex items-start gap-4">
                    <div
                      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-bold"
                      style={{
                        background: 'var(--background-secondary)',
                        color: 'var(--foreground)',
                      }}
                    >
                      {i + 1}
                    </div>
                    <div>
                      <p className="text-sm font-medium" style={{ color: 'var(--foreground)' }}>
                        {step.label}
                      </p>
                      <p className="text-xs" style={{ color: 'var(--foreground-muted)' }}>
                        {step.detail}
                      </p>
                    </div>
                  </div>
                ))}
              </div>

              <div
                className="mt-8 flex items-center gap-3 rounded-xl border px-4 py-3"
                style={{ borderColor: 'var(--border)', background: 'var(--background-secondary)' }}
              >
                <div className={statusDotClassName} style={{ background: 'var(--accent)' }} />
                <span className="text-xs font-medium" style={{ color: 'var(--foreground-muted)' }}>
                  AI is processing your inbox...
                </span>
              </div>
            </div>
            <div
              className="pointer-events-none absolute -bottom-8 left-1/2 h-20 w-[70%] -translate-x-1/2 rounded-full opacity-30 blur-2xl"
              style={{ background: 'var(--accent)' }}
            />
          </motion.div>
        </div>
      </div>
    </section>
  );
}
