/**
 * ThemeContext — provides semantic design tokens to all native screens.
 * Uses system color scheme and exposes the correct light/dark token set
 * from @zero/design-tokens (same values as the web app).
 */
import { semanticColors, spacing, typography, radius, type ColorMode } from '@zero/design-tokens';
import { createContext, useContext, useMemo, type PropsWithChildren } from 'react';
import { useColorScheme } from 'react-native';

export type ThemeContextValue = {
  colorMode: ColorMode;
  colors: typeof semanticColors.light | typeof semanticColors.dark;
  spacing: typeof spacing;
  typography: typeof typography;
  radius: typeof radius;
  isDark: boolean;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: PropsWithChildren) {
  const systemColorScheme = useColorScheme();
  const colorMode: ColorMode = systemColorScheme === 'dark' ? 'dark' : 'light';

  const value = useMemo<ThemeContextValue>(
    () => ({
      colorMode,
      colors: semanticColors[colorMode],
      spacing,
      typography,
      radius,
      isDark: colorMode === 'dark',
    }),
    [colorMode],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return ctx;
}
