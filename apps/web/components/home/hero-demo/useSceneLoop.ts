import { useEffect, useRef, useState } from 'react';

const RESUME_AFTER_MS = 8000;

export function useSceneLoop<T extends string>(
  scenes: readonly T[],
  intervalMs = 4500,
  enabled = true,
) {
  const [activeScene, setActiveScene] = useState<T>(scenes[0]);
  const pausedUntilRef = useRef(0);

  useEffect(() => {
    if (!enabled) return;
    const id = setInterval(() => {
      if (Date.now() < pausedUntilRef.current) return;
      setActiveScene((current) => {
        const idx = scenes.indexOf(current);
        return scenes[(idx + 1) % scenes.length];
      });
    }, intervalMs);
    return () => clearInterval(id);
  }, [enabled, intervalMs, scenes]);

  const selectScene = (id: T) => {
    pausedUntilRef.current = Date.now() + RESUME_AFTER_MS;
    setActiveScene(id);
  };

  return { activeScene, selectScene };
}
