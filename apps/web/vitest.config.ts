import { defineConfig } from 'vitest/config';

// Standalone vitest config for pure unit tests. Intentionally does NOT load the
// app's vite.config (cloudflare / react-router / paraglide plugins) — these
// tests cover framework-free logic in `lib/`, so a plain node environment is
// both correct and fast.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['lib/**/*.test.ts'],
  },
});
