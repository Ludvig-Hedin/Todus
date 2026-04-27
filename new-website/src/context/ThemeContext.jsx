import React, { createContext, useContext, useEffect, useState } from 'react';

const THEME_KEY = 'todus-theme';

const ThemeContext = createContext(undefined);

function getSystemTheme() {
  if (typeof window === 'undefined') return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function getInitialTheme() {
  if (typeof window === 'undefined') return 'system';
  try {
    const stored = localStorage.getItem(THEME_KEY);
    if (stored && ['light', 'dark', 'system'].includes(stored)) return stored;
  } catch {}
  return 'system';
}

export function ThemeProvider({ children }) {
  const [theme, setThemeState] = useState('system');
  const [resolvedTheme, setResolvedTheme] = useState('light');
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const initial = getInitialTheme();
    setThemeState(initial);
    setResolvedTheme(initial === 'system' ? getSystemTheme() : initial);
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!mounted) return;
    const resolved = theme === 'system' ? getSystemTheme() : theme;
    setResolvedTheme(resolved);

    const root = document.documentElement;
    if (resolved === 'dark') {
      root.classList.add('dark');
    } else {
      root.classList.remove('dark');
    }

    try {
      localStorage.setItem(THEME_KEY, theme);
    } catch {}
  }, [theme, mounted]);

  useEffect(() => {
    if (!mounted || theme !== 'system') return;
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = (e) => {
      const resolved = e.matches ? 'dark' : 'light';
      setResolvedTheme(resolved);
      const root = document.documentElement;
      if (resolved === 'dark') root.classList.add('dark');
      else root.classList.remove('dark');
    };
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, [theme, mounted]);

  const setTheme = (t) => setThemeState(t);

  return (
    <ThemeContext.Provider value={{ theme, resolvedTheme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider');
  return ctx;
}
