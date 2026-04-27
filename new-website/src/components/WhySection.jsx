import React from 'react';
import { motion } from 'framer-motion';
import { useInView, useReducedMotion } from '../hooks/useAnimation';
import { RxChevronRight } from 'react-icons/rx';
import { Link } from 'react-router-dom';

const reasons = [
  {
    title: 'Twenty minutes saved',
    description: 'Average time saved by consolidating email, calendar, and tasks into one flow.',
  },
  {
    title: 'Everything connects',
    description: 'Emails become tasks. Tasks appear on your calendar. Notes attach to projects.',
  },
  {
    title: 'One rhythm everywhere',
    description: 'Same app on phone, Mac, and web. No learning curve, no lite versions.',
  },
];

export function WhySection() {
  const { ref, inView } = useInView();
  const reduced = useReducedMotion();

  return (
    <section className="section-spacing" ref={ref}>
      <div className="container-tight">
        <div className="mb-16 grid grid-cols-1 items-start gap-6 md:mb-20 md:grid-cols-2 md:gap-16 lg:gap-24">
          <motion.div initial={reduced ? {} : { opacity: 0, y: 16 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.5 }}>
            <p className="mb-3 text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--accent)' }}>Why</p>
            <h2 className="text-3xl font-semibold tracking-tight md:text-4xl lg:text-5xl" style={{ color: 'var(--foreground)' }}>
              One app beats five apps every time
            </h2>
          </motion.div>
          <motion.div initial={reduced ? {} : { opacity: 0, y: 16 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.5, delay: 0.05 }} className="flex items-end">
            <p className="text-base leading-relaxed" style={{ color: 'var(--foreground-muted)' }}>
              Most people lose over 20 minutes a day switching between tools. Todus removes that friction so you can focus on what matters.
            </p>
          </motion.div>
        </div>

        <div className="grid grid-cols-1 gap-6 md:grid-cols-3 md:gap-8">
          {reasons.map((r, i) => (
            <motion.div
              key={r.title}
              initial={reduced ? {} : { opacity: 0, y: 28 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5, delay: 0.1 + i * 0.1 }}
              className="group overflow-hidden rounded-2xl border transition-all duration-300"
              style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}
              onMouseEnter={(e) => { e.currentTarget.style.borderColor = 'var(--border-strong)'; e.currentTarget.style.boxShadow = 'var(--shadow-lg)'; e.currentTarget.style.transform = 'translateY(-4px)'; }}
              onMouseLeave={(e) => { e.currentTarget.style.borderColor = 'var(--border)'; e.currentTarget.style.boxShadow = 'none'; e.currentTarget.style.transform = 'translateY(0)'; }}
            >
              <div className="relative aspect-[16/10] w-full overflow-hidden" style={{ background: 'var(--background-secondary)' }}>
                <div className="absolute inset-0 flex items-center justify-center">
                  <div className="text-center">
                    <div className="mb-2 text-4xl font-bold opacity-10" style={{ color: 'var(--accent)' }}>{String(i + 1).padStart(2, '0')}</div>
                    <p className="text-xs" style={{ color: 'var(--foreground-muted)' }}>Preview placeholder</p>
                  </div>
                </div>
                <div className="absolute inset-x-6 top-1/2 h-px -translate-y-1/2 opacity-30" style={{ background: 'linear-gradient(90deg, transparent, var(--border), transparent)' }} />
                <div className="absolute left-1/2 inset-y-6 w-px -translate-x-1/2 opacity-30" style={{ background: 'linear-gradient(180deg, transparent, var(--border), transparent)' }} />
              </div>
              <div className="p-6 md:p-8">
                <h3 className="text-lg font-semibold" style={{ color: 'var(--foreground)' }}>{r.title}</h3>
                <p className="mt-3 text-sm leading-relaxed" style={{ color: 'var(--foreground-muted)' }}>{r.description}</p>
              </div>
            </motion.div>
          ))}
        </div>

        <motion.div initial={reduced ? {} : { opacity: 0 }} animate={inView ? { opacity: 1 } : {}} transition={{ duration: 0.5, delay: 0.5 }} className="mt-14 flex items-center justify-center gap-5">
          <Link to="/download"><span className="btn-secondary text-sm">Explore</span></Link>
          <Link to="/download" className="inline-flex items-center gap-1 text-sm font-medium transition-colors" style={{ color: 'var(--foreground-muted)' }} onMouseEnter={(e) => e.currentTarget.style.color = 'var(--foreground)'} onMouseLeave={(e) => e.currentTarget.style.color = 'var(--foreground-muted)'}>
            Get started <RxChevronRight className="h-4 w-4" />
          </Link>
        </motion.div>
      </div>
    </section>
  );
}
