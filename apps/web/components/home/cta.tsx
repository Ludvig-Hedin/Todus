import { Balancer } from 'react-wrap-balancer';
import { Button } from '../ui/button';
import { motion } from 'motion/react';

export default function CTASection() {
  return (
    <section className="relative z-10 mx-auto flex w-full max-w-7xl flex-col items-center justify-center px-4 pt-32 md:pt-48 pb-24 text-center">
      <motion.h2
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-80px' }}
        transition={{ duration: 0.5 }}
        className="text-4xl font-medium tracking-tight text-white sm:text-5xl md:text-6xl lg:text-7xl"
      >
        <Balancer>Experience the Future of Email Today</Balancer>
      </motion.h2>
      <motion.p
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-80px' }}
        transition={{ duration: 0.5, delay: 0.15 }}
        className="mt-6 max-w-2xl text-base font-normal leading-7 text-white/60 md:text-lg"
      >
        Get started and see how Todus helps you process your inbox in a fraction of the time.
      </motion.p>
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-80px' }}
        transition={{ duration: 0.5, delay: 0.3 }}
        className="mt-10"
      >
        <a href="/login">
          <Button className="h-10 cursor-pointer bg-white px-6 text-black hover:bg-white/90">
            Get Started
          </Button>
        </a>
      </motion.div>
    </section>
  );
}
