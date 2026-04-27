import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useInView, useReducedMotion } from '../hooks/useAnimation';
import { RxChevronDown } from 'react-icons/rx';
import { Link } from 'react-router-dom';

const faqs = [
  { q: 'Is my data private?', a: 'Yes. We do not sell your data. Authentication is privacy-first — sign in with Google, Apple, or email. All data is encrypted in transit and at rest.' },
  { q: 'What devices are supported?', a: 'iOS, Mac, and web. The apps are native on mobile and Mac for speed. The web app has full feature parity — no lite version.' },
  { q: 'Can I import my email?', a: 'Yes. Connect your Gmail account and Todus pulls in your messages, calendar, and contacts. Other email providers coming soon.' },
  { q: 'Is there a free trial?', a: 'Yes. Start free with no credit card. Upgrade anytime if you want advanced features.' },
  { q: 'How does the AI work?', a: 'It reads your email, calendar, and tasks to understand your day. Then it creates tasks from messages, drafts replies, and suggests what to prioritize.' },
];

export function FAQSection() {
  const { ref, inView } = useInView();
  const reduced = useReducedMotion();

  return (
    <section className="section-spacing" ref={ref}>
      <div className="container-tight" style={{ maxWidth: '800px' }}>
        <motion.div initial={reduced ? {} : { opacity: 0, y: 16 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.5 }} className="mb-12">
          <h2 className="text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: 'var(--foreground)' }}>FAQ</h2>
          <p className="mt-4 text-base" style={{ color: 'var(--foreground-muted)' }}>Common questions about Todus</p>
        </motion.div>

        <div className="space-y-4">
          {faqs.map((faq, i) => (
            <motion.div key={faq.q} initial={reduced ? {} : { opacity: 0, y: 16 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.4, delay: 0.05 + i * 0.05 }}>
              <FAQItem question={faq.q} answer={faq.a} />
            </motion.div>
          ))}
        </div>

        <motion.div initial={reduced ? {} : { opacity: 0, y: 16 }} animate={inView ? { opacity: 1, y: 0 } : {}} transition={{ duration: 0.5, delay: 0.4 }} className="mt-16 overflow-hidden rounded-2xl border p-8 md:p-10" style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}>
          <h3 className="text-xl font-semibold" style={{ color: 'var(--foreground)' }}>Still have questions?</h3>
          <p className="mt-3 text-sm" style={{ color: 'var(--foreground-muted)' }}>Reach out anytime and we will get back to you.</p>
          <div className="mt-6">
            <Link to="/contact"><span className="btn-secondary text-sm">Contact us</span></Link>
          </div>
        </motion.div>
      </div>
    </section>
  );
}

function FAQItem({ question, answer }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="overflow-hidden rounded-xl border transition-colors" style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}>
      <button onClick={() => setOpen((p) => !p)} className="flex w-full items-center justify-between px-6 py-5 text-left md:px-8">
        <span className="pr-4 text-sm font-medium" style={{ color: 'var(--foreground)' }}>{question}</span>
        <motion.div animate={{ rotate: open ? 180 : 0 }} transition={{ duration: 0.2 }} className="shrink-0" style={{ color: 'var(--foreground-muted)' }}>
          <RxChevronDown className="h-4 w-4" />
        </motion.div>
      </button>
      <AnimatePresence initial={false}>
        {open && (
          <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: 'auto', opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={{ duration: 0.25 }}>
            <div className="px-6 pb-5 pt-0 text-sm leading-relaxed md:px-8" style={{ color: 'var(--foreground-muted)' }}>
              {answer}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
