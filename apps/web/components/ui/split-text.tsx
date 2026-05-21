import { motion, useInView } from 'motion/react';
import { useRef, Fragment } from 'react';

interface SplitTextProps {
  text: string;
  className?: string;
  delay?: number;
  stagger?: number;
}

export function SplitText({ text, className, delay = 0, stagger = 0.04 }: SplitTextProps) {
  const ref = useRef<HTMLSpanElement>(null);
  const isInView = useInView(ref, { once: true, margin: '-40px 0px' });
  const words = text.split(' ');

  return (
    <span ref={ref} className={className} aria-label={text}>
      {words.map((word, i) => (
        <Fragment key={`${word}-${i}`}>
          <span className="inline-block overflow-hidden" aria-hidden="true">
            <motion.span
              className="inline-block will-change-transform"
              initial={{ y: '110%' }}
              animate={isInView ? { y: 0 } : { y: '110%' }}
              transition={{
                duration: 0.55,
                delay: delay + i * stagger,
                ease: [0.22, 1, 0.36, 1],
              }}
            >
              {word}
            </motion.span>
          </span>
          {i < words.length - 1 && ' '}
        </Fragment>
      ))}
    </span>
  );
}
