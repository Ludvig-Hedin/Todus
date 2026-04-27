import React from 'react';
import { motion } from 'framer-motion';
import { useInView, useReducedMotion } from '../hooks/useAnimation';
import { Link } from 'react-router-dom';

export function CTASection() {
  const { ref, inView } = useInView();
  const reduced = useReducedMotion();

  return (
    <section className="relative overflow-hidden py-24 md:py-32 lg:py-40" ref={ref}>
      <div className="absolute inset-0 -z-10">
        <div className="absolute bottom-0 left-1/2 h-[600px] w-[1200px] -translate-x-1/2 translate-y-1/3 rounded-full opacity-[0.08] blur-[140px]" style={{ background: 'var(--accent)' }} />
      </div>

      <div className="container-tight flex flex-col items-center text-center">
        <motion.h2 initial={reduced ? {} : { opacity: 0, y: 24 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.6 }} className="max-w-2xl text-4xl font-semibold tracking-tight md:text-5xl lg:text-6xl" style={{ color: 'var(--foreground)' }}>
          Ready to focus?
        </motion.h2>
        <motion.p initial={reduced ? {} : { opacity: 0, y: 24 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.6, delay: 0.1 }} className="mt-6 max-w-md text-base" style={{ color: 'var(--foreground-muted)' }}>
          Start free, no credit card required.
        </motion.p>
        <motion.div initial={reduced ? {} : { opacity: 0, y: 24 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.6, delay: 0.2 }} className="mt-10 flex flex-wrap items-center justify-center gap-3">
          <Link to="/download"><span className="btn-primary">Get started</span></Link>
          <Link to="/pricing"><span className="btn-secondary">See pricing</span></Link>
        </motion.div>
      </div>
    </section>
  );
}
