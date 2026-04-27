import { useEffect, useRef, useState } from 'react';

export function useReducedMotion() {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    const mql = window.matchMedia('(prefers-reduced-motion: reduce)');
    setReduced(mql.matches);
    const handler = (e) => setReduced(e.matches);
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, []);

  return reduced;
}

export function useInView(options) {
  const ref = useRef(null);
  const [inView, setInView] = useState(false);
  const { threshold = 0.1, root = null, rootMargin = '0px' } = options ?? {};

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setInView(true);
          observer.disconnect();
        }
      },
      { threshold, root, rootMargin },
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [threshold, root, rootMargin]);

  return { ref, inView };
}
